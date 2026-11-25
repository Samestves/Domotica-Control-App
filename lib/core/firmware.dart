import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../models/device.dart';
import 'updater.dart';

/// Una versión del programa de una placa, publicada en la página del instalador (placas.json).
class BoardRelease {
  /// `casa` o `carro`: la placa a la que va.
  final String board;

  /// Por ejemplo `casa-0.9`.
  final String version;

  /// El programa (app.bin): de dónde se baja, cuánto pesa y su huella MD5.
  final Uri url;
  final int size;
  final String md5;

  const BoardRelease({required this.board, required this.version, required this.url, required this.size, required this.md5});

  String get sizeText => '${(size / 1000000).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Los programas de las placas: qué versión está publicada, si una placa tiene una más vieja, y la descarga.
///
/// La lista es la misma que usa la página del instalador: cambiar la versión allí la cambia aquí.
/// Por Wi-Fi solo se envía `app.bin`: lo demás (arranque y tabla de memoria) no cambia entre versiones.
class Firmware {
  static const catalogUrl = 'https://samestves.github.io/Domotica-Control-App/placas.json';
  static const _app = MethodChannel('control_domotica/app');

  /// El nombre de cada placa en la lista, según el tipo de dispositivo de la app.
  static String boardId(Profile p) => switch (p) {
        Profile.casa => 'casa',
        Profile.carro => 'carro',
      };

  /// La placa de un dispositivo, si se puede actualizar por Wi-Fi: se sabe su versión (desde casa-0.9 y
  /// carro-0.5 la dicen al conectarse) y no es una placa demo.
  static bool canUpdate(SavedDevice d) => d.transport != Transport.demo && d.firmware != null;

  // ---------------------------------------------------------------- versiones

  /// `casa-0.9` → [0, 9]; `carro-0.10` → [0, 10]. null si no tiene números.
  static List<int>? numbers(String version) {
    final m = RegExp(r'(\d+(?:\.\d+)*)$').firstMatch(version.trim());
    return m?.group(1)!.split('.').map(int.parse).toList();
  }

  /// true si [published] es más nueva que [installed] y son de la misma placa (`casa-…` con `casa-…`).
  static bool isNewer(String published, String installed) {
    String kind(String v) => v.trim().replaceFirst(RegExp(r'-?\d+(?:\.\d+)*$'), '');
    final a = numbers(published), b = numbers(installed);
    if (a == null || b == null || kind(published) != kind(installed)) return false;
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Lee placas.json: placa → su versión publicada. Las direcciones de los archivos son relativas a la lista.
  static Map<String, BoardRelease> parseCatalog(Map<String, dynamic> json, {Uri? base}) {
    final from = base ?? Uri.parse(catalogUrl);
    final out = <String, BoardRelease>{};
    for (final b in json['boards'] as List<dynamic>? ?? const []) {
      if (b is! Map<String, dynamic>) continue;
      final id = b['id'] as String?, version = b['version'] as String?;
      final files = b['files'] as List<dynamic>? ?? const [];
      final app = files.whereType<Map<String, dynamic>>().where((f) => f['name'] == 'app.bin').firstOrNull;
      final url = app?['url'] as String?, size = (app?['size'] as num?)?.toInt(), md5 = app?['md5'] as String?;
      if (id == null || version == null || url == null || size == null || size <= 0 || md5 == null) continue;
      out[id] = BoardRelease(board: id, version: version, url: from.resolve(url), size: size, md5: md5.toLowerCase());
    }
    return out;
  }

  /// La versión publicada que le sirve a [d], o null si ya la tiene (o no se puede actualizar por Wi-Fi).
  static BoardRelease? updateFor(SavedDevice d, Map<String, BoardRelease> catalog) {
    final r = catalog[boardId(d.profile)];
    final mine = d.firmware;
    if (r == null || mine == null || !canUpdate(d)) return null;
    return isNewer(r.version, mine) ? r : null;
  }

  // ---------------------------------------------------------------- red

  /// Lee la lista publicada. Sin internet lanza [UpdateProblem].
  static Future<Map<String, BoardRelease>> fetchCatalog() async {
    final body = await _get(Uri.parse(catalogUrl), (bytes) => utf8.decode(bytes));
    try {
      return parseCatalog(jsonDecode(body) as Map<String, dynamic>);
    } on FormatException {
      throw const UpdateProblem('La lista de versiones llegó dañada. Prueba más tarde.');
    }
  }

  /// El programa ya bajado y revisado, o null si todavía no está en el teléfono.
  static Future<List<int>?> cached(BoardRelease r) async {
    final f = await _file(r);
    if (f == null || !await f.exists() || await f.length() != r.size) return null;
    final bytes = await f.readAsBytes();
    return md5.convert(bytes).toString() == r.md5 ? bytes : null;
  }

  /// Baja el programa (o usa el que ya está), revisa tamaño y huella, y lo guarda para cuando la app esté
  /// unida a la red de la placa (que no tiene internet). [onProgress] recibe de 0 a 1.
  static Future<List<int>> download(BoardRelease r, [void Function(double)? onProgress]) async {
    final ready = await cached(r);
    if (ready != null) return ready;
    final bytes = await _get(r.url, (b) => b, expected: r.size, onProgress: onProgress);
    if (bytes.length != r.size || md5.convert(bytes).toString() != r.md5) {
      throw const UpdateProblem('La descarga llegó incompleta o dañada. Prueba otra vez con mejor señal.');
    }
    final f = await _file(r);
    if (f != null) {
      await f.parent.create(recursive: true);
      // Las versiones viejas ya no sirven: se borran para no ocupar espacio.
      for (final old in f.parent.listSync().whereType<File>().where((x) => x.path != f.path && x.path.contains('${r.board}-'))) {
        try {
          old.deleteSync();
        } catch (_) {}
      }
      await f.writeAsBytes(bytes, flush: true);
    }
    return bytes;
  }

  static Future<File?> _file(BoardRelease r) async {
    try {
      final dir = await _app.invokeMethod<String>('carpetaActualizaciones');
      return dir == null ? null : File('$dir/placas/${r.version}.bin');
    } catch (_) {
      return null; // en las pruebas no hay carpeta: se baja cada vez
    }
  }

  static Future<T> _get<T>(Uri url, T Function(List<int>) convert, {int? expected, void Function(double)? onProgress}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(url);
      req.headers.set(HttpHeaders.userAgentHeader, 'control-domotica-app');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateProblem('La página de versiones respondió ${res.statusCode}. Prueba más tarde.');
      }
      final total = expected ?? (res.contentLength > 0 ? res.contentLength : 0);
      final bytes = <int>[];
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        bytes.addAll(chunk);
        if (total > 0) onProgress?.call((bytes.length / total).clamp(0.0, 1.0));
      }
      return convert(bytes);
    } on SocketException {
      throw const UpdateProblem(Updater.offline);
    } on TimeoutException {
      throw const UpdateProblem(Updater.offline);
    } on HandshakeException {
      throw const UpdateProblem(Updater.offline);
    } finally {
      client.close();
    }
  }
}

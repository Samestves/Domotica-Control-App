import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../version.dart';

/// Una versión publicada en GitHub: una «Release» con el APK adjunto.
class AppRelease {
  /// La etiqueta de la versión, por ejemplo `v0.9.1+21` (versión + número de compilación).
  final String tag;

  /// Título para mostrar, por ejemplo «Alpha 0.9.1».
  final String title;

  /// Qué trae de nuevo (el texto de la Release).
  final String notes;

  /// El APK que sirve para este teléfono, o null si en la Release no hay uno para él.
  final String? apkName;
  final String? apkUrl;
  final int apkSize;

  const AppRelease({required this.tag, required this.title, required this.notes, this.apkName, this.apkUrl, this.apkSize = 0});

  String get sizeText => '${(apkSize / 1000000).toStringAsFixed(1)} MB';
}

/// Problema al buscar o descargar una actualización, con un mensaje listo para mostrar.
class UpdateProblem implements Exception {
  final String message;
  const UpdateProblem(this.message);

  @override
  String toString() => message;
}

/// Actualizaciones de la app desde GitHub, gratis y sin cuenta: la app lee la última Release del repositorio
/// público, descarga el APK que corresponde a este teléfono y abre el instalador de Android.
///
/// Android siempre muestra su propia ventana para confirmar la instalación: ninguna app normal puede saltársela.
class Updater {
  /// Repositorio público donde se publican las versiones (ver docs/ACTUALIZACIONES.md).
  static const repo = 'Samestves/Domotica-Control-App';
  static const releasesPage = 'https://github.com/$repo/releases';

  static const _ch = MethodChannel('control_domotica/app');
  static const _userAgent = 'control-domotica-app';

  static const offline =
      'Sin internet. Si el teléfono está unido a la red de una placa (Casa Domotica o Carrito 4x4), desconéctala y prueba otra vez.';

  // ---------------------------------------------------------------- versiones

  /// «v0.9.1+21» → versión [0, 9, 1] y compilación 21. «0.9.1» → sin compilación. null si no es una versión.
  static ({List<int> version, int? build})? parseTag(String tag) {
    final m = RegExp(r'^[vV]?(\d+)\.(\d+)(?:\.(\d+))?(?:\+(\d+))?$').firstMatch(tag.trim());
    if (m == null) return null;
    return (
      version: [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3] ?? '0')],
      build: m[4] == null ? null : int.parse(m[4]!),
    );
  }

  /// La versión instalada: «Alpha 0.9.0» → [0, 9, 0].
  static List<int> installedVersion([String text = appVersion]) {
    final m = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(text);
    if (m == null) return const [0, 0, 0];
    return [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3] ?? '0')];
  }

  /// true si la versión de [tag] es más nueva que la instalada.
  static bool isNewer(String tag, {String current = appVersion, int currentBuild = appBuild}) {
    final t = parseTag(tag);
    if (t == null) return false;
    final mine = installedVersion(current);
    for (var i = 0; i < 3; i++) {
      if (t.version[i] != mine[i]) return t.version[i] > mine[i];
    }
    final build = t.build;
    return build != null && build > currentBuild;
  }

  /// Elige el APK de la Release que sirve para este teléfono ([abi] es, por ejemplo, `arm64-v8a`).
  /// Un APK de otro procesador no se instalaría, así que si no hay uno que sirva se usa el universal
  /// (el que no dice procesador), y si tampoco hay, ninguno.
  static Map<String, dynamic>? pickApk(List<dynamic> assets, String? abi) {
    final apks = [
      for (final a in assets)
        if (a is Map<String, dynamic> && (a['name'] as String? ?? '').toLowerCase().endsWith('.apk')) a,
    ];
    String name(Map<String, dynamic> a) => (a['name'] as String).toLowerCase();
    final markers = {
      'arm64-v8a': ['arm64'],
      'armeabi-v7a': ['armeabi', 'v7a'],
      'x86_64': ['x86_64', 'x64'],
    };
    for (final marker in markers[abi] ?? const <String>[]) {
      for (final a in apks) {
        if (name(a).contains(marker)) return a;
      }
    }
    const anyAbi = ['arm64', 'armeabi', 'v7a', 'x86'];
    for (final a in apks) {
      if (!anyAbi.any(name(a).contains)) return a; // universal
    }
    return null;
  }

  /// Lee la respuesta de GitHub (`/releases/latest`).
  static AppRelease? parseRelease(Map<String, dynamic> json, String? abi) {
    final tag = json['tag_name'] as String?;
    if (tag == null || parseTag(tag) == null) return null;
    final apk = pickApk(json['assets'] as List<dynamic>? ?? const [], abi);
    final title = (json['name'] as String?)?.trim();
    return AppRelease(
      tag: tag,
      title: title == null || title.isEmpty ? 'Versión ${tag.replaceFirst(RegExp('^[vV]'), '')}' : title,
      notes: (json['body'] as String? ?? '').trim(),
      apkName: apk?['name'] as String?,
      apkUrl: apk?['browser_download_url'] as String?,
      apkSize: (apk?['size'] as num?)?.toInt() ?? 0,
    );
  }

  // ---------------------------------------------------------------- red

  /// Busca la última versión publicada. Devuelve null si la instalada ya es la más nueva
  /// (o si todavía no hay ninguna publicada).
  static Future<AppRelease?> check() async {
    final abi = await _invoke<String>('abi');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases/latest'));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, _userAgent);
      final res = await req.close().timeout(const Duration(seconds: 12));
      if (res.statusCode == 404) {
        await res.drain<void>();
        return null; // el repositorio todavía no tiene versiones publicadas
      }
      if (res.statusCode == 403 || res.statusCode == 429) {
        await res.drain<void>();
        throw const UpdateProblem('GitHub pide esperar un rato antes de volver a preguntar. Prueba en unos minutos.');
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateProblem('GitHub respondió ${res.statusCode}. Prueba más tarde.');
      }
      final body = await res.transform(utf8.decoder).join();
      final release = parseRelease(jsonDecode(body) as Map<String, dynamic>, abi);
      return release != null && isNewer(release.tag) ? release : null;
    } on SocketException {
      throw const UpdateProblem(offline);
    } on TimeoutException {
      throw const UpdateProblem(offline);
    } on HandshakeException {
      throw const UpdateProblem(offline);
    } on FormatException {
      throw const UpdateProblem('GitHub respondió algo que la app no entiende. Prueba más tarde.');
    } finally {
      client.close();
    }
  }

  /// Descarga el APK a la carpeta de la app. [onProgress] recibe de 0 a 1. Devuelve la ruta del archivo.
  static Future<String> download(AppRelease r, void Function(double progress) onProgress) async {
    final url = r.apkUrl;
    if (url == null) throw const UpdateProblem('Esta versión no tiene un APK para este teléfono.');
    final dir = await _invoke<String>('carpetaActualizaciones');
    if (dir == null) throw const UpdateProblem('Este teléfono no permite actualizar desde la app.');
    // Las descargas viejas ya no sirven: se borran para no ocupar espacio.
    for (final old in Directory(dir).listSync().whereType<File>()) {
      try {
        old.deleteSync();
      } catch (_) {}
    }
    final file = File('$dir/${r.apkName ?? 'control-domotica.apk'}');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    IOSink? sink;
    try {
      final req = await client.getUrl(Uri.parse(url)); // GitHub redirige al archivo: se sigue solo
      req.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw UpdateProblem('No se pudo descargar (GitHub respondió ${res.statusCode}).');
      }
      final total = res.contentLength > 0 ? res.contentLength : r.apkSize;
      sink = file.openWrite();
      var got = 0;
      // Si deja de llegar información por 30 s, se corta.
      await for (final chunk in res.timeout(const Duration(seconds: 30))) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got / total).clamp(0.0, 1.0));
      }
      await sink.close();
      sink = null;
      if (r.apkSize > 0 && await file.length() != r.apkSize) {
        throw const UpdateProblem('La descarga quedó incompleta. Prueba otra vez con mejor señal.');
      }
      onProgress(1);
      return file.path;
    } on SocketException {
      throw const UpdateProblem(offline);
    } on TimeoutException {
      throw const UpdateProblem('La descarga se detuvo. Prueba otra vez con mejor señal.');
    } on HandshakeException {
      throw const UpdateProblem(offline);
    } finally {
      await sink?.close();
      client.close();
    }
  }

  // ---------------------------------------------------------------- instalar (Android)

  /// Android pide permitir una vez que esta app instale actualizaciones («Instalar apps desconocidas»).
  static Future<bool> canInstall() async => await _invoke<bool>('puedeInstalar') ?? false;

  /// Abre el ajuste de Android para permitir que esta app instale actualizaciones.
  static Future<void> openInstallPermission() => _invoke<void>('permisoInstalar');

  /// Abre el instalador de Android con el APK descargado. Android pregunta «¿Instalar?» y la app se reemplaza.
  static Future<void> install(String path) async {
    try {
      await _ch.invokeMethod('instalarApk', {'ruta': path});
    } on PlatformException catch (e) {
      throw UpdateProblem(e.message ?? 'No se pudo abrir el instalador de Android.');
    } on MissingPluginException {
      throw const UpdateProblem('Este teléfono no permite actualizar desde la app.');
    }
  }

  static Future<T?> _invoke<T>(String method) async {
    try {
      return await _ch.invokeMethod<T>(method);
    } catch (_) {
      return null;
    }
  }
}

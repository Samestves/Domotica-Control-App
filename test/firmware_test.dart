import 'dart:async';

import 'package:control_domotica/core/board_update.dart';
import 'package:control_domotica/core/firmware.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/core/protocol.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Versiones de las placas', () {
    test('compara números, no letras, y solo de la misma placa', () {
      expect(Firmware.isNewer('casa-0.9', 'casa-0.8'), isTrue);
      expect(Firmware.isNewer('casa-0.10', 'casa-0.9'), isTrue, reason: '10 es más que 9 aunque como texto sea menor');
      expect(Firmware.isNewer('casa-1.0', 'casa-0.12'), isTrue);
      expect(Firmware.isNewer('casa-0.9', 'casa-0.9'), isFalse);
      expect(Firmware.isNewer('casa-0.8', 'casa-0.9'), isFalse, reason: 'nunca se ofrece una más vieja');
      expect(Firmware.isNewer('carro-0.9', 'casa-0.5'), isFalse, reason: 'el programa del carrito no va en la casa');
      expect(Firmware.isNewer('casa-0.9', 'alpha-0.6'), isFalse);
      expect(Firmware.isNewer('basura', 'casa-0.8'), isFalse);
    });

    test('lee la lista de la página del instalador', () {
      final catalog = Firmware.parseCatalog({
        'boards': [
          {
            'id': 'casa',
            'version': 'casa-0.9',
            'files': [
              {'name': 'bootloader.bin', 'url': 'firmware/casa-0.9/bootloader.bin', 'size': 18960, 'md5': 'aa'},
              {'name': 'app.bin', 'url': 'firmware/casa-0.9/app.bin', 'size': 1517888, 'md5': 'ABCDEF'},
            ],
          },
          {'id': 'carro', 'version': 'carro-0.5', 'files': []}, // sin app.bin: no sirve para Wi-Fi
          'basura',
        ],
      }, base: Uri.parse('https://ejemplo.github.io/Domotica-Control-App/placas.json'));
      expect(catalog.keys, ['casa']);
      final casa = catalog['casa']!;
      expect(casa.url.toString(), 'https://ejemplo.github.io/Domotica-Control-App/firmware/casa-0.9/app.bin');
      expect(casa.size, 1517888);
      expect(casa.md5, 'abcdef');
      expect(casa.sizeText, '1,5 MB');
    });

    test('ofrece la versión nueva solo a placas que dicen la suya y no son demo', () {
      final catalog = {'casa': _release('casa-0.9', const [])};
      SavedDevice casa({String? firmware, Transport t = Transport.ble}) =>
          SavedDevice(id: 'x', name: 'Casa', profile: Profile.casa, transport: t, firmware: firmware);
      expect(Firmware.updateFor(casa(firmware: 'casa-0.8'), catalog)?.version, 'casa-0.9');
      expect(Firmware.updateFor(casa(firmware: 'casa-0.9'), catalog), isNull, reason: 'ya la tiene');
      expect(Firmware.updateFor(casa(), catalog), isNull, reason: 'anterior a casa-0.9: se actualiza por cable');
      expect(Firmware.updateFor(casa(firmware: 'casa-0.8', t: Transport.demo), catalog), isNull);
      final carro = SavedDevice(id: 'y', name: 'Carro', profile: Profile.carro, transport: Transport.ble, firmware: 'carro-0.5');
      expect(Firmware.updateFor(carro, catalog), isNull, reason: 'no hay versión publicada para el carrito');
    });

    test('la versión que dice la placa se guarda con el dispositivo', () {
      final d = SavedDevice(id: 'x', name: 'Casa', profile: Profile.casa, transport: Transport.ble, firmware: 'casa-0.9');
      expect(SavedDevice.fromJson(d.toJson()).firmware, 'casa-0.9');
      expect(SavedDevice.fromJson({...d.toJson()}..remove('firmware')).firmware, isNull, reason: 'lo guardado antes de 0.9.6');
    });
  });

  group('Actualizar una placa por Wi-Fi', () {
    final program = List<int>.generate(50000, (i) => (i * 7 + 3) % 256);

    test('envía el programa, la placa lo revisa, se reinicia y la app confirma la versión nueva', () async {
      final board = _Board(version: 'casa-0.8', key: '1234');
      final (job, session) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.error, isNull);
      expect(job.step, BoardUpdateStep.done);
      expect(board.received, program.length);
      expect(board.version, 'casa-0.9');
      expect(session.device.firmware, 'casa-0.9', reason: 'la placa lo dijo al reconectarse');
      expect(board.progressSeen, isNotEmpty, reason: 'el avance es el que la placa confirma');
      expect(job.progress, 1);
      expect(board.otaLink!.disposed, isTrue, reason: 'la conexión del envío se cierra');
    });

    test('si la huella no coincide, la placa no lo instala y la app lo dice', () async {
      final board = _Board(version: 'casa-0.8', key: '1234', corrupt: true);
      final (job, session) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.step, BoardUpdateStep.failed);
      expect(job.error, contains('no aceptó'));
      expect(board.version, 'casa-0.8');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.linked, isTrue, reason: 'vuelve a quedar conectada como estaba');
    });

    test('si la placa falla a mitad, la app deja de enviar', () async {
      final board = _Board(version: 'casa-0.8', key: '1234', failAt: 20000);
      final (job, _) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.step, BoardUpdateStep.failed);
      expect(job.error, contains('memoria llena'));
      expect(board.received, lessThan(program.length), reason: 'no se manda el resto a una placa que ya dijo que no');
    });

    test('si la versión nueva no arranca y la placa vuelve a la anterior, la app lo avisa', () async {
      final board = _Board(version: 'casa-0.8', key: '1234', rollback: true);
      final (job, _) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.step, BoardUpdateStep.failed);
      expect(job.error, contains('volvió a casa-0.8'));
    });

    test('si la placa tarda en volver tras el reinicio, la app sigue intentando y confirma la versión nueva', () async {
      // Lo que pasó en la maqueta: su red se apaga al reiniciarse y los primeros intentos de conexión fallan.
      final board = _Board(version: 'casa-0.8', key: '1234', downAfterRestart: 5);
      final (job, session) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.error, isNull);
      expect(job.step, BoardUpdateStep.done, reason: 'tres reintentos de la conexión no alcanzan: la actualización no se rinde');
      expect(session.device.firmware, 'casa-0.9');
    });

    test('si la placa no vuelve a tiempo queda «instalada», no fallida, y se confirma cuando vuelve', () async {
      final board = _Board(version: 'casa-0.8', key: '1234', downAfterRestart: 1000);
      final (job, session) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.step, BoardUpdateStep.installed, reason: 'la placa ya revisó el programa: no es un fallo');
      expect(job.busy, isFalse);
      expect(job.error, isNull);

      board.downAfterRestart = 0; // la placa vuelve: el usuario se conecta cuando quiere
      await session.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(job.step, BoardUpdateStep.done, reason: 'en cuanto dice casa-0.9 se da por buena');
    });

    test('si después de quedar «instalada» la placa dice la versión vieja, la app lo avisa', () async {
      final board = _Board(version: 'casa-0.8', key: '1234', downAfterRestart: 1000, rollback: true);
      final (job, session) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.step, BoardUpdateStep.installed);
      board.downAfterRestart = 0;
      await session.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(job.step, BoardUpdateStep.failed);
      expect(job.error, contains('volvió a casa-0.8'));
    });

    test('sin la clave correcta no se envía nada', () async {
      final board = _Board(version: 'casa-0.8', key: '9999');
      final (job, _) = await _job(board, _release('casa-0.9', program));
      await job.run();
      expect(job.step, BoardUpdateStep.failed);
      expect(job.error, contains('clave'));
      expect(board.received, 0);
    });
  });
}

BoardRelease _release(String version, List<int> program) => BoardRelease(
      board: 'casa',
      version: version,
      url: Uri.parse('https://ejemplo/app.bin'),
      size: program.length,
      md5: md5.convert(program).toString(),
    );

/// Una placa conectada como siempre (por Bluetooth) y lista para actualizar.
Future<(BoardUpdate, Session)> _job(_Board board, BoardRelease r) async {
  final d = SavedDevice(id: 'casa', name: 'Casa', profile: Profile.casa, transport: Transport.ble, clave: '1234', firmware: board.version);
  final session = Session(d, linkFor: (_) => _SessionLink(board));
  addTearDown(session.dispose);
  final program = List<int>.generate(r.size, (i) => (i * 7 + 3) % 256);
  final job = BoardUpdate(
    session,
    r,
    linkFor: (_) => board.otaLink = _OtaLink(board),
    download: (_, onProgress) async {
      onProgress(1);
      return program;
    },
    replyTimeout: const Duration(milliseconds: 300),
    sendTimeout: const Duration(seconds: 2),
    restartDelay: Duration.zero,
    versionTimeout: const Duration(seconds: 2),
    reconnectEvery: const Duration(milliseconds: 50),
  );
  await session.connect();
  return (job, session);
}

/// Una placa con nuestro programa: su versión, su clave y lo que recibe por Wi-Fi.
class _Board {
  String version;
  final String key;
  final bool corrupt, rollback;
  final int? failAt;

  /// Intentos de conexión que fallan después del reinicio, mientras su red vuelve a aparecer.
  int downAfterRestart;
  bool restarted = false;
  _Board({required this.version, required this.key, this.corrupt = false, this.rollback = false, this.failAt, this.downAfterRestart = 0});

  _OtaLink? otaLink;
  int received = 0;
  final progressSeen = <int>[];
}

/// La conexión de siempre: entrega la clave y, con SYNC, la placa dice su versión.
class _SessionLink extends DeviceLink {
  final _Board board;
  _SessionLink(this.board);

  @override
  Future<void> connect() async {
    if (board.restarted && board.downAfterRestart > 0) {
      board.downAfterRestart--;
      return setState(LinkState.error, 'No se pudo unir a «Casa Domotica».');
    }
    setState(LinkState.connected);
  }

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {
    if (line == 'PING') return emitLine('PONG');
    if (line.startsWith('AUTH:')) return emitLine('AUTH:OK');
    if (line == 'SYNC') emitLine('VER:${board.version}');
  }
}

/// La conexión del envío, con las mismas reglas que firmware/casa_esp32/ota.h.
class _OtaLink extends DeviceLink {
  final _Board board;
  _OtaLink(this.board);
  bool authed = false, disposed = false, receiving = false, draining = false;
  int size = 0;
  String expectedMd5 = '';
  final data = <int>[];
  int reported = 0;

  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }

  @override
  Future<void> sendLine(String line) async {
    final m = Msg.parse(line);
    if (m.kind == 'AUTH') {
      authed = m.value == board.key;
      return emitLine(authed ? 'AUTH:OK' : 'AUTH:MAL:2');
    }
    if (m.kind == 'OTA' && authed) {
      final parts = m.value.split(':');
      size = int.parse(parts[0]);
      expectedMd5 = parts[1];
      receiving = true;
      emitLine('OTA:LISTO');
    }
  }

  @override
  Future<void> sendBytes(List<int> chunk) async {
    await Future<void>.delayed(Duration.zero);
    if (draining) return; // después de un error descarta lo que llega, como ota.h
    if (!receiving) throw StateError('la placa no esperaba bytes');
    board.received += chunk.length;
    data.addAll(chunk);
    final failAt = board.failAt;
    if (failAt != null && data.length >= failAt) {
      receiving = false;
      draining = true;
      return emitLine('OTA:ERR:memoria llena');
    }
    if (data.length < size) {
      final pct = data.length * 100 ~/ size;
      if (pct >= reported + 5) {
        reported = pct;
        board.progressSeen.add(pct);
        emitLine('OTA:AVANCE:$pct');
      }
      return;
    }
    receiving = false;
    final sum = md5.convert(board.corrupt ? [...data.skip(1), 0] : data).toString();
    if (sum != expectedMd5) return emitLine('OTA:ERR:la huella MD5 no coincide');
    emitLine('OTA:OK');
    board.restarted = true;
    if (!board.rollback) board.version = 'casa-0.9';
    scheduleMicrotask(() => setState(LinkState.disconnected)); // se reinicia
  }
}

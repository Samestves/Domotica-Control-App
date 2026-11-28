import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../state/app_state.dart';
import 'firmware.dart';
import 'link.dart';
import 'protocol.dart';
import 'updater.dart';
import 'wifi_link.dart';
import 'wifi_net.dart';

/// [installed]: la placa recibió el programa completo, revisó su huella y se reinició, pero todavía no volvió a
/// decir su versión (Android pregunta otra vez por su red, la placa tarda en arrancar). No es un fallo: se
/// confirma sola, como [done] o [failed], en cuanto la placa diga su versión.
enum BoardUpdateStep { ready, downloading, connecting, sending, restarting, installed, done, failed }

/// Instala una versión nueva en una placa por Wi-Fi (el lado de la placa está en firmware/casa_esp32/ota.h):
///
/// 1. baja el programa, si todavía no está en el teléfono (hace falta internet);
/// 2. se une a la red propia de la placa y entrega la clave, aunque la placa esté guardada por Bluetooth;
/// 3. le manda el programa; la placa lo escribe en su otro espacio de memoria y revisa la huella MD5;
/// 4. la placa se reinicia y la app se vuelve a conectar como siempre, para comprobar que dice la versión nueva.
///
/// Si algo falla antes del paso 4, la placa sigue con su versión: nunca queda a medias.
class BoardUpdate extends ChangeNotifier {
  final Session session;
  final BoardRelease release;

  /// Para las pruebas: otra conexión en vez del Wi-Fi de verdad, y el programa sin bajarlo de internet.
  final DeviceLink Function(SavedDevice)? linkFor;
  final Future<List<int>> Function(BoardRelease, void Function(double))? download;

  /// Esperas. Las pruebas usan unas más cortas.
  /// [versionTimeout] es cuánto se muestra «La placa se reinicia» antes de pasar a [BoardUpdateStep.installed];
  /// mientras tanto, cada [reconnectEvery] se vuelve a intentar la conexión si quedó parada.
  final Duration replyTimeout, sendTimeout, restartDelay, versionTimeout, reconnectEvery;

  BoardUpdate(
    this.session,
    this.release, {
    this.linkFor,
    this.download,
    this.replyTimeout = const Duration(seconds: 8),
    this.sendTimeout = const Duration(seconds: 90),
    this.restartDelay = const Duration(seconds: 3),
    this.versionTimeout = const Duration(seconds: 90),
    this.reconnectEvery = const Duration(seconds: 4),
  });

  /// Escucha la versión que dice la placa después del reinicio, aunque la espera de [run] ya haya terminado.
  StreamSubscription<Msg>? _versionWatch;

  BoardUpdateStep step = BoardUpdateStep.ready;

  /// De 0 a 1, en la descarga y en el envío (lo que la placa confirma que escribió).
  double progress = 0;
  String? error;

  bool get busy => switch (step) {
        BoardUpdateStep.downloading || BoardUpdateStep.connecting || BoardUpdateStep.sending || BoardUpdateStep.restarting => true,
        BoardUpdateStep.ready || BoardUpdateStep.installed || BoardUpdateStep.done || BoardUpdateStep.failed => false,
      };

  /// Trozos del envío: cada uno sale recién cuando el anterior salió del teléfono.
  static const chunk = 8 * 1024;

  SavedDevice get device => session.device;

  /// La red propia de cada placa (la misma que crea su programa).
  static String boardSsid(Profile p) => switch (p) {
        Profile.casa => WifiNet.boardSsid,
        Profile.carro => 'Carrito 4x4',
      };

  /// Conexión para enviar el programa. Por Wi-Fi, la misma que ya usa el dispositivo; por Bluetooth, la red
  /// propia de la placa: la placa acepta un teléfono por Bluetooth y otro por Wi-Fi a la vez.
  DeviceLink _openLink() {
    final custom = linkFor;
    if (custom != null) return custom(device);
    if (device.transport == Transport.wifi) {
      return WifiLink(device.address, device.port, ssid: device.ssid, password: device.wifiPass);
    }
    final ssid = boardSsid(device.profile);
    return WifiLink(WifiNet.boardIp, WifiNet.boardPort, ssid: ssid, password: WifiNet.defaultPass(ssid));
  }

  void _set(BoardUpdateStep s, [double p = 0]) {
    step = s;
    progress = p;
    notifyListeners();
  }

  Future<void> run() async {
    if (busy) return;
    error = null;
    _stopWatchingVersion();
    DeviceLink? link;
    final wasConnected = session.linked || session.busy;
    try {
      _set(BoardUpdateStep.downloading);
      final bytes = await (download ?? Firmware.download)(release, (p) {
        if (p - progress >= .01 || p == 1) _set(BoardUpdateStep.downloading, p);
      });

      _set(BoardUpdateStep.connecting);
      await session.disconnect(); // la placa acepta un solo teléfono por Wi-Fi: se libera la conexión de siempre
      link = _openLink();
      await link.connect();
      if (link.state != LinkState.connected) {
        throw UpdateProblem(link.lastError ?? 'No se pudo unir a la red de la placa.');
      }
      await _authenticate(link);

      final asked = _expect(link, (m) => m.kind == 'OTA', replyTimeout, 'La placa no respondió al pedido de actualizar.');
      link.sendLine('OTA:${bytes.length}:${release.md5}');
      final ready = await asked;
      if (ready.value != 'LISTO') throw UpdateProblem(_otaError(ready.value));

      _set(BoardUpdateStep.sending);
      await _send(link, bytes);

      _set(BoardUpdateStep.restarting);
      await link.dispose();
      link = null;
      // Una placa guardada por Bluetooth: el teléfono vuelve a su Wi-Fi de siempre mientras la placa se reinicia.
      if (device.transport != Transport.wifi) await WifiNet.releaseIfUnused();
      await Future<void>.delayed(restartDelay);
      await _confirmVersion();
    } on UpdateProblem catch (e) {
      error = e.message;
      _set(BoardUpdateStep.failed);
    } catch (e) {
      error = 'Algo salió mal: $e';
      _set(BoardUpdateStep.failed);
    } finally {
      if (link != null) {
        await link.dispose();
        if (device.transport != Transport.wifi) await WifiNet.releaseIfUnused();
      }
      // Si no se pudo, la placa sigue con su versión: vuelve a quedar conectada como estaba.
      if (step == BoardUpdateStep.failed && wasConnected && !session.linked) unawaited(session.connect());
    }
  }

  /// Entrega la clave guardada. Sin clave la placa no acepta OTA (nadie más puede cambiarle el programa).
  Future<void> _authenticate(DeviceLink link) async {
    // Primero se escucha y después se pregunta: una respuesta rápida no se pierde.
    final reply = _expect(link, (m) => m.kind == 'AUTH', replyTimeout, 'La placa no respondió a la clave.');
    link.sendLine('AUTH:${device.clave ?? ''}');
    final m = await reply;
    final answer = m.value.split(':').first;
    if (answer == 'OK') return;
    throw UpdateProblem(switch (answer) {
      'NUEVA' => 'La placa todavía no tiene clave. Conéctate una vez para crearla y vuelve a intentarlo.',
      'ESPERA' => 'La placa pide esperar por intentos de clave fallidos. Prueba en un rato.',
      _ => 'La clave guardada no sirve. Conéctate, escribe la clave y vuelve a intentarlo.',
    });
  }

  /// Manda el programa de a trozos y espera que la placa lo revise. El avance es el que la placa confirma.
  Future<void> _send(DeviceLink link, List<int> bytes) async {
    final progressSub = link.lines.map(Msg.parse).listen((m) {
      final pct = m.kind == 'OTA' && m.value.startsWith('AVANCE:') ? int.tryParse(m.value.substring(7)) : null;
      if (pct != null) _set(BoardUpdateStep.sending, pct / 100);
    });
    final finished = _expect(
      link,
      (m) => m.kind == 'OTA' && (m.value == 'OK' || m.value.startsWith('ERR')),
      sendTimeout,
      'La placa dejó de responder mientras recibía el programa. Sigue con su versión.',
    );
    var over = false; // la placa ya contestó (bien o mal): no se manda más
    finished.then((_) => over = true, onError: (_) => over = true);
    try {
      for (var i = 0; i < bytes.length && !over; i += chunk) {
        try {
          await link.sendBytes(bytes.sublist(i, min(i + chunk, bytes.length)));
        } on SocketException {
          throw const UpdateProblem('Se cortó el Wi-Fi mientras se enviaba. La placa sigue con su versión: intenta otra vez más cerca.');
        }
      }
      final m = await finished;
      if (m.value != 'OK') throw UpdateProblem(_otaError(m.value));
    } finally {
      await progressSub.cancel();
    }
  }

  /// Después del reinicio: se conecta como siempre y espera que la placa diga su versión. Mientras la placa
  /// vuelve, la conexión se reintenta seguido. Si tarda más que [versionTimeout], queda
  /// [BoardUpdateStep.installed] y se confirma en cuanto la placa diga su versión, cuando sea.
  Future<void> _confirmVersion() async {
    final said = Completer<void>();
    _versionWatch = session.messages.where((m) => m.kind == 'VER').listen((m) {
      _stopWatchingVersion();
      if (m.value == release.version) {
        _set(BoardUpdateStep.done, 1);
      } else {
        error = 'La placa volvió a ${m.value}: la versión nueva no arrancó bien y se descartó sola.';
        _set(BoardUpdateStep.failed);
      }
      if (!said.isCompleted) said.complete();
    });
    // Sin esperar los reintentos de siempre (2, 5 y 10 s, y después se rinde): la placa vuelve en segundos.
    final keepTrying = Timer.periodic(reconnectEvery, (_) {
      if (!session.linked && session.state != LinkState.connecting) unawaited(session.connect());
    });
    unawaited(session.connect());
    try {
      await said.future.timeout(versionTimeout);
    } on TimeoutException {
      _set(BoardUpdateStep.installed, 1);
    } finally {
      keepTrying.cancel();
    }
  }

  void _stopWatchingVersion() {
    _versionWatch?.cancel();
    _versionWatch = null;
  }

  @override
  void dispose() {
    _stopWatchingVersion();
    super.dispose();
  }

  static String _otaError(String value) {
    final why = value.startsWith('ERR:') ? value.substring(4) : value;
    return 'La placa no aceptó la versión nueva ($why). Sigue con la que tenía.';
  }

  /// Espera el próximo mensaje de la placa que cumpla [test]. Si se corta la conexión o pasa [timeout], falla.
  static Future<Msg> _expect(DeviceLink link, bool Function(Msg) test, Duration timeout, String why) {
    final done = Completer<Msg>();
    void fail(String message) {
      if (!done.isCompleted) done.completeError(UpdateProblem(message));
    }

    final timer = Timer(timeout, () => fail(why));
    final lines = link.lines.listen((l) {
      final m = Msg.parse(l);
      if (!done.isCompleted && test(m)) done.complete(m);
    });
    final states = link.states.listen((s) {
      if (s != LinkState.connected) fail(link.lastError ?? 'Se cortó la conexión con la placa. Sigue con su versión.');
    });
    return done.future.whenComplete(() {
      timer.cancel();
      lines.cancel();
      states.cancel();
    });
  }
}

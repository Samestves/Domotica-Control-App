import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show AppLifecycleState, ThemeMode, WidgetsBinding;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/avisos.dart';
import '../core/ble_link.dart';
import '../core/board_update.dart';
import '../core/demo_link.dart';
import '../core/firmware.dart';
import '../core/link.dart';
import '../core/protocol.dart';
import '../core/updater.dart';
import '../core/wifi_link.dart';
import '../core/wifi_net.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../version.dart';

class LogLine {
  final bool incoming;
  final String text;
  final DateTime at;
  LogLine(this.incoming, this.text) : at = DateTime.now();
}

/// En qué va la clave de la casa en la conexión actual.
/// Cómo va un cambio de clave pedido desde la app.
enum ClaveChange {
  /// Enviada: se espera que la placa la confirme.
  saving,

  /// La placa la guardó y este teléfono también.
  done,

  /// No se confirmó (ver [Session.claveChangeError]).
  failed,
}

enum ClaveState {
  /// Esperando la respuesta de la placa.
  checking,

  /// Lista para usar: clave aceptada, o la placa no usa clave.
  ok,

  /// La placa pide la clave y la app no la tiene (o era incorrecta).
  ask,

  /// La casa todavía no tiene clave: hay que crearla.
  create,

  /// Demasiados intentos: hay que esperar.
  locked,
}

/// Estado de una placa mientras la app está abierta: conexión, últimos valores y mensajes.
class Session extends ChangeNotifier {
  final SavedDevice device;
  DeviceLink? _link;
  final Map<int, String> values = {};
  final List<LogLine> log = [];
  String? lastAlert;
  final _subs = <StreamSubscription>[];

  /// Cada mensaje que llega de la placa, ya leído. Sirve para esperar una confirmación (por ejemplo, de una orden de voz).
  final _messages = StreamController<Msg>.broadcast();
  Stream<Msg> get messages => _messages.stream;

  /// Crea la conexión de una placa. Las pruebas pueden pasar otra para simular fallos.
  final DeviceLink Function(SavedDevice) _linkFor;

  /// Se llama cuando cambia algo del dispositivo que hay que guardar (por ejemplo, la clave).
  final void Function()? onDeviceChanged;

  /// Esperas entre reintentos cuando la conexión se cae sola. Después del último, queda «Sin conexión».
  static const retryDelays = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)];
  bool _wantConnected = false;
  int _retries = 0;
  Timer? _retryTimer;

  /// Latido: mientras está conectada, la app pregunta PING cada [heartbeat].
  /// Si la placa no dice nada en [silenceLimit] (se apagó, se alejó), la conexión se da por caída.
  static const heartbeat = Duration(seconds: 3);
  static const silenceLimit = Duration(seconds: 7);
  Timer? _heartbeatTimer;

  /// Latidos seguidos sin que la placa diga nada.
  int _silentBeats = 0;

  /// Si la placa no contesta a la clave en este tiempo, es una placa sin clave (por ejemplo, el carrito).
  static const claveTimeout = Duration(milliseconds: 2500);
  ClaveState clave = ClaveState.checking;

  /// true si esta placa usa clave (contestó a AUTH).
  bool keyed = false;

  /// Explicación para el usuario: clave incorrecta, esperar, clave cambiada...
  String? claveMessage;
  String? _pendingClave;
  Timer? _claveTimer;

  /// Cómo va «Cambiar la clave»: la hoja espera aquí la respuesta de la placa. null si nadie la está cambiando.
  ClaveChange? claveChange;

  /// Por qué no se pudo cambiar la clave (cuando [claveChange] es [ClaveChange.failed]).
  String? claveChangeError;
  Timer? _changeTimer;

  /// Si la placa no confirma la clave nueva en este tiempo, la hoja avisa que no respondió.
  static const changeTimeout = Duration(seconds: 5);

  bool get _changingClave => claveChange == ClaveChange.saving;

  /// Cambia cada vez que el usuario desconecta: un intento de conexión viejo que termina tarde lo nota y se cierra.
  int _generation = 0;
  Future<void>? _opening;

  Session(this.device, {DeviceLink Function(SavedDevice)? linkFor, this.onDeviceChanged})
      : _linkFor = linkFor ?? _defaultLink;

  static DeviceLink _defaultLink(SavedDevice d) => switch (d.transport) {
        Transport.ble => BleLink(d.address),
        Transport.wifi => WifiLink(d.address, d.port, ssid: d.ssid, password: d.wifiPass),
        Transport.demo => DemoLink(d.profile.name),
      };

  /// La conexión está abierta, aunque la placa todavía no haya aceptado la clave.
  bool get linked => _link?.state == LinkState.connected;

  /// Mientras se comprueba la clave se muestra «Conectando…».
  LinkState get state {
    final s = _link?.state ?? LinkState.disconnected;
    return s == LinkState.connected && clave == ClaveState.checking ? LinkState.connecting : s;
  }

  String? get error => _link?.lastError;

  /// Lista para usar: conectada y con la clave aceptada.
  bool get connected => linked && clave == ClaveState.ok;

  /// Conectada, pero esperando que el usuario escriba o cree la clave.
  bool get needsClave => linked && (clave == ClaveState.ask || clave == ClaveState.create || clave == ClaveState.locked);

  /// true mientras la app espera para reintentar una conexión caída.
  bool get retrying => _retryTimer?.isActive ?? false;

  /// true desde que la conexión se cayó sola hasta que vuelve o se acaban los intentos.
  bool get reconnecting => _wantConnected && _retries > 0 && (retrying || state == LinkState.connecting);

  /// Intento de reconexión en curso (1, 2, 3) y cuántos hay.
  int get attempt => _retries;
  int get maxAttempts => retryDelays.length;

  /// Algo está en marcha (conectando o esperando para reintentar): se puede cancelar.
  bool get busy => retrying || state == LinkState.connecting;

  /// Conecta porque el usuario lo pidió. Si después se cae, la app reintenta sola.
  Future<void> connect() async {
    _wantConnected = true;
    _retries = 0;
    _retryTimer?.cancel();
    await _open();
  }

  /// Desconecta (o cancela un intento) porque el usuario lo pidió: no se reintenta.
  Future<void> disconnect() async {
    _wantConnected = false;
    _retries = 0;
    _generation++;
    _opening = null;
    _retryTimer?.cancel();
    _stopHeartbeat();
    await _link?.disconnect();
    // Si era la última placa por Wi-Fi, el teléfono vuelve a su Wi-Fi de siempre.
    if (device.transport == Transport.wifi) await WifiNet.releaseIfUnused();
    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _silentBeats = 0;
    _heartbeatTimer = Timer.periodic(heartbeat, (_) {
      if (!linked) return;
      if (++_silentBeats * heartbeat.inMilliseconds > silenceLimit.inMilliseconds) {
        _stopHeartbeat();
        _link?.fail('La placa dejó de responder. ¿Se apagó o está lejos?');
        return;
      }
      _link?.sendLine('PING'); // sin anotarlo en los mensajes: es solo el latido
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Abre la conexión. Si ya hay un intento en marcha (doble toque en «Conectar»), se espera ese mismo.
  Future<void> _open() {
    final running = _opening;
    if (running != null) return running;
    final f = _openNow(_generation);
    _opening = f;
    f.whenComplete(() {
      if (identical(_opening, f)) _opening = null;
    });
    return f;
  }

  Future<void> _openNow(int generation) async {
    final current = _link?.state;
    if (current == LinkState.connected || current == LinkState.connecting) return;
    await _teardown();
    if (generation != _generation) return; // el usuario canceló mientras se cerraba la anterior
    final link = _linkFor(device);
    _link = link;
    _subs.add(link.states.listen(_onState));
    _subs.add(link.lines.listen(_onLine));
    notifyListeners();
    await link.connect();
    if (_link != link) {
      await link.dispose(); // la reemplazó otro intento: esta queda huérfana y se cierra
      return;
    }
    if (generation != _generation || !_wantConnected) {
      if (linked) await link.disconnect(); // el usuario canceló mientras conectaba
      return;
    }
    if (linked) {
      _retries = 0;
      _startHeartbeat();
      _sendClave('AUTH', device.clave ?? '');
    }
    notifyListeners();
  }

  void _onState(LinkState s) {
    if (s != LinkState.connected) {
      _resetClave();
      _stopHeartbeat();
      _clearPending();
    }
    // Un reintento a la vez: si ya hay uno esperando, otro aviso de error no gasta otro intento.
    if (s == LinkState.error && _wantConnected && !retrying && _retries < retryDelays.length) {
      _retryTimer = Timer(retryDelays[_retries++], _open);
    }
    notifyListeners();
  }

  // ---------- Clave de la casa ----------

  /// Entrega una clave escrita por el usuario.
  void enterClave(String c) => _sendClave('AUTH', c);

  /// Crea la primera clave de la casa.
  void createClave(String c) => _sendClave('CLAVE', c);

  /// Cambia la clave estando ya dentro. La placa responde AUTH:OK y la app guarda la nueva.
  void changeClave(String c) {
    _pendingClave = c;
    claveChange = ClaveChange.saving;
    claveChangeError = null;
    claveMessage = null;
    _changeTimer?.cancel();
    _changeTimer = Timer(changeTimeout, () {
      if (!_changingClave) return;
      _changeFailed('La placa no respondió. Revisa la conexión e intenta otra vez.');
      notifyListeners();
    });
    _addLog(false, 'CLAVE:${'•' * c.length}');
    _link?.sendLine('CLAVE:$c');
    notifyListeners();
  }

  /// El cambio de clave no se confirmó. La clave guardada sigue siendo la de antes.
  void _changeFailed(String why) {
    _changeTimer?.cancel();
    claveChange = ClaveChange.failed;
    claveChangeError = why;
  }

  /// Envía AUTH o CLAVE y espera la respuesta. La clave no se muestra en los mensajes.
  void _sendClave(String kind, String c) {
    _pendingClave = c.isEmpty ? null : c;
    clave = ClaveState.checking;
    claveMessage = null;
    _addLog(false, '$kind:${'•' * c.length}');
    _link?.sendLine('$kind:$c');
    _claveTimer?.cancel();
    _claveTimer = Timer(claveTimeout, _onClaveTimeout);
    notifyListeners();
  }

  void _onClaveTimeout() {
    if (!linked || clave != ClaveState.checking) return;
    if (keyed) {
      clave = ClaveState.ask;
      claveMessage = 'La casa no respondió. Intenta de nuevo.';
      notifyListeners();
    } else {
      _ready(); // no contestó nunca: es una placa sin clave
    }
  }

  void _onClaveReply(String value) {
    keyed = true;
    _claveTimer?.cancel();
    final parts = value.split(':');
    final n = parts.length > 1 ? parts[1] : '';
    if (parts.first != 'OK' && _changingClave) {
      _changeFailed(parts.first == 'PIDE'
          ? 'La placa pidió otra vez la clave actual. Escríbela y vuelve a intentarlo.'
          : 'La placa no aceptó la clave nueva (respondió «$value»).');
    }
    switch (parts.first) {
      case 'OK':
        final p = _pendingClave;
        _pendingClave = null;
        if (p != null && p != device.clave) {
          device.clave = p;
          onDeviceChanged?.call();
        }
        if (clave != ClaveState.ok) {
          _ready();
        } else if (p != null && claveChange != null) {
          // La placa confirmó la clave nueva, aunque sea tarde (después del aviso de que no respondía).
          _changeTimer?.cancel();
          claveChange = ClaveChange.done;
          claveChangeError = null;
          claveMessage = 'Clave cambiada';
        }
      case 'NUEVA':
        _forgetClave();
        clave = ClaveState.create;
      case 'MAL':
        _forgetClave();
        clave = ClaveState.ask;
        claveMessage = 'Clave incorrecta. ${n == '1' ? 'Queda 1 intento' : 'Quedan $n intentos'}.';
      case 'ESPERA':
        _forgetClave();
        clave = ClaveState.locked;
        claveMessage = 'Demasiados intentos. Espera $n segundos.';
        _claveTimer = Timer(Duration(seconds: int.tryParse(n) ?? 30), () {
          if (clave != ClaveState.locked) return;
          clave = ClaveState.ask;
          claveMessage = null;
          notifyListeners();
        });
      case 'PIDE':
        _forgetClave();
        clave = ClaveState.ask;
      default:
        // Una versión del programa que responde algo que esta app no conoce: no se queda «Conectando» para siempre.
        clave = ClaveState.ask;
        claveMessage = 'La placa respondió «$value», que esta versión de la app no entiende.';
    }
  }

  /// La placa ya obedece: le envía los pines guardados y pide el estado real.
  void _ready() {
    clave = ClaveState.ok;
    _pushPinConfig();
    sendRaw('SYNC');
  }

  /// La clave guardada ya no sirve: se borra para no volver a enviarla.
  void _forgetClave() {
    _pendingClave = null;
    if (device.clave == null) return;
    device.clave = null;
    onDeviceChanged?.call();
  }

  void _resetClave() {
    _claveTimer?.cancel();
    clave = ClaveState.checking;
    keyed = false;
    claveMessage = null;
    _pendingClave = null;
    if (_changingClave) {
      _changeFailed('Se cortó la conexión antes de que la placa confirmara. Si al volver no entra, escribe la clave nueva.');
    }
  }

  /// La app es la fuente de verdad de los pines: al conectar, envía a la placa
  /// todos los ajustes guardados, aunque se hayan hecho sin conexión.
  /// En la casa, un servo guardado con un GPIO (antes de casa-0.8) se envía con su canal del PCA9685.
  void _pushPinConfig() {
    device.pins.forEach((vpin, saved) {
      final p = (device.profile == Profile.casa ? casaSpec(vpin)?.pinsFor(device) : null) ?? saved;
      sendRaw(cfgMsg(vpin, p.code, inverted: p.inverted, enabled: p.enabled));
    });
  }

  void _onLine(String line) {
    _silentBeats = 0;
    if (line == 'PONG') return; // respuesta al latido: no hace falta mostrarla
    _addLog(true, line);
    final m = Msg.parse(line);
    if (!_messages.isClosed) _messages.add(m);
    if (m.kind == 'AUTH') {
      _onClaveReply(m.value);
    } else if (m.kind == 'VER') {
      // La placa dice su versión (desde casa-0.9 y carro-0.5): así la app sabe si hay una más nueva.
      if (device.firmware != m.value) {
        device.firmware = m.value;
        onDeviceChanged?.call();
      }
    } else if (m.kind == 'ERR' && clave == ClaveState.checking && !keyed && m.value.contains('AUTH')) {
      _ready(); // una versión anterior del programa no conoce la clave
    } else if (m.isPin) {
      values[m.pin!] = m.value;
      _confirmed(m.pin!);
      if (device.profile == Profile.casa && m.pin == CasaPins.siren && m.value == '1') {
        lastAlert = 'Alarma sonando en ${device.name}';
      }
    }
    notifyListeners();
  }

  void _addLog(bool incoming, String text) {
    log.insert(0, LogLine(incoming, text));
    if (log.length > 60) log.removeLast();
  }

  /// Envía un valor a un pin virtual y lo recuerda para mostrarlo en el panel.
  /// Con [confirm], el control queda «enviando» hasta que la placa responda con ese pin.
  ///
  /// Una orden [quiet] que no cambia nada (por ejemplo, la repetición del acelerador cada 200 ms) no avisa a la
  /// pantalla: si no, toda la app se redibujaría varias veces por segundo sin necesidad.
  void send(int pin, Object value, {bool remember = true, bool quiet = false, bool confirm = false}) {
    final line = pinMsg(pin, value);
    final text = value.toString();
    final changed = remember && values[pin] != text;
    if (remember) values[pin] = text;
    if (!quiet) _addLog(false, line);
    if (confirm) expect([pin]);
    _link?.sendLine(line);
    if (!quiet || changed || confirm) notifyListeners();
  }

  // ---------- Confirmación de la placa ----------

  /// Pines enviados que todavía esperan respuesta de la placa.
  final Set<int> pending = {};

  /// Pines que la placa no confirmó a tiempo (se muestran con un aviso unos segundos).
  final Set<int> unconfirmed = {};
  final _pendingTimers = <int, Timer>{};
  static const confirmTimeout = Duration(milliseconds: 2500);

  /// Marca estos pines como «esperando a la placa». Se limpian al llegar su respuesta.
  void expect(Iterable<int> pins) {
    if (!connected) return;
    for (final p in pins) {
      _pendingTimers[p]?.cancel();
      pending.add(p);
      unconfirmed.remove(p);
      _pendingTimers[p] = Timer(confirmTimeout, () {
        if (!pending.remove(p)) return;
        unconfirmed.add(p);
        notifyListeners();
        _pendingTimers[p] = Timer(const Duration(seconds: 3), () {
          if (unconfirmed.remove(p)) notifyListeners();
        });
      });
    }
    notifyListeners();
  }

  void _confirmed(int pin) {
    if (pending.remove(pin) | unconfirmed.remove(pin)) _pendingTimers.remove(pin)?.cancel();
  }

  void _clearPending() {
    for (final t in _pendingTimers.values) {
      t.cancel();
    }
    _pendingTimers.clear();
    pending.clear();
    unconfirmed.clear();
  }

  void sendRaw(String line) {
    _addLog(false, line);
    _link?.sendLine(line);
    notifyListeners();
  }

  void clearAlert() {
    lastAlert = null;
    notifyListeners();
  }

  Future<void> _teardown() async {
    // Se copia antes de esperar: mientras tanto otra apertura puede agregar las suyas.
    final subs = [..._subs];
    _subs.clear();
    // Todas se cancelan ya (sin esperar entre una y otra): ningún aviso llega a una sesión que se está cerrando.
    await Future.wait(subs.map((s) => s.cancel()));
    await _link?.dispose();
    _link = null;
  }

  @override
  void dispose() {
    _wantConnected = false;
    _generation++; // una apertura que todavía no terminó lo nota y no sigue
    _retryTimer?.cancel();
    _stopHeartbeat();
    _clearPending();
    _claveTimer?.cancel();
    _changeTimer?.cancel();
    _messages.close();
    _teardown();
    super.dispose();
  }
}

class AppState extends ChangeNotifier {
  static const _key = 'devices_v1';
  static const _backupKey = 'devices_v1_respaldo';
  final List<SavedDevice> devices = [];

  /// Dispositivos guardados que esta versión no sabe leer (por ejemplo, de una versión más nueva de la app).
  /// No se muestran, pero se vuelven a guardar tal cual para no perderlos.
  final List<Object?> _unreadable = [];
  final Map<String, Session> _sessions = {};

  /// Para los tests: conexiones simuladas en vez de Bluetooth o Wi-Fi.
  final DeviceLink Function(SavedDevice)? linkFor;
  AppState({this.linkFor});

  Session session(SavedDevice d) => _sessions.putIfAbsent(d.id, () {
        final s = Session(d, linkFor: linkFor, onDeviceChanged: save);
        s.addListener(notifyListeners);
        return s;
      });

  int get connectedCount => _sessions.values.where((s) => s.connected).length;

  /// Versión nueva publicada en GitHub (null si no hay, o si todavía no se revisó).
  AppRelease? update;

  void setUpdate(AppRelease? r) {
    update = r;
    notifyListeners();
  }

  /// Al abrir la app: revisa en segundo plano si hay una versión nueva de la app o del programa de las placas.
  /// Sin internet no pasa nada (la app se busca a mano en Ajustes; las placas, en la próxima apertura).
  Future<void> checkForUpdateQuietly() async {
    await Future.wait([
      () async {
        try {
          setUpdate(await Updater.check());
        } catch (_) {}
      }(),
      _checkBoards(),
    ]);
    if (update != null || devices.any((d) => boardUpdate(d) != null)) await _askAvisosOnce();
  }

  // ---------- Programa de las placas ----------

  /// Versión publicada de cada placa (`casa`, `carro`), según la página del instalador. Vacío hasta revisar.
  Map<String, BoardRelease> boardReleases = {};

  /// La versión nueva que le sirve a esta placa, o null si ya la tiene (o no se puede actualizar por Wi-Fi).
  BoardRelease? boardUpdate(SavedDevice d) => Firmware.updateFor(d, boardReleases);

  final Map<String, BoardUpdate> _boardJobs = {};

  /// La actualización en curso (o la última) de una placa, para que la hoja la muestre aunque se haya cerrado.
  BoardUpdate? boardJob(SavedDevice d) => _boardJobs[d.id];

  Future<void> _checkBoards() async {
    try {
      boardReleases = await Firmware.fetchCatalog();
      notifyListeners();
    } catch (_) {
      return;
    }
    // Se baja ya, con internet: al actualizar, la app estará unida a la red de la placa, que no tiene.
    for (final d in devices) {
      final r = boardUpdate(d);
      if (r == null) continue;
      try {
        await Firmware.download(r);
      } catch (_) {}
    }
  }

  /// Instala [r] en la placa [d] (ver [BoardUpdate]). Si ya hay una en curso, devuelve esa.
  BoardUpdate updateBoard(SavedDevice d, BoardRelease r) {
    final running = _boardJobs[d.id];
    if (running != null && running.busy) return running;
    final job = BoardUpdate(session(d), r, linkFor: linkFor);
    _boardJobs[d.id] = job;
    job.addListener(notifyListeners);
    job.run().then((_) {
      // Con la app en segundo plano, una notificación cuenta cómo salió.
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return;
      final ok = job.step == BoardUpdateStep.done;
      Avisos.show(ok ? '«${d.name}» quedó actualizada' : 'No se pudo actualizar «${d.name}»',
          ok ? 'Ya tiene ${r.version}.' : 'Sigue con ${d.firmware ?? 'su versión'}. Abre la app para ver qué pasó.');
    });
    return job;
  }

  // ---------- Avisos ----------

  static const _avisosKey = 'avisos_versiones';
  static const _avisosAskedKey = 'avisos_permiso_pedido';

  /// Avisar versiones nuevas con notificaciones, aunque la app esté cerrada (la revisión en Android lee este ajuste).
  bool avisos = true;

  Future<void> setAvisos(bool v) async {
    avisos = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_avisosKey, v);
    await Avisos.schedule(v);
    if (v) await Avisos.askPermission();
  }

  /// La primera vez que aparece una versión nueva, Android pregunta si la app puede avisar: así el permiso se
  /// pide cuando se entiende para qué es, y una sola vez.
  Future<void> _askAvisosOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (!avisos || (prefs.getBool(_avisosAskedKey) ?? false)) return;
    await prefs.setBool(_avisosAskedKey, true);
    await Avisos.askPermission();
  }

  static const _newsKey = 'novedades_vistas';

  /// true si la app se acaba de actualizar y todavía no mostró qué trae esta versión.
  bool newsPending = false;

  /// Anota que las novedades de esta versión ya se mostraron: no vuelven a salir solas.
  Future<void> markNewsSeen() async {
    newsPending = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_newsKey, appBuild);
  }

  static const _showPinsKey = 'ui_show_pins';

  /// Modo técnico: muestra el pin virtual y el GPIO de cada control. Apagado, el panel se ve más limpio.
  bool showPins = false;

  Future<void> setShowPins(bool v) async {
    showPins = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showPinsKey, v);
  }

  static const _themeKey = 'ui_theme';

  /// Claro, oscuro o el del sistema. Aparte del resto del estado, para no redibujar toda la app con cada mensaje.
  final theme = ValueNotifier(ThemeMode.system);
  ThemeMode get themeMode => theme.value;

  Future<void> setThemeMode(ThemeMode m) async {
    theme.value = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, m.name);
  }

  /// Lee lo guardado. Cada dispositivo se lee por separado: si uno está dañado o es de una versión más nueva,
  /// los demás se cargan igual y ese se conserva sin tocar.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    T? read<T>(T? Function() f) {
      try {
        return f();
      } catch (_) {
        return null; // un ajuste guardado con otro tipo: se usa el valor por defecto
      }
    }

    final raw = read(() => prefs.getString(_key));
    // Las novedades salen solo al actualizar: no en la primera instalación (sin nada guardado), ni al volver
    // a una versión vieja. La 0.9.1 no anotaba nada, así que quien viene de ella tiene dispositivos guardados.
    final seen = read(() => prefs.getInt(_newsKey));
    newsPending = seen == null ? raw != null : seen < appBuild;
    if (raw == null && seen == null) await prefs.setInt(_newsKey, appBuild);
    showPins = read(() => prefs.getBool(_showPinsKey)) ?? false;
    avisos = read(() => prefs.getBool(_avisosKey)) ?? true;
    Avisos.schedule(avisos); // sin esperar: Android guarda el horario aunque la app se cierre
    theme.value = ThemeMode.values.asNameMap()[read(() => prefs.getString(_themeKey))] ?? ThemeMode.system;
    devices.clear();
    _unreadable.clear();
    if (raw != null) {
      List<dynamic>? list;
      try {
        list = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        // Todo el texto está dañado: se guarda una copia aparte antes de empezar de cero.
        await prefs.setString(_backupKey, raw);
      }
      for (final e in list ?? const []) {
        try {
          devices.add(SavedDevice.fromJson(e as Map<String, dynamic>));
        } catch (_) {
          _unreadable.add(e);
        }
      }
    }
    if (raw == null) {
      // Primer uso: dos placas demo para que la app no arranque vacía. Si el usuario las borra, no vuelven.
      devices.addAll([
        SavedDevice(id: 'demo-casa', name: 'Casa (demo)', profile: Profile.casa, transport: Transport.demo),
        SavedDevice(id: 'demo-carro', name: 'Auto Robot (demo)', profile: Profile.carro, transport: Transport.demo),
      ]);
      await save();
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([...devices.map((d) => d.toJson()), ..._unreadable]));
  }

  Future<void> add(SavedDevice d) async {
    devices.add(d);
    await save();
    notifyListeners();
  }

  /// Guarda los cambios hechos a un dispositivo ya registrado.
  Future<void> saveChanges() async {
    await save();
    notifyListeners();
  }

  Future<void> remove(SavedDevice d) async {
    // Primero sale de la lista: así ninguna pantalla vuelve a crear su sesión mientras se desconecta.
    devices.removeWhere((x) => x.id == d.id);
    final s = _sessions.remove(d.id);
    if (s != null) {
      s.removeListener(notifyListeners);
      await s.disconnect();
      s.dispose();
    }
    await save();
    notifyListeners();
  }
}

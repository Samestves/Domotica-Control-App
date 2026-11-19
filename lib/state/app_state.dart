import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ble_link.dart';
import '../core/demo_link.dart';
import '../core/link.dart';
import '../core/protocol.dart';
import '../core/wifi_link.dart';
import '../models/device.dart';
import '../models/pins.dart';

class LogLine {
  final bool incoming;
  final String text;
  final DateTime at;
  LogLine(this.incoming, this.text) : at = DateTime.now();
}

/// En qué va la clave de la casa en la conexión actual.
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
    _retryTimer?.cancel();
    _stopHeartbeat();
    await _link?.disconnect();
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

  Future<void> _open() async {
    final current = _link?.state;
    if (current == LinkState.connected || current == LinkState.connecting) return;
    await _teardown();
    final link = _linkFor(device);
    _link = link;
    _subs.add(link.states.listen(_onState));
    _subs.add(link.lines.listen(_onLine));
    notifyListeners();
    await link.connect();
    if (_link != link) return; // se canceló o se reemplazó mientras conectaba
    if (!_wantConnected && linked) {
      await link.disconnect(); // el usuario canceló mientras conectaba
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
    if (s == LinkState.error && _wantConnected && _retries < retryDelays.length) {
      _retryTimer?.cancel();
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
    claveMessage = null;
    _addLog(false, 'CLAVE:${'•' * c.length}');
    _link?.sendLine('CLAVE:$c');
    notifyListeners();
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
    switch (parts.first) {
      case 'OK':
        final p = _pendingClave;
        _pendingClave = null;
        if (p != null && p != device.clave) {
          device.clave = p;
          onDeviceChanged?.call();
        }
        if (clave == ClaveState.ok) {
          claveMessage = 'Clave cambiada';
        } else {
          _ready();
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
  }

  /// La app es la fuente de verdad de los pines: al conectar, envía a la placa
  /// todos los ajustes guardados, aunque se hayan hecho sin conexión.
  void _pushPinConfig() {
    device.pins.forEach((vpin, p) => sendRaw(cfgMsg(vpin, p.gpio, inverted: p.inverted, enabled: p.enabled)));
  }

  void _onLine(String line) {
    _silentBeats = 0;
    if (line == 'PONG') return; // respuesta al latido: no hace falta mostrarla
    _addLog(true, line);
    final m = Msg.parse(line);
    if (!_messages.isClosed) _messages.add(m);
    if (m.kind == 'AUTH') {
      _onClaveReply(m.value);
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
  void send(int pin, Object value, {bool remember = true, bool quiet = false, bool confirm = false}) {
    final line = pinMsg(pin, value);
    if (remember) values[pin] = value.toString();
    if (!quiet) _addLog(false, line);
    if (confirm) expect([pin]);
    _link?.sendLine(line);
    notifyListeners();
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
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _link?.dispose();
    _link = null;
  }

  @override
  void dispose() {
    _wantConnected = false;
    _retryTimer?.cancel();
    _stopHeartbeat();
    _clearPending();
    _claveTimer?.cancel();
    _messages.close();
    _teardown();
    super.dispose();
  }
}

class AppState extends ChangeNotifier {
  static const _key = 'devices_v1';
  final List<SavedDevice> devices = [];
  final Map<String, Session> _sessions = {};

  Session session(SavedDevice d) => _sessions.putIfAbsent(d.id, () {
        final s = Session(d, onDeviceChanged: save);
        s.addListener(notifyListeners);
        return s;
      });

  int get connectedCount => _sessions.values.where((s) => s.connected).length;

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

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    showPins = prefs.getBool(_showPinsKey) ?? false;
    theme.value = ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ?? ThemeMode.system;
    devices.clear();
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        devices.addAll(list.map((e) => SavedDevice.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // Si los datos guardados están dañados, empezamos de cero.
      }
    }
    if (devices.isEmpty) {
      // Primer uso: dos placas demo para que la app no arranque vacía.
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
    await prefs.setString(_key, jsonEncode(devices.map((d) => d.toJson()).toList()));
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
    final s = _sessions.remove(d.id);
    if (s != null) {
      s.removeListener(notifyListeners);
      await s.disconnect();
      s.dispose();
    }
    devices.removeWhere((x) => x.id == d.id);
    await save();
    notifyListeners();
  }
}

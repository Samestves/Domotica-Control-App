import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/ble_link.dart';
import '../core/demo_link.dart';
import '../core/link.dart';
import '../core/protocol.dart';
import '../core/wifi_link.dart';
import '../models/device.dart';

class LogLine {
  final bool incoming;
  final String text;
  final DateTime at;
  LogLine(this.incoming, this.text) : at = DateTime.now();
}

/// Estado de una placa mientras la app está abierta: conexión, últimos valores y mensajes.
class Session extends ChangeNotifier {
  final SavedDevice device;
  DeviceLink? _link;
  final Map<int, String> values = {};
  final List<LogLine> log = [];
  String? lastAlert;
  final _subs = <StreamSubscription>[];

  /// Crea la conexión de una placa. Las pruebas pueden pasar otra para simular fallos.
  final DeviceLink Function(SavedDevice) _linkFor;

  /// Esperas entre reintentos cuando la conexión se cae sola.
  static const retryDelays = [Duration(seconds: 2), Duration(seconds: 4), Duration(seconds: 8), Duration(seconds: 15)];
  bool _wantConnected = false;
  int _retries = 0;
  Timer? _retryTimer;

  Session(this.device, {DeviceLink Function(SavedDevice)? linkFor}) : _linkFor = linkFor ?? _defaultLink;

  static DeviceLink _defaultLink(SavedDevice d) => switch (d.transport) {
        Transport.ble => BleLink(d.address),
        Transport.wifi => WifiLink(d.address, d.port),
        Transport.demo => DemoLink(d.profile.name),
      };

  LinkState get state => _link?.state ?? LinkState.disconnected;
  String? get error => _link?.lastError;
  bool get connected => state == LinkState.connected;

  /// true mientras la app espera para reintentar una conexión caída.
  bool get retrying => _retryTimer?.isActive ?? false;

  /// Conecta porque el usuario lo pidió. Si después se cae, la app reintenta sola.
  Future<void> connect() async {
    _wantConnected = true;
    _retries = 0;
    _retryTimer?.cancel();
    await _open();
  }

  /// Desconecta porque el usuario lo pidió: no se reintenta.
  Future<void> disconnect() async {
    _wantConnected = false;
    _retryTimer?.cancel();
    await _link?.disconnect();
    notifyListeners();
  }

  Future<void> _open() async {
    if (state == LinkState.connected || state == LinkState.connecting) return;
    await _teardown();
    final link = _linkFor(device);
    _link = link;
    _subs.add(link.states.listen(_onState));
    _subs.add(link.lines.listen(_onLine));
    notifyListeners();
    await link.connect();
    if (connected) {
      _retries = 0;
      _pushPinConfig();
      sendRaw('SYNC');
    }
    notifyListeners();
  }

  void _onState(LinkState s) {
    if (s == LinkState.error && _wantConnected && _retries < retryDelays.length) {
      _retryTimer?.cancel();
      _retryTimer = Timer(retryDelays[_retries++], _open);
    }
    notifyListeners();
  }

  /// La app es la fuente de verdad de los pines: al conectar, envía a la placa
  /// todos los ajustes guardados, aunque se hayan hecho sin conexión.
  void _pushPinConfig() {
    device.pins.forEach((vpin, p) => sendRaw(cfgMsg(vpin, p.gpio, inverted: p.inverted, enabled: p.enabled)));
  }

  void _onLine(String line) {
    _addLog(true, line);
    final m = Msg.parse(line);
    if (m.isPin) {
      values[m.pin!] = m.value;
      if (m.pin == 7 && m.value.toUpperCase().startsWith('DISPARO')) {
        lastAlert = 'Alarma: se detectó movimiento en ${device.name}';
      }
    }
    notifyListeners();
  }

  void _addLog(bool incoming, String text) {
    log.insert(0, LogLine(incoming, text));
    if (log.length > 60) log.removeLast();
  }

  /// Envía un valor a un pin virtual y lo recuerda para mostrarlo en el panel.
  void send(int pin, Object value, {bool remember = true, bool quiet = false}) {
    final line = pinMsg(pin, value);
    if (remember) values[pin] = value.toString();
    if (!quiet) _addLog(false, line);
    _link?.sendLine(line);
    notifyListeners();
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
    _teardown();
    super.dispose();
  }
}

class AppState extends ChangeNotifier {
  static const _key = 'devices_v1';
  final List<SavedDevice> devices = [];
  final Map<String, Session> _sessions = {};

  Session session(SavedDevice d) => _sessions.putIfAbsent(d.id, () {
        final s = Session(d);
        s.addListener(notifyListeners);
        return s;
      });

  int get connectedCount => _sessions.values.where((s) => s.connected).length;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
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

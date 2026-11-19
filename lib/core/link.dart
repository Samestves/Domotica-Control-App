import 'dart:async';

enum LinkState { disconnected, connecting, connected, error }

/// Una conexión con una placa. Puede ser Bluetooth, Wi-Fi o simulada.
abstract class DeviceLink {
  final _lines = StreamController<String>.broadcast();
  final _state = StreamController<LinkState>.broadcast();
  LinkState _current = LinkState.disconnected;
  String? lastError;

  Stream<String> get lines => _lines.stream;
  Stream<LinkState> get states => _state.stream;
  LinkState get state => _current;

  Future<void> connect();
  Future<void> disconnect();
  Future<void> sendLine(String line);

  /// Las subclases llaman esto cuando llega una línea de la placa.
  void emitLine(String line) {
    if (!_lines.isClosed) _lines.add(line);
  }

  void setState(LinkState s, [String? error]) {
    _current = s;
    if (error != null) lastError = error;
    if (!_state.isClosed) _state.add(s);
  }

  /// Corta la conexión y la marca como caída (por ejemplo, porque la placa dejó de responder).
  Future<void> fail(String why) async {
    await disconnect();
    setState(LinkState.error, why);
  }

  Future<void> dispose() async {
    await disconnect();
    await _lines.close();
    await _state.close();
  }
}

import 'dart:async';
import 'dart:math';

import 'link.dart';
import 'protocol.dart';

/// Placa simulada dentro del teléfono. Sirve para probar y mostrar la app sin hardware.
class DemoLink extends DeviceLink {
  final String profile; // 'casa' o 'carro'
  final _rnd = Random();
  Timer? _timer;
  Timer? _alarmTimer;
  double _temp = 24.1;
  bool _armed = false;
  int _speed = 0;

  DemoLink(this.profile);

  @override
  Future<void> connect() async {
    setState(LinkState.connecting);
    await Future.delayed(const Duration(milliseconds: 600));
    setState(LinkState.connected);
    emitLine('HELLO:Placa demo');
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
    _tick();
  }

  void _tick() {
    if (profile == 'carro') {
      final d = _speed > 20 ? 12 + _rnd.nextInt(60) : 70 + _rnd.nextInt(25);
      emitLine('V22:$d');
    } else {
      _temp += (_rnd.nextDouble() - .5) * .4;
      emitLine('V10:${_temp.toStringAsFixed(1)}');
    }
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _alarmTimer?.cancel();
    setState(LinkState.disconnected);
  }

  @override
  Future<void> sendLine(String line) async {
    if (state != LinkState.connected) return;
    final m = Msg.parse(line);
    await Future.delayed(const Duration(milliseconds: 80));
    if (m.kind == 'PING') return emitLine('PONG');
    if (m.kind == 'CFG') return emitLine('OK:${m.value}');
    if (m.kind == 'TEST') return emitLine('OK:prueba de salidas');
    if (m.kind == 'SYNC') return emitLine('V7:${_armed ? 1 : 0}');
    if (!m.isPin) return;
    switch (m.pin) {
      case 6:
        emitLine('V6:OK');
      case 7:
        _alarmTimer?.cancel();
        _armed = m.value == '1';
        if (_armed) {
          // Simula que alguien entra a la casa unos segundos después de armar.
          _alarmTimer = Timer(const Duration(seconds: 6), () {
            if (_armed) {
              emitLine('V11:1');
              emitLine('V7:DISPARO');
            }
          });
        } else {
          emitLine('V11:0');
        }
      case 20:
        final p = m.value.split(',');
        _speed = p.length == 2 ? (int.tryParse(p[1]) ?? 0).abs() : 0;
      case 24:
        _speed = int.tryParse(m.value) ?? 0;
    }
  }
}

import 'dart:async';
import 'dart:math';

import '../models/pins.dart';
import 'casa_sim.dart';
import 'link.dart';
import 'protocol.dart';

/// Placa simulada dentro del teléfono. Sirve para probar y mostrar la app sin hardware.
class DemoLink extends DeviceLink {
  final String profile; // 'casa' o 'carro'
  final Duration casaGrace;
  CasaSim? _casa;
  Timer? _carTimer;
  final _rnd = Random();
  int _speed = 0;

  /// En la demo la alarma espera menos que en la placa real, para no aburrir al mostrarla.
  DemoLink(this.profile, {this.casaGrace = const Duration(seconds: 8)});

  bool get _isCar => profile == 'carro';

  @override
  Future<void> connect() async {
    setState(LinkState.connecting);
    await Future.delayed(const Duration(milliseconds: 600));
    setState(LinkState.connected);
    emitLine('HELLO:Placa demo');
    if (_isCar) {
      _carTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sendDistance());
      _sendDistance();
    } else {
      _casa = CasaSim(emitLine, grace: casaGrace);
    }
  }

  void _sendDistance() {
    final d = _speed > 20 ? 12 + _rnd.nextInt(60) : 70 + _rnd.nextInt(25);
    emitLine('V${CarPins.distance}:$d');
  }

  @override
  Future<void> disconnect() async {
    _carTimer?.cancel();
    _casa?.dispose();
    _casa = null;
    setState(LinkState.disconnected);
  }

  @override
  Future<void> sendLine(String line) async {
    if (state != LinkState.connected) return;
    await Future.delayed(const Duration(milliseconds: 60));
    if (!_isCar) return _casa?.handle(line);

    final m = Msg.parse(line);
    if (m.kind == 'PING') return emitLine('PONG');
    if (m.kind == 'CFG') return emitLine('OK:${m.value}');
    if (m.pin == CarPins.joystick) {
      final p = m.value.split(',');
      _speed = p.length == 2 ? (int.tryParse(p[1]) ?? 0).abs() : 0;
    }
    if (m.pin == CarPins.throttle) _speed = int.tryParse(m.value) ?? 0;
  }
}

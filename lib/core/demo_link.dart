import 'dart:async';

import '../models/letras.dart';
import '../models/pins.dart';
import 'casa_sim.dart';
import 'link.dart';
import 'protocol.dart';

/// Placa simulada dentro del teléfono. Sirve para probar y mostrar la app sin hardware.
/// El «carro» de la demo es el robot que escribe (como carro-0.6): lápiz, escritura, medidas y prueba.
class DemoLink extends DeviceLink {
  final String profile; // 'casa' o 'carro'
  final Duration casaGrace;

  /// Cuánto tarda el robot de la demo en cada letra (el de verdad, unos 20 s).
  final Duration letterTime;
  CasaSim? _casa;

  String _invert = '010';
  bool _pen = false;
  String _measures = '65,120,30,1000';

  /// La escritura o la prueba en curso: una sola cosa a la vez, como en la placa.
  Timer? _job;
  bool _writing = false;

  /// En la demo la alarma espera menos que en la placa real, para no aburrir al mostrarla.
  DemoLink(this.profile, {this.casaGrace = const Duration(seconds: 8), this.letterTime = const Duration(milliseconds: 900)});

  bool get _isCar => profile == 'carro';

  @override
  Future<void> connect() async {
    setState(LinkState.connecting);
    await Future.delayed(const Duration(milliseconds: 600));
    if (state != LinkState.connecting) return; // se canceló mientras «conectaba»
    setState(LinkState.connected);
    emitLine('HELLO:Placa demo');
    if (!_isCar) _casa = CasaSim(emitLine, grace: casaGrace);
  }

  @override
  Future<void> disconnect() async {
    _stopJob();
    _casa?.dispose();
    _casa = null;
    setState(LinkState.disconnected);
  }

  void _stopJob() {
    _job?.cancel();
    _job = null;
    _writing = false;
  }

  void _setPen(bool down) {
    _pen = down;
    emitLine('V${CarPins.pen}:${down ? 1 : 0}');
  }

  /// Una letra cada [letterTime], con el lápiz que baja y sube; al final, como la placa: V29:0 y OK:ESCRITO.
  void _write(String text) {
    if (_writing) return emitLine('ERR:ya esta escribiendo: toca Parar primero');
    final shown = Letras.normalizar(text);
    final n = Letras.contar(shown);
    if (n == 0) return emitLine('ERR:no hay letras para escribir: usa A-Z, N, 0-9 y . , ! ? - + :');
    _stopJob();
    _writing = true;
    emitLine('OK:ESCRIBIENDO $text');
    var i = 0;
    void next() {
      if (i == n) {
        _writing = false;
        _setPen(false);
        emitLine('V${CarPins.writing}:0');
        return emitLine('OK:ESCRITO');
      }
      i++;
      emitLine('V${CarPins.writing}:$i/$n');
      _setPen(true);
      _job = Timer(letterTime, next);
    }

    next();
  }

  void _stop() {
    final was = _writing;
    _stopJob();
    if (was) {
      if (_pen) _setPen(false);
      emitLine('V${CarPins.writing}:0');
      emitLine('OK:escritura cancelada');
    }
    emitLine('OK:PARADO');
  }

  void _test() {
    if (_writing) return emitLine('ERR:espera a que termine de escribir (o toca Parar)');
    const parts = ['rueda izquierda', 'rueda derecha', 'lapiz abajo', 'lapiz arriba'];
    _stopJob();
    emitLine('OK:PRUEBA cada rueda debe girar hacia ADELANTE y el lapiz bajar y subir');
    var k = 0;
    void next() {
      if (k == parts.length) return emitLine('OK:PRUEBA terminada. Si una rueda giro hacia atras o el lapiz subio al bajar, activa Invertir');
      emitLine('OK:PRUEBA ${parts[k++]}');
      _job = Timer(const Duration(milliseconds: 700), next);
    }

    next();
  }

  @override
  Future<void> sendLine(String line) async {
    if (state != LinkState.connected) return;
    await Future.delayed(const Duration(milliseconds: 60));
    if (!_isCar) return _casa?.handle(line);

    final m = Msg.parse(line);
    if (m.kind == 'PING') return emitLine('PONG');
    if (m.kind == 'AUTH') return emitLine('ERR:AUTH no se usa en el carrito'); // la demo no pide clave
    if (m.kind == 'SYNC') {
      emitLine('V${CarPins.invert}:$_invert');
      emitLine('V${CarPins.measures}:$_measures');
      emitLine('V${CarPins.pen}:${_pen ? 1 : 0}');
      return emitLine('V${CarPins.writing}:0');
    }
    if (m.kind == 'TEST') return _test();
    if (m.kind == 'PARAR') return _stop();
    if (line.startsWith('ESCRIBIR:')) return _write(line.substring('ESCRIBIR:'.length));
    if (m.pin == CarPins.invert && RegExp(r'^[01]{3}$').hasMatch(m.value)) {
      _invert = m.value;
      return emitLine('V${CarPins.invert}:$_invert');
    }
    if (m.pin == CarPins.pen) {
      if (_writing) return emitLine('V${CarPins.pen}:${_pen ? 1 : 0}');
      return _setPen(m.value == '1');
    }
    if (m.pin == CarPins.measures && RegExp(r'^\d+,\d+,\d+,\d+$').hasMatch(m.value)) {
      _measures = m.value;
      return emitLine('V${CarPins.measures}:$_measures');
    }
  }
}

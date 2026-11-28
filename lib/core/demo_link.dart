import 'dart:async';
import 'dart:math';

import '../models/letras.dart';
import '../models/pins.dart';
import '../models/robot.dart';
import 'casa_sim.dart';
import 'link.dart';
import 'protocol.dart';

/// Placa simulada dentro del teléfono. Sirve para probar y mostrar la app sin hardware.
/// El «carro» de la demo es el robot que escribe (como carro-0.7): lápiz, escritura, medidas, la hoja con su
/// 0,0 y su cerca, ir a un punto, la prueba y la cara.
class DemoLink extends DeviceLink {
  final String profile; // 'casa' o 'carro'
  final Duration casaGrace;

  /// Cuánto tarda el robot de la demo en cada letra (el de verdad, unos 20 s).
  final Duration letterTime;
  CasaSim? _casa;

  /// Una sola semilla: la demo se comporta igual cada vez (las pruebas lo agradecen).
  final _rnd = Random(7);

  String _invert = '010';
  bool _pen = false;
  String _measures = '65,120,30,1000';

  /// La escritura, ir a un punto o la prueba: una sola cosa a la vez, como en la placa.
  Timer? _job;
  String _jobKind = ''; // 'escribir', 'ir' o ''

  // Dónde está, como lo cuenta la placa (mm, mm y radianes), y la hoja (la demo trae una carta).
  double _x = 0, _y = 0, _th = 0;
  bool _origin = false;
  Paper? _paper = Paper.presets['Carta'];

  // Manejo: lo que pidieron el joystick y el acelerador; se suma cada 50 ms.
  int _joyX = 0, _joyY = 0, _throttle = 0;
  bool _reverse = false, _edgeWarned = false;
  Timer? _drive;
  int _driveTicks = 0;

  // La cara: solo a quien la mira (CARA:1).
  bool _faceOn = false;
  Timer? _faceTimer, _blinkTimer;
  int _labelSeq = 0;
  var _mood = (tired: 0, sad: 0, happy: 0, lx: 0, ly: 0);

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
    _drive?.cancel();
    _drive = null;
    _watchFace(false);
    _casa?.dispose();
    _casa = null;
    setState(LinkState.disconnected);
  }

  void _stopJob() {
    _job?.cancel();
    _job = null;
    _jobKind = '';
  }

  void _setPen(bool down) {
    if (_pen == down) return;
    _pen = down;
    emitLine('V${CarPins.pen}:${down ? 1 : 0}');
  }

  RobotPose get _pose => RobotPose(_x, _y, _th * 180 / pi);

  void _reportPose() => emitLine('V${CarPins.pose}:${_origin ? '${_x.round()},${_y.round()},${(_th * 180 / pi).round()}' : '-'}');

  void _reportJob([String value = '0']) => emitLine('V${CarPins.writing}:$value');

  int get _letterMm => int.tryParse(_measures.split(',')[2]) ?? 30;

  // ---------------------------------------------------------------- escribir

  /// Escribe como la placa: una letra cada [letterTime], recorriendo sus trazos (la posición se va diciendo y el
  /// lápiz baja y sube), así en la app la tinta aparece en la hoja. Al final, V29:0 y OK:ESCRITO.
  void _write(String text) {
    if (_jobKind.isNotEmpty) return emitLine('ERR:${_busyText()}: toca Parar primero');
    final shown = Letras.normalizar(text);
    final n = Letras.contar(shown);
    if (n == 0) return emitLine('ERR:no hay letras para escribir: usa A-Z, N, 0-9 y . , ! ? - + :');
    final box = textBox(shown, _letterMm), paper = _paper;
    if (_origin && paper != null && box != null && !fitsOnPaper(box, _pose, paper)) {
      return emitLine('ERR:no cabe en la hoja: mueve el robot o achica las letras');
    }
    _stopJob();
    _jobKind = 'escribir';
    emitLine('OK:ESCRIBIENDO $text');

    // Los puntos de cada letra en la hoja, con el robot mirando hacia donde mira ahora. [first]: el primero de un
    // trazo (se llega con el marcador arriba y ahí baja); a los demás se llega dibujando.
    final scale = _letterMm / Letras.alto, x0 = _x, y0 = _y, c = cos(_th), s = sin(_th);
    final letters = <List<({double x, double y, bool first})>>[];
    final chars = shown.split('');
    for (var i = 0; i < chars.length; i++) {
      final strokes = Letras.trazos(chars[i]);
      if (strokes.isEmpty) continue;
      final points = <({double x, double y, bool first})>[];
      for (final trazo in strokes) {
        for (var k = 0; k < trazo.length; k++) {
          final px = (i * (Letras.ancho + Letras.espacio) + trazo[k].$1) * scale, py = trazo[k].$2 * scale;
          points.add((x: x0 + px * c - py * s, y: y0 + px * s + py * c, first: k == 0));
        }
      }
      letters.add(points);
    }

    var letter = 0, point = 0;
    void step() {
      if (letter == letters.length) {
        _jobKind = '';
        _setPen(false);
        _reportJob();
        _say('LISTO', 2200, happy: 100);
        return emitLine('OK:ESCRITO');
      }
      final pts = letters[letter];
      if (point == 0) {
        _reportJob('${letter + 1}/$n');
        _say('ESCRIBIENDO ${letter + 1}/$n', 60000, tired: 32, ly: 70);
      }
      final pt = pts[point];
      if (pt.first) _setPen(false);
      final dx = pt.x - _x, dy = pt.y - _y;
      if (dx.abs() > .01 || dy.abs() > .01) _th = atan2(dy, dx);
      _x = pt.x;
      _y = pt.y;
      _reportPose();
      if (pt.first) _setPen(true); // llegó al principio del trazo: baja el marcador
      if (++point == pts.length) {
        point = 0;
        letter++;
      }
      _job = Timer(letterTime ~/ pts.length, step);
    }

    step();
  }

  String _busyText() => _jobKind == 'escribir' ? 'el robot esta escribiendo' : 'el robot va hacia un punto';

  // ---------------------------------------------------------------- la hoja: 0,0, ir a un punto y alinearse

  /// IR (y ALINEAR, que es ir a donde ya está): avanza en línea recta y queda mirando hacia +x.
  void _goTo(double tx, double ty) {
    if (_jobKind.isNotEmpty) return emitLine('ERR:${_busyText()}: toca Parar primero');
    if (!_origin) return emitLine('ERR:primero pon el robot en la esquina de la hoja y toca 0,0 (CERO)');
    if (_paper != null && !_paper!.contains(tx, ty)) return emitLine('ERR:ese punto queda fuera de la hoja');
    _stopJob();
    _jobKind = 'ir';
    _setPen(false);
    _reportJob('ir');
    emitLine('OK:IR ${tx.round()},${ty.round()}');
    final dist = sqrt(pow(tx - _x, 2) + pow(ty - _y, 2));
    if (dist > .5) _th = atan2(ty - _y, tx - _x);
    final ticks = max(1, (dist / 3).ceil()); // 3 mm cada 50 ms: 60 mm/s
    final sx = _x, sy = _y;
    var k = 0;
    _job = Timer.periodic(const Duration(milliseconds: 50), (t) {
      k++;
      _x = sx + (tx - sx) * min(1, k / ticks);
      _y = sy + (ty - sy) * min(1, k / ticks);
      if (k >= ticks) {
        t.cancel();
        _th = 0;
        _jobKind = '';
        _reportPose();
        _reportJob();
        emitLine('OK:LLEGO');
        return;
      }
      _reportPose();
    });
  }

  void _stop() {
    final was = _jobKind;
    _stopJob();
    _joyX = _joyY = _throttle = 0;
    if (was.isNotEmpty) {
      _setPen(false);
      _reportJob();
      emitLine(was == 'escribir' ? 'OK:escritura cancelada' : 'OK:camino cancelado');
      if (was == 'escribir') _say('PARADO', 2000, sad: 100);
    }
    emitLine('OK:PARADO');
  }

  // ---------------------------------------------------------------- manejar, con la cerca de la hoja

  void _drivePing() {
    _drive ??= Timer.periodic(const Duration(milliseconds: 50), (_) => _driveTick());
  }

  void _driveTick() {
    final th = _throttle.clamp(0, 100), y = _joyY.clamp(-100, 100), x = _joyX.clamp(-100, 100);
    final forward = y.abs() >= th ? y : (_reverse ? -th : th);
    var l = (forward + x).toDouble(), r = (forward - x).toDouble();
    final biggest = max(l.abs(), r.abs());
    if (biggest > 100) {
      l = l * 100 / biggest;
      r = r * 100 / biggest;
    }
    // 100 % = 40 mm/s, como el robot de verdad (800 medios pasos por segundo con ruedas de 65 mm).
    var vl = l * .4, vr = r * .4;
    final paper = _paper;
    if (_origin && paper != null && vl + vr != 0) {
      final dir = _th + (vl + vr < 0 ? pi : 0), cx = cos(dir), cy = sin(dir);
      final out = (_x <= 0 && cx < -.02) || (_x >= paper.width && cx > .02) || (_y <= 0 && cy < -.02) || (_y >= paper.height && cy > .02);
      if (out) {
        final v = (vl + vr) / 2;
        vl -= v;
        vr -= v;
        if (!_edgeWarned) emitLine('ERR:borde de la hoja: el robot no sale del papel');
        _edgeWarned = true;
      } else {
        _edgeWarned = false;
      }
    }
    if (vl == 0 && vr == 0) {
      _drive?.cancel();
      _drive = null;
      _reportPose();
      return;
    }
    const dt = .05, track = 120.0;
    final ds = (vl + vr) / 2 * dt, dth = (vr - vl) / track * dt;
    _x += ds * cos(_th + dth / 2);
    _y += ds * sin(_th + dth / 2);
    _th = (_th + dth + pi) % (2 * pi) - pi;
    if (++_driveTicks % 3 == 0) _reportPose(); // cada 150 ms, como la placa
  }

  // ---------------------------------------------------------------- la cara

  void _watchFace(bool on) {
    _faceOn = on;
    _faceTimer?.cancel();
    _blinkTimer?.cancel();
    if (!on) return;
    _say('HOLA', 1800, happy: 100);
    // Mira alrededor y parpadea de vez en cuando, como la cara de la placa.
    _faceTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      final dice = _rnd.nextDouble();
      if (dice < .3) {
        _sendFace(blink: true);
        _blinkTimer = Timer(const Duration(milliseconds: 150), _sendFace);
      } else if (dice < .65 && _jobKind != 'escribir') {
        _mood = (tired: _mood.tired, sad: 0, happy: 0, lx: _rnd.nextInt(161) - 80, ly: _rnd.nextInt(101) - 50);
        _sendFace();
      }
    });
  }

  void _sendFace({bool blink = false}) {
    if (!_faceOn) return;
    final b = blink ? 100 : 0, m = _mood;
    final moving = _drive != null || _jobKind.isNotEmpty;
    emitLine('V${CarPins.face}:${m.tired},0,${m.sad},${m.happy},100,0,${m.lx},${m.ly},$b,$b,${moving ? 60 : 0},8');
  }

  /// Un mensaje en la franja de arriba y el ánimo que va con él.
  void _say(String text, int ms, {int tired = 0, int sad = 0, int happy = 0, int ly = 0}) {
    _mood = (tired: tired, sad: sad, happy: happy, lx: 0, ly: ly);
    if (!_faceOn) return;
    emitLine('V${CarPins.faceLabel}:${++_labelSeq},$ms,$text');
    _sendFace();
  }

  // ---------------------------------------------------------------- la prueba

  void _test() {
    if (_jobKind.isNotEmpty) return emitLine('ERR:${_busyText()}: espera a que termine (o toca Parar)');
    const parts = ['rueda izquierda', 'rueda derecha', 'lapiz abajo', 'lapiz arriba'];
    _stopJob();
    if (_origin) {
      _origin = false; // las ruedas giran en el aire: se pierde la cuenta, como en la placa
      _reportPose();
    }
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
      emitLine('V${CarPins.writing}:0');
      emitLine('V${CarPins.paper}:${_paper?.wire ?? '0,0'}');
      return _reportPose();
    }
    if (m.kind == 'TEST') return _test();
    if (m.kind == 'PARAR') return _stop();
    if (m.kind == 'CERO') {
      if (_jobKind.isNotEmpty) return emitLine('ERR:${_busyText()}: espera a que termine (o toca Parar)');
      _x = _y = _th = 0;
      _origin = true;
      return _reportPose();
    }
    if (m.kind == 'ALINEAR') return _goTo(_x, _y);
    if (m.kind == 'IR') {
      final p = m.value.split(',').map(int.tryParse).toList();
      if (p.length != 2 || p.contains(null)) return emitLine('ERR:usa IR:x,y en mm desde el 0,0, por ejemplo IR:150,80');
      return _goTo(p[0]!.toDouble(), p[1]!.toDouble());
    }
    if (m.kind == 'CARA') return _watchFace(m.value == '1');
    if (line.startsWith('ESCRIBIR:')) return _write(line.substring('ESCRIBIR:'.length));
    if (m.pin == CarPins.invert && RegExp(r'^[01]{3}$').hasMatch(m.value)) {
      _invert = m.value;
      return emitLine('V${CarPins.invert}:$_invert');
    }
    if (m.pin == CarPins.pen) {
      // Siempre se confirma, aunque ya estuviera así (como la placa). Ocupado, lo maneja el robot.
      if (_jobKind.isEmpty) _pen = m.value == '1';
      return emitLine('V${CarPins.pen}:${_pen ? 1 : 0}');
    }
    if (m.pin == CarPins.measures && RegExp(r'^\d+,\d+,\d+,\d+$').hasMatch(m.value)) {
      _measures = m.value;
      return emitLine('V${CarPins.measures}:$_measures');
    }
    if (m.pin == CarPins.paper) {
      final p = Paper.parse(m.value);
      if (p == null && m.value != '0,0') return emitLine('ERR:V32 es ancho,alto de la hoja en mm');
      _paper = p;
      _edgeWarned = false;
      return emitLine('V${CarPins.paper}:${p?.wire ?? '0,0'}');
    }
    if (m.pin == CarPins.reverse) {
      _reverse = m.value == '1';
      emitLine('V${CarPins.reverse}:${_reverse ? 1 : 0}');
      return _drivePing();
    }
    if (_jobKind.isNotEmpty && (m.pin == CarPins.joystick || m.pin == CarPins.throttle)) {
      if (m.value != '0,0' && m.value != '0') emitLine('ERR:${_busyText()}: toca Parar para manejar');
      return;
    }
    if (m.pin == CarPins.joystick) {
      final p = m.value.split(',').map(int.tryParse).toList();
      if (p.length == 2 && !p.contains(null)) {
        _joyX = p[0]!;
        _joyY = p[1]!;
        _drivePing();
      }
    }
    if (m.pin == CarPins.throttle) {
      _throttle = int.tryParse(m.value) ?? 0;
      _drivePing();
    }
  }
}

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../models/pins.dart';
import '../../models/robot.dart';
import '../../state/app_state.dart';
import '../theme.dart';

/// La cara del robot, como se ve en sus dos pantallas: es el mismo motor de firmware/carro_esp32/cara.h, punto
/// por punto. La placa manda lo que la cara quiere mostrar (V33) cada vez que cambia; aquí los ojos se acercan a
/// eso con la misma suavidad, cuadro a cuadro, y se dibujan en dos pantallas de 128 × 64.

// ===================== Pantalla: un punto por byte =====================

const _w = 128, _h = 64, _band = 16;

/// La imagen de una pantalla (1 = encendido), con las mismas funciones de dibujo que la placa.
class FaceFrame {
  final pixels = Uint8List(_w * _h);

  void clear() => pixels.fillRange(0, pixels.length, 0);

  bool at(int x, int y) => pixels[y * _w + x] != 0;

  // Redondeo como lroundf en C: la mitad se aleja del cero (igual que round() en Dart).
  static int _r(double v) => v.round();

  void hline(double fx0, double fx1, double fy, bool on) {
    final y = _r(fy);
    if (y < 0 || y >= _h) return;
    final x0 = max(0, _r(fx0)), x1 = min(_w - 1, _r(fx1));
    for (var x = x0; x <= x1; x++) {
      pixels[y * _w + x] = on ? 1 : 0;
    }
  }

  void rect(double x, double y, double w, double h, bool on) {
    for (var j = _r(y); j < _r(y + h); j++) {
      hline(x, x + w - 1, j.toDouble(), on);
    }
  }

  /// Rectángulo redondeado.
  void rrect(double fx, double fy, double fw, double fh, double fr, bool on) {
    final x = _r(fx), y = _r(fy), w = _r(fw), h = _r(fh);
    if (w <= 0 || h <= 0) return;
    final r = max(0, min(_r(fr), min(w ~/ 2, h ~/ 2)));
    for (var j = 0; j < h; j++) {
      final d = j < r ? r - j - .5 : (j >= h - r ? j - (h - r) + .5 : 0.0);
      final inset = d > 0 ? _r(r - sqrt(max(0.0, r * r - d * d))) : 0;
      hline((x + inset).toDouble(), (x + w - 1 - inset).toDouble(), (y + j).toDouble(), on);
    }
  }

  /// Triángulo relleno.
  void tri(double x0, double y0, double x1, double y1, double x2, double y2, bool on) {
    final edges = [
      [x0, y0, x1, y1],
      [x1, y1, x2, y2],
      [x2, y2, x0, y0],
    ];
    for (var y = _r(min(y0, min(y1, y2))); y <= _r(max(y0, max(y1, y2))); y++) {
      final yc = y + .5;
      var lo = 1e9, hi = -1e9;
      var n = 0;
      for (final s in edges) {
        if ((s[1] <= yc && s[3] > yc) || (s[3] <= yc && s[1] > yc)) {
          final x = s[0] + (yc - s[1]) * (s[2] - s[0]) / (s[3] - s[1]);
          lo = min(lo, x);
          hi = max(hi, x);
          n++;
        }
      }
      if (n >= 2) hline(lo, hi, y.toDouble(), on);
    }
  }

  void text(String s, int x, int y) {
    for (final ch in s.split('')) {
      final rows = _font[ch];
      if (rows != null) {
        for (var j = 0; j < 7; j++) {
          for (var i = 0; i < 5; i++) {
            if (rows[j] & (16 >> i) != 0) hline((x + i).toDouble(), (x + i).toDouble(), (y + j).toDouble(), true);
          }
        }
      }
      x += 6;
    }
  }

  static int textWidth(String s) => max(0, s.length * 6 - 1);

  /// Las filas de una letra de la cara, o null si no la tiene; y todas las que tiene (las pruebas las comparan
  /// con las de cara.h).
  static List<int>? glyph(String ch) => _font[ch];
  static Iterable<String> get glyphs => _font.keys;

  void icon(List<int> rows, int width, int x, int y) {
    for (var j = 0; j < rows.length; j++) {
      for (var i = 0; i < width; i++) {
        if (rows[j] & (1 << (width - 1 - i)) != 0) hline((x + i).toDouble(), (x + i).toDouble(), (y + j).toDouble(), true);
      }
    }
  }
}

/// Letras de 5 × 7 de la cara (las mismas de cara.h): cada fila es un número, bit 4 = columna izquierda.
const _font = <String, List<int>>{
  'A': [14, 17, 17, 31, 17, 17, 17], 'B': [30, 17, 17, 30, 17, 17, 30], 'C': [15, 16, 16, 16, 16, 16, 15],
  'D': [30, 17, 17, 17, 17, 17, 30], 'E': [31, 16, 16, 30, 16, 16, 31], 'F': [31, 16, 16, 30, 16, 16, 16],
  'H': [17, 17, 17, 31, 17, 17, 17], 'I': [31, 4, 4, 4, 4, 4, 31], 'L': [16, 16, 16, 16, 16, 16, 31],
  'M': [17, 27, 21, 21, 17, 17, 17], 'N': [17, 25, 21, 19, 17, 17, 17], 'O': [14, 17, 17, 17, 17, 17, 14],
  'R': [30, 17, 17, 30, 20, 18, 17], 'S': [15, 16, 16, 14, 1, 1, 30], 'T': [31, 4, 4, 4, 4, 4, 4],
  'U': [17, 17, 17, 17, 17, 17, 14], 'V': [17, 17, 17, 17, 10, 10, 4], 'W': [17, 17, 17, 21, 21, 27, 17],
  'X': [17, 17, 10, 4, 10, 17, 17], 'Z': [31, 1, 2, 4, 8, 16, 31], 'P': [30, 17, 17, 30, 16, 16, 16],
  'Q': [14, 17, 17, 17, 21, 18, 13], 'G': [15, 16, 16, 23, 17, 17, 15], 'K': [17, 18, 20, 24, 20, 18, 17],
  'J': [7, 2, 2, 2, 2, 18, 12], 'Y': [17, 17, 10, 4, 4, 4, 4], '/': [1, 1, 2, 4, 8, 16, 16],
  ':': [0, 12, 12, 0, 12, 12, 0], '.': [0, 0, 0, 0, 0, 12, 12], ',': [0, 0, 0, 0, 12, 4, 8],
  '0': [14, 19, 21, 21, 25, 17, 14], '1': [4, 12, 4, 4, 4, 4, 14], '2': [14, 17, 1, 6, 8, 16, 31],
  '3': [30, 1, 1, 14, 1, 1, 30], '4': [2, 6, 10, 18, 31, 2, 2], '5': [31, 16, 30, 1, 1, 17, 14],
  '6': [6, 8, 16, 30, 17, 17, 14], '7': [31, 1, 2, 4, 8, 8, 8], '8': [14, 17, 17, 14, 17, 17, 14],
  '9': [14, 17, 17, 15, 1, 2, 12], '!': [4, 4, 4, 4, 4, 0, 4], '?': [14, 17, 1, 6, 4, 0, 4],
  '-': [0, 0, 0, 31, 0, 0, 0], '%': [25, 26, 2, 4, 8, 11, 19],
};

const _iconBt = [0x18, 0x14, 0x52, 0x34, 0x18, 0x34, 0x52, 0x14, 0x18]; // 7 de ancho
const _iconWifi = [0x7C, 0x82, 0x139, 0x44, 0x38, 0x00, 0x10]; // 9 de ancho

// ===================== Motor de ojos (el de cara.h) =====================

/// Los ojos ahora, que se acercan a lo que pide la placa (FaceTarget) como en update() de cara.h.
class FaceEngine {
  double lx = 0, ly = 0, scale = 1, tired = 0, angry = 0, sad = 0, happy = 0, curious = 0, blinkL = 0, blinkR = 0;
  FaceTarget target = FaceTarget.rest;

  /// Reloj de la cara, en ms (para las sacudidas, los saltos y los «Z» de dormida).
  int now = 0;
  int _shakeUntil = 0, _bounceUntil = 0;

  FaceLabel? _label;
  int _labelUntil = 0;

  /// Un mensaje nuevo de la franja (si cambió su número) se muestra lo que dijo la placa.
  void setLabel(FaceLabel? l) {
    if (l == null || l.seq == _label?.seq) return;
    _label = l;
    _labelUntil = now + l.ms;
  }

  String? get label => _label != null && now < _labelUntil && !target.sleeping ? _label!.text : null;

  void update(int dt) {
    now += dt;
    final t = target;
    // Mientras la placa marca sacudida o salto, siguen un rato (llegan cada 80 ms como mucho).
    if (t.shaking) _shakeUntil = now + 200;
    if (t.bouncing) _bounceUntil = now + 200;
    double k(double base, double slow) => 1 - pow(1 - base, dt / 33 / slow).toDouble();
    final kf = k(.45, 1), km = k(.2, 1), kl = k(.28, 1);
    double ease(double v, double to, double k) => v + (to - v) * k;
    blinkL = ease(blinkL, t.blinkL, kf);
    blinkR = ease(blinkR, t.blinkR, kf);
    tired = ease(tired, t.tired, km);
    angry = ease(angry, t.angry, km);
    sad = ease(sad, t.sad, km);
    happy = ease(happy, t.happy, km);
    scale = ease(scale, t.scale, km);
    curious = ease(curious, t.curious, km);
    lx = ease(lx, t.lx, kl);
    ly = ease(ly, t.ly, kl);
  }

  /// El ojo [side] (−1 el de la izquierda de quien mira, 1 el de la derecha) en su propia pantalla, como drawEyes
  /// de cara.h con dos pantallas: centrado y más grande.
  void drawEye(FaceFrame fb, int side) {
    const cy0 = _band + (_h - _band) / 2, grow = 1.25, travel = 22.0;
    final shake = now < _shakeUntil ? sin(now / 18) * 3 : 0.0;
    final bounce = now < _bounceUntil ? -sin(now / 110).abs() * 4 : 0.0;
    final toward = (lx > 0 ? 1 : (lx < 0 ? -1 : 0)) == side ? .14 : -.08; // el ojo hacia donde mira, más grande
    final big = curious * toward * min(1.0, lx.abs() * 2);
    final size = 36 * scale * grow * (1 + big);
    final h = max(2.0, size * (1 - (side < 0 ? blinkL : blinkR)));
    final cx = 64 + lx * travel + shake;
    final cy = cy0 + ly * 6 + bounce + (size - h) * .15;
    final x = cx - size / 2, y = cy - h / 2, w = size;
    fb.rrect(x, y, w, h, (12 + 6 * happy) * scale, true);
    final inner = side < 0 ? x + w : x, outer = side < 0 ? x : x + w;
    if (tired > .01) fb.rect(x - 1, y - 1, w + 2, h * .55 * tired + 1, false);
    if (angry > .01) fb.tri(outer, y - 1, inner, y - 1, inner, y + h * .62 * angry, false);
    if (sad > .01) fb.tri(inner, y - 1, outer, y - 1, outer, y + h * .58 * sad, false);
    if (happy > .01) fb.rrect(x - 6, y + h - h * .58 * happy, w + 12, h + 4, 18, false);
  }

  /// La franja de arriba, como drawBand de cara.h: la conexión en la pantalla izquierda, la velocidad en la
  /// derecha y el mensaje (o los «Z» de dormida) en las dos.
  void drawBand(FaceFrame fb, {required bool icons, required bool bars}) {
    final t = target, text = label;
    if (icons && !(text != null && FaceFrame.textWidth(text) > _w - 44)) {
      if (t.bluetooth) {
        fb.icon(_iconBt, 7, 2, 3);
      } else if (t.wifi) {
        fb.icon(_iconWifi, 9, 1, 5);
      } else {
        fb.text('X', 2, 4);
      }
    }
    if (bars && !(text != null && FaceFrame.textWidth(text) > 64)) {
      for (var i = 0; i < 5; i++) {
        final bh = 2 + i * 2;
        if (t.speed > i * 20) {
          fb.rect(_w - 26 + i * 5.0, 12.0 - bh, 4, bh.toDouble(), true);
        } else {
          fb.rect(_w - 26 + i * 5.0, 11, 4, 1, true);
        }
      }
    }
    if (t.sleeping) {
      final p = (now / 900) % 1;
      fb.text('Z', 50, (8 - p * 6).round());
      fb.text('Z', 60, (6 - ((p + .4) % 1) * 4).round());
      fb.text('Z', 70, (9 - ((p + .7) % 1) * 7).round());
    } else if (text != null) {
      fb.text(text, (_w - FaceFrame.textWidth(text)) ~/ 2, 4);
    }
  }

  /// Las dos pantallas como las ve quien mira al robot: [0] la de la izquierda (el ojo derecho del robot).
  void drawScreens(List<FaceFrame> screens) {
    for (var i = 0; i < 2; i++) {
      final fb = screens[i]..clear();
      final side = i == 0 ? -1 : 1;
      drawEye(fb, side);
      drawBand(fb, icons: side < 0, bars: side > 0);
    }
  }
}

// ===================== En la app =====================

/// La cara del robot en vivo, en dos pantallitas. Mientras se ve, le pide a la placa que la mande (CARA:1) y al
/// irse le dice que pare (CARA:0). Si el robot tiene un programa anterior a carro-0.7, lo dice.
class RobotFace extends StatefulWidget {
  final Session session;
  const RobotFace({super.key, required this.session});

  /// El robot puede mandar su cara: desde carro-0.7, que también dice su hoja (V32).
  static bool supported(Session s) => s.values.containsKey(CarPins.paper);

  @override
  State<RobotFace> createState() => _RobotFaceState();
}

class _RobotFaceState extends State<RobotFace> with SingleTickerProviderStateMixin {
  final _engine = FaceEngine();
  final _screens = [FaceFrame(), FaceFrame()];
  final _frame = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  int _sinceDraw = 0;
  bool _watching = false;

  Session get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s.addListener(_onSession);
    _onSession();
    _engine.drawScreens(_screens);
    _ticker.start();
  }

  @override
  void didUpdateWidget(RobotFace old) {
    super.didUpdateWidget(old);
    if (old.session == widget.session) return;
    old.session.removeListener(_onSession);
    if (_watching) old.session.sendSilently('CARA:0');
    _watching = false;
    widget.session.addListener(_onSession);
    _onSession();
  }

  /// La placa olvida quién mira al desconectarse: al volver la conexión se le pide otra vez.
  void _onSession() {
    final want = _s.connected && RobotFace.supported(_s);
    if (want == _watching) return;
    _watching = want;
    _s.sendSilently(want ? 'CARA:1' : 'CARA:0');
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMilliseconds.clamp(0, 200);
    _last = elapsed;
    _engine.target = FaceTarget.parse(_s.values[CarPins.face]) ?? FaceTarget.rest;
    _engine.setLabel(FaceLabel.parse(_s.values[CarPins.faceLabel]));
    _engine.update(dt);
    // Treinta cuadros por segundo, como la placa: no hace falta más.
    _sinceDraw += dt;
    if (_sinceDraw < 33) return;
    _sinceDraw = 0;
    _engine.drawScreens(_screens);
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _s.removeListener(_onSession);
    if (_watching) _s.sendSilently('CARA:0');
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: 'La cara del robot, en vivo',
      excludeSemantics: true,
      child: CustomPaint(painter: _ScreensPainter(_screens, _frame, eye: const Color(0xFF8FDFFF), band: c.amber), size: Size.infinite),
    );
  }
}

/// Dos pantallitas negras con sus puntos: la franja de arriba en ámbar (como las pantallas de dos colores) y
/// los ojos en celeste. Cada punto encendido es un cuadradito; se dibujan de a tramos por fila.
class _ScreensPainter extends CustomPainter {
  final List<FaceFrame> screens;
  final Color eye, band;
  _ScreensPainter(this.screens, Listenable frame, {required this.eye, required this.band}) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    const gap = 10.0, bezel = 5.0;
    final sw = (size.width - gap) / 2;
    final sh = min(size.height, sw / 2 + 2 * bezel);
    final pw = min(sw - 2 * bezel, (sh - 2 * bezel) * 2);
    final px = pw / _w;
    final top = (size.height - sh) / 2;
    for (var i = 0; i < 2; i++) {
      final left = i * (sw + gap);
      final panel = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, sw, sh), const Radius.circular(10));
      canvas.drawRRect(panel, Paint()..color = const Color(0xFF050608));
      canvas.drawRRect(panel, Paint()
        ..color = const Color(0xFF2A2D33)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
      final ox = left + (sw - pw) / 2, oy = top + (sh - pw / 2) / 2;
      final fb = screens[i];
      // Sin suavizado y un pelito más altos: los puntos se tocan, como en la pantalla (si no, quedan rayitas).
      final paint = Paint()..isAntiAlias = false;
      for (var y = 0; y < _h; y++) {
        paint.color = y < _band ? band : eye;
        var x = 0;
        while (x < _w) {
          if (!fb.at(x, y)) {
            x++;
            continue;
          }
          final start = x;
          while (x < _w && fb.at(x, y)) {
            x++;
          }
          canvas.drawRect(Rect.fromLTWH(ox + start * px, oy + y * px, (x - start) * px, px + .6), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ScreensPainter old) => old.screens != screens || old.eye != eye || old.band != band;
}

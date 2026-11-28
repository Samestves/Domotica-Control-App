import 'dart:math';

import 'letras.dart';

/// Lo que dice el robot que escribe (carro-0.7), ya leído. Las cuentas son las mismas de la placa
/// (firmware/carro_esp32/escritura.h): la app dice «cabe» exactamente cuando el robot lo acepta.

/// Dónde está el marcador del robot (V31), desde el 0,0: x a lo largo de la hoja y y hacia su izquierda, en mm;
/// [deg] hacia dónde mira (0 = a lo largo de la hoja, + = girado a la izquierda).
class RobotPose {
  final double x, y, deg;
  const RobotPose(this.x, this.y, this.deg);

  double get rad => deg * pi / 180;

  /// «120,45,90» → la posición; «-» (sin 0,0) o algo raro → null.
  static RobotPose? parse(String? v) {
    final p = (v ?? '').split(',').map(double.tryParse).toList();
    if (p.length != 3 || p.any((x) => x == null)) return null;
    return RobotPose(p[0]!, p[1]!, p[2]!);
  }

  @override
  bool operator ==(Object other) => other is RobotPose && other.x == x && other.y == y && other.deg == deg;

  @override
  int get hashCode => Object.hash(x, y, deg);
}

/// La hoja (V32): [width] a lo largo (x) y [height] (y), en mm.
class Paper {
  final int width, height;
  const Paper(this.width, this.height);

  /// Las más comunes, acostadas: el robot escribe a lo largo.
  static const presets = {'Carta': Paper(279, 216), 'A4': Paper(297, 210), 'Oficio': Paper(356, 216)};

  /// Los mismos límites que acepta la placa.
  static const minMm = 50, maxMm = 2000;

  /// «279,216» → la hoja; «0,0» (sin hoja) o algo raro → null.
  static Paper? parse(String? v) {
    final p = (v ?? '').split(',').map(int.tryParse).toList();
    if (p.length != 2 || p.any((x) => x == null) || p[0]! <= 0 || p[1]! <= 0) return null;
    return Paper(p[0]!, p[1]!);
  }

  String get wire => '$width,$height';

  /// «Carta», o «30 × 21 cm» si no es una de las comunes.
  String get name {
    for (final e in presets.entries) {
      if (e.value == this) return e.key;
    }
    String cm(int mm) => mm % 10 == 0 ? '${mm ~/ 10}' : (mm / 10).toStringAsFixed(1).replaceAll('.', ',');
    return '${cm(width)} × ${cm(height)} cm';
  }

  bool contains(double x, double y, {double tolerance = .5}) =>
      x >= -tolerance && y >= -tolerance && x <= width + tolerance && y <= height + tolerance;

  @override
  bool operator ==(Object other) => other is Paper && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Un rectángulo en mm.
typedef Box = ({double x0, double y0, double x1, double y1});

/// Lo que ocupa [text] (como lo deja [Letras.normalizar]) con letras de [letterMm], medido desde donde empieza,
/// con el robot mirando hacia +x. Igual que Escritor::caja en la placa. null si no tiene trazos.
Box? textBox(String text, int letterMm) {
  final s = letterMm / Letras.alto;
  final chars = text.split('');
  double? x0, y0, x1, y1;
  for (var i = 0; i < chars.length; i++) {
    for (final trazo in Letras.trazos(chars[i])) {
      for (final (gx, gy) in trazo) {
        final px = (i * (Letras.ancho + Letras.espacio) + gx) * s, py = gy * s;
        x0 = x0 == null ? px : min(x0, px);
        x1 = x1 == null ? px : max(x1, px);
        y0 = y0 == null ? py : min(y0, py);
        y1 = y1 == null ? py : max(y1, py);
      }
    }
  }
  return x0 == null ? null : (x0: x0, y0: y0!, x1: x1!, y1: y1!);
}

/// Las cuatro esquinas de [box] en la hoja, con el robot en [pose].
List<(double, double)> boxOnPaper(Box box, RobotPose pose) {
  final c = cos(pose.rad), s = sin(pose.rad);
  return [
    for (final (px, py) in [(box.x0, box.y0), (box.x1, box.y0), (box.x1, box.y1), (box.x0, box.y1)])
      (pose.x + px * c - py * s, pose.y + px * s + py * c),
  ];
}

/// ¿Cabe [box] en [paper] con el robot en [pose]? Igual que cabeEnHoja en la placa (medio milímetro de tolerancia).
bool fitsOnPaper(Box box, RobotPose pose, Paper paper) => boxOnPaper(box, pose).every((p) => paper.contains(p.$1, p.$2));

/// Lo que la cara del robot quiere mostrar (V33, ver caraState en firmware/carro_esp32/cara.h): ánimo, hacia
/// dónde mira y el parpadeo, de 0 a 1 (lx y ly de −1 a 1); la velocidad (0 a 100) y sus marcas.
class FaceTarget {
  final double tired, angry, sad, happy, scale, curious, lx, ly, blinkL, blinkR;
  final int speed, marks;
  const FaceTarget({
    this.tired = 0,
    this.angry = 0,
    this.sad = 0,
    this.happy = 0,
    this.scale = 1,
    this.curious = 0,
    this.lx = 0,
    this.ly = 0,
    this.blinkL = 0,
    this.blinkR = 0,
    this.speed = 0,
    this.marks = 0,
  });

  /// Ojos abiertos mirando al frente: mientras la placa no dice nada.
  static const rest = FaceTarget();

  bool get sleeping => marks & 1 != 0;
  bool get shaking => marks & 2 != 0;
  bool get bouncing => marks & 4 != 0;
  bool get bluetooth => marks & 8 != 0;
  bool get wifi => marks & 16 != 0;

  static FaceTarget? parse(String? v) {
    final p = (v ?? '').split(',').map(int.tryParse).toList();
    if (p.length != 12 || p.any((x) => x == null)) return null;
    double f(int i) => p[i]! / 100;
    return FaceTarget(
      tired: f(0),
      angry: f(1),
      sad: f(2),
      happy: f(3),
      scale: f(4),
      curious: f(5),
      lx: f(6),
      ly: f(7),
      blinkL: f(8),
      blinkR: f(9),
      speed: p[10]!,
      marks: p[11]!,
    );
  }
}

/// El mensaje de la franja de arriba de la cara (V34): «número,ms,TEXTO». El número cambia con cada mensaje.
class FaceLabel {
  final int seq, ms;
  final String text;
  const FaceLabel(this.seq, this.ms, this.text);

  static FaceLabel? parse(String? v) {
    final s = v ?? '';
    final a = s.indexOf(','), b = a < 0 ? -1 : s.indexOf(',', a + 1);
    if (b < 0) return null;
    final seq = int.tryParse(s.substring(0, a)), ms = int.tryParse(s.substring(a + 1, b));
    return seq == null || ms == null ? null : FaceLabel(seq, ms, s.substring(b + 1));
  }
}

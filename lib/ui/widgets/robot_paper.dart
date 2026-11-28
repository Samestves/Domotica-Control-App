import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/robot.dart';
import '../theme.dart';

/// Lo que dibujó el robot con el marcador abajo, para verlo en la hoja: puntos en mm; null = ahí subió el
/// marcador (un trazo termina). Se arma con cada posición que dice la placa (V31).
class RobotTrail extends ChangeNotifier {
  final points = <(double, double)?>[];

  /// Más puntos no hacen falta para verlo (un texto largo son unos pocos cientos).
  static const maxPoints = 6000;

  void add(RobotPose? pose, {required bool penDown}) {
    if (pose == null || !penDown) {
      if (points.isNotEmpty && points.last != null) {
        points.add(null);
        notifyListeners();
      }
      return;
    }
    final last = points.isEmpty ? null : points.last;
    if (last != null && (last.$1 - pose.x).abs() < .2 && (last.$2 - pose.y).abs() < .2) return;
    points.add((pose.x, pose.y));
    if (points.length > maxPoints) points.removeRange(0, points.length - maxPoints);
    notifyListeners();
  }

  void clear() {
    if (points.isEmpty) return;
    points.clear();
    notifyListeners();
  }
}

/// La hoja vista desde arriba, con el robot encima: el 0,0 abajo a la izquierda y x hacia la derecha. Muestra
/// dónde está y hacia dónde mira, la tinta que dejó, dónde caería un texto ([box]: verde si cabe, rojo si no) y
/// el punto elegido ([target]). Un toque en la hoja elige un punto ([onTap], en mm).
class PaperView extends StatelessWidget {
  final Paper paper;
  final RobotPose? pose;
  final RobotTrail trail;
  final List<(double, double)>? box;
  final bool boxFits;
  final (double, double)? target;

  /// Distancia entre las ruedas, para dibujar el robot a escala.
  final int trackMm;
  final void Function(double x, double y)? onTap;

  const PaperView({
    super.key,
    required this.paper,
    required this.pose,
    required this.trail,
    required this.trackMm,
    this.box,
    this.boxFits = true,
    this.target,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(builder: (context, size) {
      final layout = _PaperLayout(paper, Size(size.maxWidth, size.maxHeight));
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: onTap == null
            ? null
            : (d) {
                final (x, y) = layout.toPaper(d.localPosition);
                if (paper.contains(x, y, tolerance: 0)) onTap!(x, y);
              },
        child: Semantics(
          label: pose == null ? 'Hoja ${paper.name}, sin 0,0' : 'Hoja ${paper.name}: el robot está en ${_cm(pose!.x)}, ${_cm(pose!.y)} cm',
          excludeSemantics: true,
          // Lo que queda fuera de la tarjeta (el robot en la esquina, por ejemplo) no tapa lo de al lado.
          child: ClipRect(
            child: CustomPaint(
            size: Size.infinite,
            painter: _PaperPainter(
              layout: layout,
              pose: pose,
              trail: trail,
              box: box,
              boxFits: boxFits,
              target: target,
              trackMm: trackMm,
              c: c,
            ),
          ),
          ),
        ),
      );
    });
  }
}

/// «12,3»: mm a cm con una coma decimal.
String _cm(double mm) => (mm / 10).toStringAsFixed(1).replaceAll('.', ',');

/// Dónde cae la hoja dentro del espacio que hay: centrada, lo más grande posible, sin deformarse.
class _PaperLayout {
  final Paper paper;
  late final double k, left, bottom;

  static const pad = 10.0;

  _PaperLayout(this.paper, Size size) {
    k = max(0.0, min((size.width - 2 * pad) / paper.width, (size.height - 2 * pad) / paper.height));
    left = (size.width - paper.width * k) / 2;
    bottom = (size.height + paper.height * k) / 2;
  }

  Offset toScreen(double x, double y) => Offset(left + x * k, bottom - y * k);

  (double, double) toPaper(Offset p) => k <= 0 ? (-1, -1) : ((p.dx - left) / k, (bottom - p.dy) / k);
}

class _PaperPainter extends CustomPainter {
  final _PaperLayout layout;
  final RobotPose? pose;
  final RobotTrail trail;
  final List<(double, double)>? box;
  final bool boxFits;
  final (double, double)? target;
  final int trackMm;
  final Palette c;

  _PaperPainter({
    required this.layout,
    required this.pose,
    required this.trail,
    required this.box,
    required this.boxFits,
    required this.target,
    required this.trackMm,
    required this.c,
  }) : super(repaint: trail);

  @override
  void paint(Canvas canvas, Size size) {
    final l = layout, p = l.paper;
    if (l.k <= 0) return;
    final sheet = Rect.fromPoints(l.toScreen(0, 0), l.toScreen(p.width.toDouble(), p.height.toDouble()));
    canvas.drawRRect(RRect.fromRectAndRadius(sheet, const Radius.circular(3)), Paint()..color = c.isDark ? const Color(0xFF1B1D22) : Colors.white);

    // Cuadrícula de 5 cm, muy suave: ayuda a ver distancias.
    final grid = Paint()
      ..color = c.line
      ..strokeWidth = 1;
    for (var x = 50; x < p.width; x += 50) {
      canvas.drawLine(l.toScreen(x.toDouble(), 0), l.toScreen(x.toDouble(), p.height.toDouble()), grid);
    }
    for (var y = 50; y < p.height; y += 50) {
      canvas.drawLine(l.toScreen(0, y.toDouble()), l.toScreen(p.width.toDouble(), y.toDouble()), grid);
    }
    canvas.drawRRect(RRect.fromRectAndRadius(sheet, const Radius.circular(3)), Paint()
      ..color = c.line2
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);

    // El 0,0: la esquina donde se pone el robot.
    final origin = l.toScreen(0, 0);
    canvas.drawCircle(origin, 3, Paint()..color = c.green);

    // La tinta: lo que dibujó con el marcador abajo.
    final ink = Paint()
      ..color = c.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.5, l.k * .8)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    for (final pt in trail.points) {
      if (pt == null) {
        if (path != null) canvas.drawPath(path, ink);
        path = null;
        continue;
      }
      final o = l.toScreen(pt.$1, pt.$2);
      if (path == null) {
        path = Path()..moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    if (path != null) canvas.drawPath(path, ink);

    // Dónde caería el texto: verde si cabe, rojo si se sale.
    final b = box;
    if (b != null) {
      final color = boxFits ? c.green : c.red;
      final outline = Path()..addPolygon([for (final (x, y) in b) l.toScreen(x, y)], true);
      canvas.drawPath(outline, Paint()..color = color.withValues(alpha: .12));
      canvas.drawPath(outline, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
    }

    // El punto elegido: una mira.
    final t = target;
    if (t != null) {
      final o = l.toScreen(t.$1, t.$2);
      final mark = Paint()
        ..color = c.amber
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(o, 7, mark);
      canvas.drawLine(o.translate(-11, 0), o.translate(11, 0), mark);
      canvas.drawLine(o.translate(0, -11), o.translate(0, 11), mark);
    }

    // El robot: su silueta a escala (las ruedas a los lados), el marcador al centro y una flecha hacia donde mira.
    final r = pose;
    if (r != null) {
      final o = l.toScreen(r.x, r.y);
      final dir = Offset(cos(r.rad), -sin(r.rad));
      final body = max(10.0, trackMm / 2 * l.k);
      canvas.drawCircle(o, body, Paint()..color = c.blue.withValues(alpha: .06));
      canvas.drawCircle(o, body, Paint()
        ..color = c.blue.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1);
      final side = Offset(-dir.dy, dir.dx);
      final wheel = Paint()
        ..color = c.blue
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      for (final s in [-1.0, 1.0]) {
        final w = o + side * body * s;
        canvas.drawLine(w - dir * body * .35, w + dir * body * .35, wheel);
      }
      final tip = o + dir * (body + 9);
      canvas.drawLine(o, tip, Paint()
        ..color = c.blue
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round);
      canvas.drawPath(
          Path()
            ..moveTo(tip.dx + dir.dx * 6, tip.dy + dir.dy * 6)
            ..lineTo(tip.dx + side.dx * 4, tip.dy + side.dy * 4)
            ..lineTo(tip.dx - side.dx * 4, tip.dy - side.dy * 4)
            ..close(),
          Paint()..color = c.blue);
      canvas.drawCircle(o, 3.5, Paint()..color = c.text);
    }
  }

  @override
  bool shouldRepaint(_PaperPainter old) =>
      old.pose != pose ||
      old.box != box ||
      old.boxFits != boxFits ||
      old.target != target ||
      old.layout.k != layout.k ||
      old.layout.left != layout.left ||
      old.layout.bottom != layout.bottom ||
      old.layout.paper != layout.paper ||
      old.c != c;
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'kit.dart';

/// Joystick de dos ejes: anillos finos y una perilla del color del texto.
/// Entrega x e y entre −100 y 100 (y positivo = adelante). Al soltarlo vuelve al centro.
class Joystick extends StatefulWidget {
  final double size;
  final void Function(int x, int y) onChanged;
  final bool enabled;
  const Joystick({super.key, this.size = 176, required this.onChanged, this.enabled = true});

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _knob = Offset.zero;
  bool _dragging = false;

  double get _r => widget.size / 2 - 32;

  void _update(Offset local) {
    var d = local - Offset(widget.size / 2, widget.size / 2);
    if (d.distance > _r) d = d / d.distance * _r;
    setState(() => _knob = d);
    widget.onChanged((d.dx / _r * 100).round(), (-d.dy / _r * 100).round());
  }

  void _release() {
    setState(() {
      _knob = Offset.zero;
      _dragging = false;
    });
    widget.onChanged(0, 0);
  }

  @override
  void didUpdateWidget(Joystick old) {
    super.didUpdateWidget(old);
    // Si se corta la conexión con el dedo puesto, la perilla vuelve al centro (sin mandar nada).
    if (old.enabled && !widget.enabled && _knob != Offset.zero) {
      _knob = Offset.zero;
      _dragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.size;
    final on = widget.enabled;
    return Semantics(
      label: 'Joystick de manejo',
      child: GestureDetector(
        onPanStart: on
            ? (d) {
                _dragging = true;
                _update(d.localPosition);
              }
            : null,
        onPanUpdate: on ? (d) => _update(d.localPosition) : null,
        onPanEnd: on ? (_) => _release() : null,
        onPanCancel: on ? _release : null,
        child: SizedBox(
          width: s,
          height: s,
          child: Stack(alignment: Alignment.center, children: [
            Container(decoration: BoxDecoration(shape: BoxShape.circle, color: c.surface, border: Border.all(color: c.line2))),
            Container(width: s * 0.56, height: s * 0.56, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.line))),
            // Cruz fina de referencia
            Container(width: 1, height: s - 24, color: c.line),
            Container(width: s - 24, height: 1, color: c.line),
            AnimatedContainer(
              duration: _dragging ? Duration.zero : const Duration(milliseconds: 360),
              curve: Curves.easeOutBack,
              transform: Matrix4.translationValues(_knob.dx, _knob.dy, 0),
              transformAlignment: Alignment.center,
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? c.inverse : c.surface2,
                border: Border.all(color: on ? c.inverse : c.line2),
                boxShadow: on && _dragging ? [BoxShadow(color: c.inverse.withValues(alpha: 0.25), blurRadius: 22)] : null,
              ),
              child: Icon(Ic.steering, size: 24, color: on ? c.onInverse : c.text3),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Dial de 360°: arrastra en círculo para elegir un ángulo de 0 a 359.
class Dial360 extends StatelessWidget {
  final int value;
  final double size;
  final ValueChanged<int> onChanged;
  final bool enabled;
  const Dial360({super.key, required this.value, required this.onChanged, this.size = 104, this.enabled = true});

  void _fromPos(Offset p) {
    final center = Offset(size / 2, size / 2);
    final a = atan2(p.dy - center.dy, p.dx - center.dx) * 180 / pi + 90;
    onChanged(((a.round() % 360) + 360) % 360);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: 'Giro de 360 grados',
      value: '$value grados',
      child: GestureDetector(
        onPanStart: enabled ? (d) => _fromPos(d.localPosition) : null,
        onPanUpdate: enabled ? (d) => _fromPos(d.localPosition) : null,
        onTapDown: enabled ? (d) => _fromPos(d.localPosition) : null,
        child: CustomPaint(
          size: Size.square(size),
          painter: _DialPainter(value, enabled, c),
          child: SizedBox.square(dimension: size, child: Center(child: Text('$value°', style: T.stat.copyWith(fontSize: 20)))),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final int value;
  final bool enabled;
  final Palette c;
  _DialPainter(this.value, this.enabled, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    canvas.drawCircle(center, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = c.line2);
    final tick = Paint()
      ..color = c.text3
      ..strokeWidth = 1;
    for (var i = 0; i < 24; i++) {
      final a = i * pi / 12;
      final inner = i % 6 == 0 ? r - 10 : r - 5;
      canvas.drawLine(center + Offset(cos(a), sin(a)) * inner, center + Offset(cos(a), sin(a)) * r, tick);
    }
    final color = enabled ? c.text : c.text3;
    if (value > 0) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), -pi / 2, value * pi / 180, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color);
    }
    final a = (value - 90) * pi / 180;
    final h = center + Offset(cos(a), sin(a)) * r;
    canvas.drawCircle(h, 7, Paint()..color = c.surface);
    canvas.drawCircle(h, 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.value != value || old.enabled != enabled || old.c != c;
}

/// Acelerador vertical: arrastra hacia arriba para dar más potencia (0 a 100).
class Throttle extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final double width;
  const Throttle({super.key, required this.value, required this.onChanged, this.enabled = true, this.width = 64});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return LayoutBuilder(builder: (context, box) {
      void set(Offset p) => onChanged(((1 - p.dy / box.maxHeight) * 100).clamp(0, 100).round());
      return Semantics(
        label: 'Acelerador',
        value: '$value por ciento',
        child: GestureDetector(
          onPanStart: enabled ? (d) => set(d.localPosition) : null,
          onPanUpdate: enabled ? (d) => set(d.localPosition) : null,
          onTapDown: enabled ? (d) => set(d.localPosition) : null,
          child: Container(
            width: width,
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(R.card), border: Border.all(color: c.line2)),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              // Marcas cada 25 %
              for (final f in const [0.25, 0.5, 0.75])
                Positioned(left: 14, right: 14, bottom: box.maxHeight * f, child: Container(height: 1, color: c.line)),
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  height: box.maxHeight * value / 100,
                  color: enabled ? c.inverse : c.text3,
                ),
              ),
              Positioned(left: 0, right: 0, top: 12, child: Icon(Ic.speed, color: value > 90 ? c.onInverse : c.text2, size: 20)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Text('$value', textAlign: TextAlign.center, style: T.heading.copyWith(color: value > 12 ? c.onInverse : c.text)),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

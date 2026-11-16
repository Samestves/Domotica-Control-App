import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Joystick de dos ejes en vidrio oscuro. Entrega x e y entre −100 y 100 (y positivo = adelante).
/// Al soltarlo vuelve al centro con un pequeño rebote.
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

  double get _r => widget.size / 2 - 34;

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
  Widget build(BuildContext context) {
    final s = widget.size;
    final on = widget.enabled;
    return GestureDetector(
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
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Color(0x1FFFFFFF), Color(0x0AFFFFFF)]),
              border: Border.all(color: C.nightEdge),
            ),
          ),
          Container(
            width: s * 0.56,
            height: s * 0.56,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0x14FFFFFF))),
          ),
          for (final (a, icon) in const [
            (Alignment.topCenter, Icons.keyboard_arrow_up_rounded),
            (Alignment.bottomCenter, Icons.keyboard_arrow_down_rounded),
            (Alignment.centerLeft, Icons.keyboard_arrow_left_rounded),
            (Alignment.centerRight, Icons.keyboard_arrow_right_rounded),
          ])
            Align(alignment: a, child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: const Color(0x4DFFFFFF), size: 22))),
          AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            transform: Matrix4.translationValues(_knob.dx, _knob.dy, 0),
            transformAlignment: Alignment.center,
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: on ? const [Color(0xFF4AA8FF), Color(0xFF0A6BE0)] : const [Color(0xFF4A5363), Color(0xFF2C3340)],
              ),
              border: Border.all(color: const Color(0x40FFFFFF)),
              boxShadow: [BoxShadow(color: C.blue.withValues(alpha: on ? 0.55 : 0), blurRadius: 24, offset: const Offset(0, 6))],
            ),
          ),
        ]),
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
  const Dial360({super.key, required this.value, required this.onChanged, this.size = 108, this.enabled = true});

  void _fromPos(Offset p) {
    final c = Offset(size / 2, size / 2);
    final a = atan2(p.dy - c.dy, p.dx - c.dx) * 180 / pi + 90;
    onChanged(((a.round() % 360) + 360) % 360);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Giro de 360 grados',
      value: '$value grados',
      child: GestureDetector(
        onPanStart: enabled ? (d) => _fromPos(d.localPosition) : null,
        onPanUpdate: enabled ? (d) => _fromPos(d.localPosition) : null,
        onTapDown: enabled ? (d) => _fromPos(d.localPosition) : null,
        child: CustomPaint(
          size: Size.square(size),
          painter: _DialPainter(value, enabled),
          child: SizedBox.square(
            dimension: size,
            child: Center(
              child: Text('$value°', style: T.title3.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  final int value;
  final bool enabled;
  _DialPainter(this.value, this.enabled);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 10;
    canvas.drawCircle(c, r + 8, Paint()..color = const Color(0x14FFFFFF));
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0x1FFFFFFF));
    final tick = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final a = i * pi / 6;
      final inner = i % 3 == 0 ? r - 14 : r - 10;
      canvas.drawLine(c + Offset(cos(a), sin(a)) * inner, c + Offset(cos(a), sin(a)) * (r - 6), tick);
    }
    final color = enabled ? C.blue : const Color(0xFF4A5363);
    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -pi / 2,
        value * pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
    final a = (value - 90) * pi / 180;
    final h = c + Offset(cos(a), sin(a)) * r;
    canvas.drawCircle(h, 10, Paint()..color = Colors.white);
    canvas.drawCircle(h, 6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.value != value || old.enabled != enabled;
}

/// Acelerador vertical: arrastra hacia arriba para dar más potencia (0 a 100).
class Throttle extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final double width;
  const Throttle({super.key, required this.value, required this.onChanged, this.enabled = true, this.width = 60});

  @override
  Widget build(BuildContext context) {
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
            decoration: ShapeDecoration(
              shape: squircle(22, side: const BorderSide(color: C.nightEdge)),
              color: C.nightGlass,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  height: box.maxHeight * value / 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: enabled ? const [Color(0xFF0A6BE0), Color(0xFF4AA8FF)] : const [Color(0xFF2C3340), Color(0xFF4A5363)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 12,
                child: Icon(Icons.speed_rounded, color: Colors.white.withValues(alpha: 0.6), size: 20),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Text('$value', textAlign: TextAlign.center, style: T.headline.copyWith(color: Colors.white)),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

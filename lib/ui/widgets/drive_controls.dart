import 'dart:math';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Joystick de dos ejes. Entrega x e y entre −100 y 100 (y positivo = adelante).
/// Al soltarlo vuelve al centro.
class Joystick extends StatefulWidget {
  final double size;
  final void Function(int x, int y) onChanged;
  final bool enabled;
  const Joystick({super.key, this.size = 170, required this.onChanged, this.enabled = true});

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
  Widget build(BuildContext context) {
    final s = widget.size;
    return GestureDetector(
      onPanStart: widget.enabled
          ? (d) {
              _dragging = true;
              _update(d.localPosition);
            }
          : null,
      onPanUpdate: widget.enabled ? (d) => _update(d.localPosition) : null,
      onPanEnd: widget.enabled ? (_) => _release() : null,
      onPanCancel: widget.enabled ? _release : null,
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [Colors.white, Color(0xFFEEF2F7)], stops: [0, .75]),
              border: Border.all(color: const Color(0xFFD5DCE5), width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, 6))],
            ),
          ),
          Container(width: 1, height: s - 30, color: const Color(0xFFD5DCE5)),
          Container(width: s - 30, height: 1, color: const Color(0xFFD5DCE5)),
          const Positioned(top: 8, child: Text('ADELANTE', style: TextStyle(fontSize: 9, color: C.ink2, letterSpacing: .8))),
          const Positioned(bottom: 8, child: Text('ATRÁS', style: TextStyle(fontSize: 9, color: C.ink2, letterSpacing: .8))),
          AnimatedContainer(
            duration: _dragging ? Duration.zero : const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            transform: Matrix4.translationValues(_knob.dx, _knob.dy, 0),
            transformAlignment: Alignment.center,
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: widget.enabled ? const [Color(0xFF2A8DFF), Color(0xFF0A6BE0)] : const [Color(0xFFB8C0CA), Color(0xFF9AA4B0)],
              ),
              boxShadow: [BoxShadow(color: C.accent.withValues(alpha: widget.enabled ? .4 : 0), blurRadius: 16, offset: const Offset(0, 6))],
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
  const Dial360({super.key, required this.value, required this.onChanged, this.size = 104, this.enabled = true});

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
            child: Center(child: Text('$value°', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
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
    final r = size.width / 2 - 9;
    canvas.drawCircle(c, r + 6, Paint()..color = Colors.white);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFD5DCE5));
    final tick = Paint()
      ..color = const Color(0xFFC4CCD6)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 4; i++) {
      final a = i * pi / 2;
      canvas.drawLine(c + Offset(cos(a), sin(a)) * (r - 8), c + Offset(cos(a), sin(a)) * (r - 3), tick);
    }
    final color = enabled ? C.accent : const Color(0xFF9AA4B0);
    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -pi / 2,
        value * pi / 180,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
    final a = (value - 90) * pi / 180;
    final h = c + Offset(cos(a), sin(a)) * r;
    canvas.drawCircle(h, 8.5, Paint()..color = Colors.white);
    canvas.drawCircle(h, 6.5, Paint()..color = color);
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
  const Throttle({super.key, required this.value, required this.onChanged, this.enabled = true, this.width = 54});

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
            decoration: BoxDecoration(color: const Color(0xFFDFE5EC), borderRadius: BorderRadius.circular(width / 2)),
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
                      colors: enabled ? const [Color(0xFF0A6BE0), Color(0xFF3FA0FF)] : const [Color(0xFF9AA4B0), Color(0xFFB8C0CA)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Text('$value', textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700, color: value > 12 ? Colors.white : C.ink2)),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

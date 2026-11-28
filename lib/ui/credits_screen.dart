import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Créditos escondidos de la app. Se abren tocando 3 veces el logo en «Acerca de».
class Credits {
  static const project = 'Casa domótica';

  /// El equipo de la casa domótica, en orden alfabético: nadie va primero.
  static const team = [
    'Ana Camila Guzmán',
    'Ana María Guzmán',
    'Antoni Cortéz',
    'Diana Yegüez',
    'Edglis Felicce',
    'Karlibet Vega',
    'Samuel Esteves',
    'Victoria Santodomingo',
  ];
}

/// Abre los créditos con un fundido, encima de lo que esté abierto.
Future<void> showCredits(BuildContext context) {
  HapticFeedback.heavyImpact();
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 600),
    reverseTransitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (_, _, _) => const CreditsScreen(),
    transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child),
  ));
}

/// Momento (0 a 1 de la entrada) en que se enciende la estrella de cada integrante y aparece su nombre.
const _starAt = [0.08, 0.17, 0.25, 0.33, 0.41, 0.49, 0.57, 0.65];

/// Dónde queda cada estrella (0 a 1): los ocho puntos del logo. El orden sigue el de [_starAt]: primero la
/// señal del centro y después la casa, punto por punto. Las esquinas de arriba de las paredes quedan sobre el
/// techo, así la línea que las une sigue el alero.
const _starPos = [
  Offset(0.5, 0.68), // señal
  Offset(0.03, 0.47), // punta izquierda del alero
  Offset(0.5, 0.06), // techo
  Offset(0.97, 0.47), // punta derecha del alero
  Offset(0.84, 0.36), // pared derecha, arriba
  Offset(0.84, 0.95), // piso derecho
  Offset(0.16, 0.95), // piso izquierdo
  Offset(0.16, 0.36), // pared izquierda, arriba
];

/// Cielo negro con estrellas. Ocho se encienden una por una, se unen y forman la casa del logo;
/// con cada una aparece el nombre de quien la hizo. Siempre en oscuro, sin importar el tema.
class CreditsScreen extends StatefulWidget {
  const CreditsScreen({super.key});

  @override
  State<CreditsScreen> createState() => _CreditsScreenState();
}

class _CreditsScreenState extends State<CreditsScreen> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  late final _sky = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  final _anims = <String, CurvedAnimation>{};
  int _lit = 0;

  @override
  void initState() {
    super.initState();
    assert(_starAt.length == Credits.team.length && _starPos.length == Credits.team.length, 'una estrella por integrante');
    // Un toquecito en la mano por cada estrella que se enciende.
    _intro.addListener(() {
      while (_lit < _starAt.length && _intro.value >= _starAt[_lit]) {
        _lit++;
        HapticFeedback.selectionClick();
      }
    });
    _intro.forward();
  }

  @override
  void dispose() {
    for (final a in _anims.values) {
      a.dispose();
    }
    _intro.dispose();
    _sky.dispose();
    super.dispose();
  }

  Animation<double> _at(double from, [double length = 0.14]) => _anims.putIfAbsent(
      '$from/$length', () => CurvedAnimation(parent: _intro, curve: Interval(from, math.min(1, from + length), curve: Curves.easeOutCubic)));

  /// Aparece subiendo un poco desde [from].
  Widget _rise(double from, Widget child) {
    final a = _at(from);
    return FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    const p = Palette.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Stack(fit: StackFit.expand, children: [
            RepaintBoundary(child: CustomPaint(painter: _SkyPainter(_sky))),
            SafeArea(
              child: LayoutBuilder(builder: (context, box) {
                // En pantallas bajitas se achica todo junto en vez de cortarse.
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: box.maxWidth,
                    height: math.max(box.maxHeight, 660),
                    child: Column(children: [
                      const Spacer(flex: 3),
                      _rise(0.0, Text('CONTROL DOMÓTICA', style: T.eyebrow.copyWith(color: p.text, fontSize: 13, letterSpacing: 5))),
                      const SizedBox(height: 40),
                      RepaintBoundary(
                        child: CustomPaint(size: const Size(176, 176), painter: _ConstellationPainter(intro: _intro, sky: _sky)),
                      ),
                      const Spacer(flex: 3),
                      _rise(0.04, Text('UN PROYECTO DE', style: T.eyebrow.copyWith(color: p.text3, letterSpacing: 4))),
                      const SizedBox(height: 26),
                      for (var i = 0; i < Credits.team.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        _Name(Credits.team[i], reveal: _at(_starAt[i], 0.22)),
                      ],
                      const Spacer(flex: 4),
                      _rise(0.8, Text('${Credits.project.toUpperCase()}  ·  ${DateTime.now().year}',
                          style: T.eyebrow.copyWith(color: p.text3, fontSize: 10.5, letterSpacing: 3))),
                      const SizedBox(height: 22),
                    ]),
                  ),
                );
              }),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Un nombre en mayúsculas espaciadas, al estilo de los títulos de Starlink: el nombre en blanco
/// y el apellido en gris. Aparece abriéndose desde el centro, con las letras separándose.
class _Name extends StatelessWidget {
  final String full;
  final Animation<double> reveal;
  const _Name(this.full, {required this.reveal});

  @override
  Widget build(BuildContext context) {
    const p = Palette.dark;
    final cut = full.lastIndexOf(' ');
    final first = full.substring(0, cut).toUpperCase();
    final last = full.substring(cut + 1).toUpperCase();
    return AnimatedBuilder(
      animation: reveal,
      builder: (_, _) {
        final v = reveal.value;
        final spacing = 1.2 + 2.6 * v;
        return Opacity(
          opacity: v,
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: first, style: T.button.copyWith(color: p.text, fontSize: 15, letterSpacing: spacing)),
              TextSpan(text: '  $last', style: T.button.copyWith(color: p.text3, fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: spacing)),
            ]),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        );
      },
    );
  }
}

/// Las ocho estrellas: se encienden con un destello, se unen con líneas finas y la del centro
/// manda su señal hacia arriba, como el logo.
class _ConstellationPainter extends CustomPainter {
  final Animation<double> intro, sky;
  _ConstellationPainter({required this.intro, required this.sky}) : super(repaint: Listenable.merge([intro, sky]));

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro.value;
    final seconds = sky.value * 60;
    Offset at(int i) => Offset(_starPos[i].dx * size.width, _starPos[i].dy * size.height);

    // Líneas: cada una corre de una estrella a la siguiente mientras esta se enciende.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    void segment(int from, int to, double start, double end) {
      final k = ((t - start) / (end - start)).clamp(0.0, 1.0);
      if (k <= 0) return;
      canvas.drawLine(at(from), Offset.lerp(at(from), at(to), Curves.easeInOut.transform(k))!, line);
    }

    for (var j = 2; j < _starPos.length; j++) {
      segment(j - 1, j, _starAt[j - 1], _starAt[j]);
    }
    segment(_starPos.length - 1, 1, _starAt.last, _starAt.last + 0.1); // cierra la casa

    // Señal del centro: ondas que suben, como en el logo.
    final signal = ((t - _starAt[0]) / 0.1).clamp(0.0, 1.0);
    if (signal > 0) {
      final c = at(0);
      for (var i = 0; i < 2; i++) {
        final k = ((seconds / 2.4) + i / 2) % 1.0;
        canvas.drawArc(
          Rect.fromCircle(center: c, radius: size.width * (0.08 + 0.2 * k)),
          -math.pi / 2 - 0.8,
          1.6,
          false,
          Paint()
            ..color = Colors.white.withValues(alpha: signal * math.sin(k * math.pi) * 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Estrellas: un destello al encenderse y después titilan suave.
    for (var i = 0; i < _starPos.length; i++) {
      final since = t - _starAt[i];
      if (since < 0) continue;
      final on = (since / 0.05).clamp(0.0, 1.0);
      final flash = since < 0.12 ? 1 - since / 0.12 : 0.0;
      final twinkle = 0.85 + 0.15 * math.sin(seconds * 1.7 + i * 1.3);
      final c = at(i);
      final glowR = 9 + 16 * flash;
      canvas.drawCircle(
        c,
        glowR,
        Paint()
          ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.35 * on * twinkle), Colors.white.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: glowR)),
      );
      canvas.drawCircle(c, 2.6 + 1.4 * flash, Paint()..color = Colors.white.withValues(alpha: on * twinkle));
    }
  }

  @override
  bool shouldRepaint(_ConstellationPainter old) => false;
}

/// Cielo de fondo: estrellas pequeñas que titilan y bajan muy despacio.
class _SkyPainter extends CustomPainter {
  final Animation<double> clock;
  _SkyPainter(this.clock) : super(repaint: clock);

  static final _stars = () {
    final r = math.Random(42);
    return List.generate(140, (_) {
      final depth = r.nextDouble();
      return (
        x: r.nextDouble(),
        y: r.nextDouble(),
        size: 0.4 + depth * 1.2,
        speed: 0.6 + r.nextDouble() * 1.6,
        phase: r.nextDouble() * math.pi * 2,
        depth: depth,
      );
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = clock.value * 60;
    final dot = Paint();
    for (final s in _stars) {
      // Las más cercanas bajan un poco más rápido: da sensación de profundidad.
      final y = (s.y + seconds * (0.002 + 0.006 * s.depth)) % 1.0;
      final twinkle = 0.5 + 0.5 * math.sin(seconds * s.speed + s.phase);
      dot.color = Colors.white.withValues(alpha: (0.12 + 0.5 * s.depth) * (0.35 + 0.65 * twinkle));
      canvas.drawCircle(Offset(s.x * size.width, y * size.height), s.size, dot);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => false;
}

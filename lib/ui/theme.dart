import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Colores de la app, en claro y en oscuro, al estilo Starlink:
/// fondo negro (o casi blanco), superficies planas con un borde fino y un solo color fuerte: el texto.
@immutable
class Palette extends ThemeExtension<Palette> {
  final Brightness brightness;

  /// Fondo de la pantalla.
  final Color bg;

  /// Tarjetas.
  final Color surface;

  /// Controles y tarjetas dentro de tarjetas.
  final Color surface2;

  /// Borde fino de las tarjetas.
  final Color line;

  /// Borde de botones y separadores marcados.
  final Color line2;

  /// Texto principal, secundario y terciario.
  final Color text, text2, text3;

  /// Botón principal: blanco sobre negro (oscuro) o negro sobre blanco (claro).
  final Color inverse, onInverse;

  /// Estados.
  final Color green, amber, red, blue;

  /// Luz encendida: tono cálido.
  final Color glow;

  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.line2,
    required this.text,
    required this.text2,
    required this.text3,
    required this.inverse,
    required this.onInverse,
    required this.green,
    required this.amber,
    required this.red,
    required this.blue,
    required this.glow,
  });

  bool get isDark => brightness == Brightness.dark;

  static const dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    surface: Color(0xFF0C0D0F),
    surface2: Color(0xFF15171A),
    line: Color(0xFF1F2125),
    line2: Color(0xFF30333A),
    text: Color(0xFFF0F0FA),
    text2: Color(0xFF9AA0A9),
    text3: Color(0xFF6E737C), // ~4,2:1 sobre negro (antes 3,3:1)
    inverse: Color(0xFFF0F0FA),
    onInverse: Color(0xFF000000),
    green: Color(0xFF3DDC97),
    amber: Color(0xFFF5B841),
    red: Color(0xFFFF5A5F),
    blue: Color(0xFF5AA2FF),
    glow: Color(0xFFFFCF70),
  );

  static const light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFF3F3F4),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF4F5F7),
    line: Color(0xFFE3E4E8),
    line2: Color(0xFFCDD0D6),
    text: Color(0xFF0A0B0D),
    text2: Color(0xFF5F646C),
    text3: Color(0xFF767B83), // ~4,1:1 sobre blanco (antes 2,4:1)
    inverse: Color(0xFF0A0B0D),
    onInverse: Color(0xFFFFFFFF),
    green: Color(0xFF119A4F),
    amber: Color(0xFFB97F00),
    red: Color(0xFFDB3439),
    blue: Color(0xFF1F6FEB),
    glow: Color(0xFFDB9600),
  );

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) => t < 0.5 || other == null ? this : other;
}

extension PaletteOf on BuildContext {
  /// Los colores del tema actual: `context.c.text`, `context.c.surface`...
  Palette get c => Theme.of(this).extension<Palette>() ?? Palette.dark;
}

/// Letra D-DIN, de la familia DIN que usa SpaceX. Solo dos pesos: normal y negrita.
/// Las etiquetas (eyebrow) y los botones van en MAYÚSCULAS espaciadas; los textos largos, normales.
class T {
  static const family = 'DDIN';
  static const _tab = [FontFeature.tabularFigures()];

  static const display = TextStyle(fontFamily: family, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 0.3, height: 1.05);
  static const title = TextStyle(fontFamily: family, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 0.3, height: 1.1);
  static const heading = TextStyle(fontFamily: family, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: 0.3, height: 1.15);
  static const body = TextStyle(fontFamily: family, fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.2, height: 1.35);
  static const callout = TextStyle(fontFamily: family, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3, height: 1.2);
  static const small = TextStyle(fontFamily: family, fontSize: 13.5, fontWeight: FontWeight.w400, letterSpacing: 0.2, height: 1.35);

  /// Etiqueta pequeña en mayúsculas: «CONEXIÓN», «SALA», «2 DE 6».
  static const eyebrow = TextStyle(fontFamily: family, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.8, height: 1.2);

  /// Texto de los botones, en mayúsculas.
  static const button = TextStyle(fontFamily: family, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1.5, height: 1);

  /// Números grandes de los resúmenes.
  static const stat = TextStyle(fontFamily: family, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 0.2, height: 1, fontFeatures: _tab);

  static const mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5);
}

/// Radios de las esquinas.
class R {
  static const card = 16.0;
  static const tile = 14.0;
  static const control = 12.0;
  static const sheet = 22.0;
}

/// Perilla del deslizador: un círculo pequeño del color del texto.
class _Thumb extends SliderComponentShape {
  final Color color, ring;
  const _Thumb(this.color, this.ring);
  static const _r = 9.0;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size.fromRadius(_r);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final canvas = context.canvas;
    final grow = 1 + 0.25 * activationAnimation.value;
    canvas.drawCircle(center, _r * grow + 3, Paint()..color = ring);
    canvas.drawCircle(center, _r * grow, Paint()..color = enableAnimation.value < 1 ? ring : color);
  }
}

ThemeData buildTheme(Brightness brightness) {
  final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: T.family,
    colorScheme: ColorScheme.fromSeed(
      seedColor: p.blue,
      brightness: brightness,
      primary: p.inverse,
      onPrimary: p.onInverse,
      surface: p.surface,
      onSurface: p.text,
    ),
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: p.text.withValues(alpha: 0.04),
    hoverColor: Colors.transparent,
    dividerColor: p.line,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    extensions: [p],
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: T.family, bodyColor: p.text, displayColor: p.text),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.text, selectionColor: p.text.withValues(alpha: 0.2), selectionHandleColor: p.text),
    inputDecorationTheme: InputDecorationTheme(
      border: InputBorder.none,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      hintStyle: T.body.copyWith(color: p.text3),
    ),
    iconTheme: IconThemeData(color: p.text, size: 22),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface2,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.control), side: BorderSide(color: p.line2)),
      textStyle: T.body.copyWith(color: p.text),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 3,
      activeTrackColor: p.text,
      inactiveTrackColor: p.line2,
      thumbShape: _Thumb(p.text, p.surface),
      overlayShape: SliderComponentShape.noOverlay,
      trackShape: const RoundedRectSliderTrackShape(),
      disabledActiveTrackColor: p.text3,
      disabledInactiveTrackColor: p.line,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.inverse,
      contentTextStyle: T.small.copyWith(color: p.onInverse),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.control)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.text, linearTrackColor: p.line, strokeWidth: 2),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.inverse, borderRadius: BorderRadius.circular(8)),
      textStyle: T.small.copyWith(color: p.onInverse),
    ),
  );
}

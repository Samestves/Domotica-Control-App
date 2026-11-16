import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Colores con nombre de iOS: así la app se siente de la misma familia que el sistema de Apple.
class C {
  // Texto
  static const label = Color(0xFF1C1C1E);
  static const label2 = Color(0x993C3C43); // secundario (60 %)
  static const label3 = Color(0x4D3C3C43); // terciario (30 %)
  static const separator = Color(0x1F3C3C43);

  // Acentos del sistema
  static const blue = Color(0xFF007AFF);
  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9500);
  static const red = Color(0xFFFF3B30);
  static const yellow = Color(0xFFFFCC00);
  static const teal = Color(0xFF30B0C7);

  // Rellenos y vidrio sobre el fondo claro
  static const fill = Color(0x1F787880);
  static const glass = Color(0x73FFFFFF); // tarjeta apagada: deja ver el fondo
  static const glassSolid = Color(0xEBFFFFFF); // tarjeta encendida o barra
  static const glassEdge = Color(0xB3FFFFFF); // borde con brillo

  // Fondo «de pantalla»
  static const skyTop = Color(0xFFE6EEF7);
  static const sandBottom = Color(0xFFF3EEE9);

  // Modo cabina (carro)
  static const night = Color(0xFF0B1220);
  static const nightGlass = Color(0x1AFFFFFF);
  static const nightEdge = Color(0x24FFFFFF);
  static const nightLabel2 = Color(0x99EBEBF5);
}

/// Escala tipográfica de iOS con Inter. Los títulos grandes usan InterDisplay, más ajustada.
class T {
  static const _display = 'InterDisplay';

  static const largeTitle = TextStyle(fontFamily: _display, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.9, height: 1.12, color: C.label);
  static const title1 = TextStyle(fontFamily: _display, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: C.label);
  static const title2 = TextStyle(fontFamily: _display, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: C.label);
  static const title3 = TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: C.label);
  static const headline = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: C.label);
  static const body = TextStyle(fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: -0.4, color: C.label);
  static const callout = TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: -0.3, color: C.label);
  static const subhead = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.2, color: C.label);
  static const footnote = TextStyle(fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: -0.1, color: C.label2);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: C.label2);
  static const sectionHeader = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.2, color: C.label2);
  static const mono = TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.45);
}

/// Radios de las esquinas continuas (squircle), como en iOS.
class R {
  static const tile = 22.0;
  static const card = 26.0;
  static const control = 14.0;
  static const sheet = 30.0;
}

ShapeBorder squircle(double radius, {BorderSide side = BorderSide.none}) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius), side: side);

/// Perilla del deslizador como la de iOS: círculo blanco con borde fino y sombra suave.
class IosThumbShape extends SliderComponentShape {
  const IosThumbShape();
  static const _r = 13.0;

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
    canvas.drawCircle(center + const Offset(0, 1.5), _r, Paint()
      ..color = const Color(0x24000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawCircle(center, _r, Paint()..color = Colors.white);
    canvas.drawCircle(center, _r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5
      ..color = const Color(0x1F000000));
  }
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Inter',
    colorScheme: ColorScheme.fromSeed(seedColor: C.blue, brightness: Brightness.light, primary: C.blue, surface: C.skyTop),
    scaffoldBackgroundColor: C.skyTop,
    // iOS no tiene «ondas» al tocar: solo un leve oscurecimiento.
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x0A000000),
    // Transiciones de pantalla deslizando desde la derecha, como en el iPhone.
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
  final controlShape = WidgetStatePropertyAll<OutlinedBorder>(RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(R.control)));

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Inter', bodyColor: C.label, displayColor: C.label),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: C.blue, selectionHandleColor: C.blue),
    inputDecorationTheme: const InputDecorationTheme(
      border: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 14),
      hintStyle: TextStyle(color: C.label3),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? C.fill : C.blue),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? C.label3 : Colors.white),
        minimumSize: const WidgetStatePropertyAll(Size(0, 50)),
        shape: controlShape,
        elevation: const WidgetStatePropertyAll(0),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? C.label3 : C.blue),
        shape: controlShape,
        textStyle: const WidgetStatePropertyAll(TextStyle(fontFamily: 'Inter', fontSize: 17, fontWeight: FontWeight.w500, letterSpacing: -0.4)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.glassSolid,
      elevation: 12,
      shadowColor: const Color(0x401B2A3A),
      surfaceTintColor: Colors.transparent,
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(R.control)),
      textStyle: T.body,
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 6,
      activeTrackColor: C.blue,
      inactiveTrackColor: Color(0x29787880),
      thumbColor: Colors.white,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 0),
      thumbShape: IosThumbShape(),
      trackShape: RoundedRectSliderTrackShape(),
      disabledThumbColor: Color(0xFFF2F2F7),
      disabledActiveTrackColor: Color(0x33787880),
      disabledInactiveTrackColor: Color(0x1F787880),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xE61C1C1E),
      contentTextStyle: T.subhead.copyWith(color: Colors.white),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(R.control)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.label2, strokeWidth: 2),
  );
}

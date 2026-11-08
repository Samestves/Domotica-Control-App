import 'package:flutter/material.dart';

/// Paleta sobria tipo iOS: fondo gris claro, tarjetas blancas, un solo azul de acento.
class C {
  static const bg = Color(0xFFF2F3F7);
  static const card = Colors.white;
  static const ink = Color(0xFF0E1A28);
  static const ink2 = Color(0xFF6B7684);
  static const line = Color(0xFFE3E7EC);
  static const fill = Color(0xFFEEF1F5);
  static const accent = Color(0xFF0A7CFF);
  static const ok = Color(0xFF2FBF5B);
  static const warn = Color(0xFFFF9F0A);
  static const danger = Color(0xFFFF3B30);
  static const night = Color(0xFF1C1F26);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: C.accent, brightness: Brightness.light, surface: C.bg),
    scaffoldBackgroundColor: C.bg,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.ink, displayColor: C.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(color: C.ink, fontSize: 17, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.night,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Tarjeta blanca redondeada, la pieza base de toda la app.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color = C.card, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(duration: const Duration(milliseconds: 250), padding: padding, child: child),
      ),
    );
  }
}

class PinTag extends StatelessWidget {
  final String text;
  final bool dark;
  const PinTag(this.text, {super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: dark ? Colors.white12 : C.fill, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: dark ? Colors.white70 : C.ink2)),
    );
  }
}

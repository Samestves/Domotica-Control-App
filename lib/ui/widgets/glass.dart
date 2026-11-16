import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Fondo «de pantalla»: un degradado suave con manchas de color, para que el vidrio tenga qué dejar ver.
class Wallpaper extends StatelessWidget {
  final bool dark;
  const Wallpaper({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _WallpaperPainter(dark), size: Size.infinite);
}

class _WallpaperPainter extends CustomPainter {
  final bool dark;
  _WallpaperPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF0E1726), C.night] : const [C.skyTop, C.sandBottom],
        ).createShader(rect),
    );
    final blobs = dark
        ? const [(Alignment(-0.9, -0.8), Color(0x332E6BFF), 0.9), (Alignment(1.0, 0.7), Color(0x264C2BFF), 0.8)]
        : const [
            (Alignment(-1.0, -0.85), Color(0x667FB4F0), 0.85), // cielo
            (Alignment(1.1, -0.1), Color(0x4DF6C7A6), 0.75), // durazno
            (Alignment(-0.9, 0.9), Color(0x40A9E3CF), 0.8), // menta
          ];
    final d = size.longestSide;
    for (final (align, color, scale) in blobs) {
      final center = align.alongSize(size);
      final r = d * scale * 0.55;
      canvas.drawCircle(
        center,
        r,
        Paint()..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) => old.dark != dark;
}

/// Superficie de vidrio con esquinas continuas.
///
/// Sin [blur] es un vidrio «quieto»: translúcido, barato de dibujar, ideal para tarjetas sobre el fondo.
/// Con [blur] desenfoca lo que pasa por detrás (barras y hojas), como en iOS.
class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final bool blur;
  final bool dark;
  final bool shadow;

  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = R.card,
    this.color,
    this.gradient,
    this.blur = false,
    this.dark = false,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: dark ? C.nightEdge : C.glassEdge, width: 0.8),
    );
    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: padding,
      decoration: ShapeDecoration(
        shape: shape,
        color: gradient == null ? (color ?? (dark ? C.nightGlass : C.glass)) : null,
        gradient: gradient,
        shadows: shadow && !blur
            ? [BoxShadow(color: dark ? const Color(0x33000000) : const Color(0x0D1B2A3A), blurRadius: 18, offset: const Offset(0, 4))]
            : null,
      ),
      child: child,
    );
    if (blur) {
      box = ClipRSuperellipse(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: box),
      );
    }
    return box;
  }
}

/// Se encoge un poco al tocarlo, como los botones de iOS.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Pressable({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.97});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onTapDown: active ? (_) => _set(true) : null,
      onTapUp: active ? (_) => _set(false) : null,
      onTapCancel: active ? () => _set(false) : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Botón redondo de vidrio con un icono (atrás, más, menú…).
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool dark;
  final Color? iconColor;
  const GlassIconButton({super.key, required this.icon, required this.tooltip, this.onTap, this.dark = false, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.9,
        child: Glass(
          radius: 20,
          padding: const EdgeInsets.all(9),
          dark: dark,
          color: dark ? C.nightGlass : C.glassSolid,
          shadow: false,
          child: Icon(icon, size: 22, color: iconColor ?? (dark ? Colors.white : C.blue)),
        ),
      ),
    );
  }
}

/// Cápsula pequeña con icono y texto (estados, resúmenes).
class Capsule extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;
  final Color? background;
  const Capsule(this.text, {super.key, this.icon, this.color = C.label2, this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 10 : 8, 5, 10, 5),
      decoration: ShapeDecoration(shape: const StadiumBorder(), color: background ?? color.withValues(alpha: 0.12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
        Text(text, style: T.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// Título de sección, como «Sala» o «PLACAS CERCANAS».
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final bool small;
  const SectionTitle(this.text, {super.key, this.trailing, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: small ? const EdgeInsets.fromLTRB(16, 22, 16, 8) : const EdgeInsets.fromLTRB(4, 26, 4, 12),
      child: Row(children: [
        Expanded(child: Text(small ? text.toUpperCase() : text, style: small ? T.sectionHeader : T.title2)),
        ?trailing,
      ]),
    );
  }
}

/// Grupo de filas como en Ajustes de iOS: una tarjeta de vidrio con separadores finos.
class GlassGroup extends StatelessWidget {
  final List<Widget> children;
  final String? footer;
  const GlassGroup({super.key, required this.children, this.footer});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Divider(height: 0.6, thickness: 0.6, indent: 16, color: C.separator));
      rows.add(children[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Glass(padding: EdgeInsets.zero, radius: R.tile, color: C.glassSolid, child: Column(children: rows)),
      if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(footer!, style: T.footnote)),
    ]);
  }
}

/// Hoja inferior de vidrio con su «tirador», como las hojas de iOS.
Future<V?> showGlassSheet<V>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<V>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x33000000),
    elevation: 0,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: ClipRSuperellipse(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.sheet)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            color: const Color(0xE6F2F4F8),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 6),
                    width: 36,
                    height: 5,
                    decoration: const ShapeDecoration(shape: StadiumBorder(), color: Color(0x4D3C3C43)),
                  ),
                ),
                Builder(builder: builder),
              ]),
            ),
          ),
        ),
      ),
    ),
  );
}

/// El icono de la app, dibujado: casa blanca sobre un degradado azul con esquinas continuas.
class AppGlyph extends StatelessWidget {
  final double size;
  const AppGlyph({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: squircle(size * 0.27),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3AA0FF), Color(0xFF0060E0)]),
        shadows: [BoxShadow(color: const Color(0xFF0A6BE0).withValues(alpha: 0.35), blurRadius: size * 0.3, offset: Offset(0, size * 0.1))],
      ),
      child: Icon(Icons.home_rounded, color: Colors.white, size: size * 0.58),
    );
  }
}

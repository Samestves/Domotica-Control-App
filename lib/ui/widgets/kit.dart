import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Iconos de línea fina (Phosphor «light», licencia MIT: assets/fonts/LICENSE-Phosphor.txt)
/// y su versión rellena para lo que está encendido. Cada uno es un carácter de la letra de iconos.
class Ic {
  static const house = IconData(0xe2c6, fontFamily: 'PhosphorLight') /* houseSimple */;
  static const car = IconData(0xe8cc, fontFamily: 'PhosphorLight') /* carProfile */;
  static const plus = IconData(0xe3d4, fontFamily: 'PhosphorLight') /* plus */;
  static const settings = IconData(0xe272, fontFamily: 'PhosphorLight') /* gearSix */;
  static const back = IconData(0xe138, fontFamily: 'PhosphorLight') /* caretLeft */;
  static const more = IconData(0xe1fe, fontFamily: 'PhosphorLight') /* dotsThree */;
  static const chevronRight = IconData(0xe13a, fontFamily: 'PhosphorLight') /* caretRight */;
  static const chevronDown = IconData(0xe136, fontFamily: 'PhosphorLight') /* caretDown */;
  static const close = IconData(0xe4f6, fontFamily: 'PhosphorLight') /* x */;
  static const check = IconData(0xe182, fontFamily: 'PhosphorLight') /* check */;
  static const checkCircle = IconData(0xe184, fontFamily: 'PhosphorFill') /* checkCircle */;
  static const warning = IconData(0xe4e2, fontFamily: 'PhosphorLight') /* warningCircle */;
  static const bluetooth = IconData(0xe0da, fontFamily: 'PhosphorLight') /* bluetooth */;
  static const wifi = IconData(0xe4ea, fontFamily: 'PhosphorLight') /* wifiHigh */;
  static const demo = IconData(0xe6a2, fontFamily: 'PhosphorLight') /* sparkle */;
  static const board = IconData(0xe610, fontFamily: 'PhosphorLight') /* cpu */;
  static const link = IconData(0xe2e2, fontFamily: 'PhosphorLight') /* link */;
  static const unlink = IconData(0xe2e4, fontFamily: 'PhosphorLight') /* linkBreak */;
  static const sync = IconData(0xe094, fontFamily: 'PhosphorLight') /* arrowsClockwise */;
  static const play = IconData(0xe3d0, fontFamily: 'PhosphorLight') /* play */;
  static const trash = IconData(0xe4a6, fontFamily: 'PhosphorLight') /* trash */;
  static const lock = IconData(0xe2fa, fontFamily: 'PhosphorLight') /* lock */;
  static const eye = IconData(0xe220, fontFamily: 'PhosphorLight') /* eye */;
  static const download = IconData(0xe20c, fontFamily: 'PhosphorLight') /* downloadSimple */;
  static const eyeOff = IconData(0xe224, fontFamily: 'PhosphorLight') /* eyeSlash */;
  static const lockOpen = IconData(0xe306, fontFamily: 'PhosphorLight') /* lockOpen */;
  static const terminal = IconData(0xeae8, fontFamily: 'PhosphorLight') /* terminalWindow */;
  static const pins = IconData(0xe610, fontFamily: 'PhosphorLight') /* cpu */;
  static const sun = IconData(0xe472, fontFamily: 'PhosphorLight') /* sun */;
  static const moon = IconData(0xe330, fontFamily: 'PhosphorLight') /* moon */;
  static const system = IconData(0xe18c, fontFamily: 'PhosphorLight') /* circleHalf */;
  static const info = IconData(0xe2ce, fontFamily: 'PhosphorLight') /* info */;
  static const mic = IconData(0xe326, fontFamily: 'PhosphorLight') /* microphone */;
  static const micFill = IconData(0xe326, fontFamily: 'PhosphorFill') /* microphone */;
  static const stop = IconData(0xe46c, fontFamily: 'PhosphorFill') /* stop */;
  static const bell = IconData(0xe5e8, fontFamily: 'PhosphorLight') /* bellRinging */;

  // Casa
  static const light = IconData(0xe2dc, fontFamily: 'PhosphorLight') /* lightbulb */;
  static const lightOn = IconData(0xe2dc, fontFamily: 'PhosphorFill') /* lightbulb */;
  static const door = IconData(0xe61c, fontFamily: 'PhosphorLight') /* door */;
  static const doorOpen = IconData(0xe7e6, fontFamily: 'PhosphorFill') /* doorOpen */;
  static const garage = IconData(0xecd6, fontFamily: 'PhosphorLight') /* garage */;
  static const garageOpen = IconData(0xecd6, fontFamily: 'PhosphorFill') /* garage */;
  static const blind = IconData(0xe5a2, fontFamily: 'PhosphorLight') /* rows */;
  static const blindOpen = IconData(0xe5a2, fontFamily: 'PhosphorFill') /* rows */;
  static const shield = IconData(0xe40a, fontFamily: 'PhosphorLight') /* shield */;
  static const shieldOn = IconData(0xe40c, fontFamily: 'PhosphorFill') /* shieldCheck */;
  static const siren = IconData(0xe9b8, fontFamily: 'PhosphorLight') /* siren */;
  static const sirenOn = IconData(0xe9b8, fontFamily: 'PhosphorFill') /* siren */;

  // Habitaciones
  static IconData room(String r) => switch (r) {
        'Sala' => const IconData(0xe7f6, fontFamily: 'PhosphorLight') /* couch */,
        'Cocina' => const IconData(0xe764, fontFamily: 'PhosphorLight') /* cookingPot */,
        'Baño' => const IconData(0xe81e, fontFamily: 'PhosphorLight') /* bathtub */,
        'Cuarto' => const IconData(0xe0cc, fontFamily: 'PhosphorLight') /* bed */,
        'Garaje' => const IconData(0xecd6, fontFamily: 'PhosphorLight') /* garage */,
        'Entrada' => const IconData(0xe61c, fontFamily: 'PhosphorLight') /* door */,
        _ => const IconData(0xe464, fontFamily: 'PhosphorLight') /* squaresFour */,
      };

  // Carrito
  static const headlights = IconData(0xe6fe, fontFamily: 'PhosphorLight') /* headlights */;
  static const horn = IconData(0xe324, fontFamily: 'PhosphorLight') /* megaphone */;
  static const brake = IconData(0xe57e, fontFamily: 'PhosphorLight') /* handPalm */;
  static const reverse = IconData(0xe07e, fontFamily: 'PhosphorLight') /* arrowUDownLeft */;
  static const speed = IconData(0xe628, fontFamily: 'PhosphorLight') /* gauge */;
  static const distance = IconData(0xe1d6, fontFamily: 'PhosphorLight') /* crosshair */;
  static const steering = IconData(0xe9ac, fontFamily: 'PhosphorLight') /* steeringWheel */;
  static const wheels = IconData(0xe434, fontFamily: 'PhosphorLight') /* slidersHorizontal */;
}

/// Se atenúa y se encoge apenas al tocarlo.
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Tap({super.key, required this.child, this.onTap, this.onLongPress, this.scale = 0.98});

  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
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
      child: AnimatedOpacity(
        opacity: _down ? 0.72 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedScale(scale: _down ? widget.scale : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      ),
    );
  }
}

/// Tarjeta plana con borde fino.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? border;
  final double borderWidth;

  /// Resplandor suave (por ejemplo, una luz encendida en modo oscuro).
  final Color? glow;
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.radius = R.card, this.color, this.border, this.borderWidth = 1, this.glow});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? c.line, width: borderWidth),
        boxShadow: [BoxShadow(color: glow ?? Colors.transparent, blurRadius: 26, spreadRadius: -2)],
      ),
      child: child,
    );
  }
}

/// Etiqueta pequeña en mayúsculas.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;
  final int maxLines;
  const Eyebrow(this.text, {super.key, this.color, this.maxLines = 2});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: T.eyebrow.copyWith(color: color ?? context.c.text2), maxLines: maxLines, overflow: TextOverflow.ellipsis);
}

/// Título de una sección: «HABITACIONES», «REGISTRO»…
class SectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionHeader(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(4, 28, 4, 10)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(children: [Expanded(child: Eyebrow(text)), ?trailing]),
    );
  }
}

class Hairline extends StatelessWidget {
  final bool vertical;
  const Hairline({super.key, this.vertical = false});

  @override
  Widget build(BuildContext context) =>
      vertical ? Container(width: 1, color: context.c.line) : Container(height: 1, color: context.c.line);
}

enum PillKind { primary, secondary, danger, dangerFilled, ghost }

/// Lo que muestra un botón después de tocarlo: enviando, listo (la placa confirmó) o sin respuesta.
enum PillState { idle, busy, done, failed }

/// Botón en forma de píldora, con el texto en mayúsculas.
/// El texto nunca se corta con «…»: si no cabe, se achica un poco.
class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final PillKind kind;
  final IconData? icon;
  final bool small;
  final bool expand;
  final Widget? leading;
  final PillState state;
  const PillButton(this.label,
      {super.key, this.onTap, this.kind = PillKind.primary, this.icon, this.small = false, this.expand = false, this.leading, this.state = PillState.idle});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (Color bg, Color fg, Color border) = switch (kind) {
      PillKind.primary => (c.inverse, c.onInverse, c.inverse),
      PillKind.secondary => (Colors.transparent, c.text, c.line2),
      PillKind.danger => (Colors.transparent, c.red, c.red.withValues(alpha: 0.5)),
      PillKind.dangerFilled => (c.red, Colors.white, c.red),
      PillKind.ghost => (c.surface2, c.text, c.surface2),
    };
    final h = small ? 34.0 : 46.0;
    final iconSize = small ? 16.0 : 18.0;
    final Widget? lead = switch (state) {
      PillState.busy => SizedBox(width: iconSize - 2, height: iconSize - 2, child: CircularProgressIndicator(strokeWidth: 1.6, color: fg)),
      PillState.done => Icon(Ic.check, size: iconSize, color: fg),
      PillState.failed => Icon(Ic.warning, size: iconSize, color: fg),
      PillState.idle => leading ?? (icon == null ? null : Icon(icon, size: iconSize, color: fg)),
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
          child: lead == null ? const SizedBox(key: ValueKey('none')) : Padding(key: ValueKey(state), padding: const EdgeInsets.only(right: 8), child: lead),
        ),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label.toUpperCase(), style: T.button.copyWith(color: fg, fontSize: small ? 11.5 : 13, letterSpacing: small ? 1.3 : 1.5), maxLines: 1),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Tap(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: onTap == null ? 0.38 : 1,
          child: Container(
            height: h,
            padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20),
            decoration: ShapeDecoration(shape: StadiumBorder(side: BorderSide(color: border)), color: bg),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Botón redondo con un icono (volver, agregar, ajustes, menú).
class RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final bool filled;
  const RoundButton({super.key, required this.icon, required this.tooltip, this.onTap, this.size = 42, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Tap(
          onTap: onTap,
          scale: 0.92,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? c.inverse : c.surface,
              border: Border.all(color: filled ? c.inverse : c.line2),
            ),
            child: Icon(icon, size: size * 0.48, color: filled ? c.onInverse : c.text),
          ),
        ),
      ),
    );
  }
}

/// Resumen en columnas separadas por líneas finas, como las cifras de Starlink.
class StatStrip extends StatelessWidget {
  final List<(String value, String label, Color? color)> items;
  const StatStrip({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: IntrinsicHeight(
        child: Row(children: [
          for (final (i, (value, label, color)) in items.indexed) ...[
            if (i > 0) const Hairline(vertical: true),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(value, style: T.stat.copyWith(color: color ?? c.text), maxLines: 1),
                  const SizedBox(height: 6),
                  Eyebrow(label),
                ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Interruptor plano: pista del color del texto cuando está encendido.
/// La perilla salta con un pequeño rebote; con [busy] muestra que está esperando a la placa.
/// [icon] va dibujado dentro de la perilla (por ejemplo, un bombillo).
/// [onFilled]: para usarlo sobre una tarjeta encendida (rellena del color del texto).
class Toggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final bool busy;
  final bool large;
  final IconData? icon;
  final bool onFilled;
  const Toggle({super.key, required this.value, this.onChanged, this.activeColor, this.busy = false, this.large = false, this.icon, this.onFilled = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = large ? 60.0 : 46.0, h = large ? 34.0 : 28.0, knob = h - 8;
    final track = onFilled ? c.onInverse : (activeColor ?? c.inverse);
    final knobOn = onFilled ? c.inverse : (activeColor == null ? c.onInverse : Colors.white);
    final knobColor = value ? knobOn : c.text3;
    final glyph = value ? track : c.surface2;
    return Semantics(
      toggled: value,
      enabled: onChanged != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onChanged!(!value);
              },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: onChanged == null && !busy ? 0.4 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            width: w,
            height: h,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? track : (onFilled ? Colors.transparent : c.surface2),
              borderRadius: BorderRadius.circular(h / 2),
              border: Border.all(color: value ? track : c.line2),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: knobColor,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: value ? 0.18 : 0), blurRadius: 4, offset: const Offset(0, 1))],
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: busy
                      ? SizedBox(key: const ValueKey('busy'), width: knob * 0.55, height: knob * 0.55, child: CircularProgressIndicator(strokeWidth: 1.6, color: glyph))
                      : (icon == null ? const SizedBox(key: ValueKey('none')) : Icon(icon, key: ValueKey(value), size: knob * 0.62, color: glyph)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Selector de opciones en una cápsula: la elegida va rellena.
class Segmented<V> extends StatelessWidget {
  final V value;
  final Map<V, String> items;
  final ValueChanged<V> onChanged;
  final Map<V, IconData>? icons;
  const Segmented({super.key, required this.value, required this.items, required this.onChanged, this.icons});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(999), border: Border.all(color: c.line)),
      child: Row(children: [
        for (final e in items.entries)
          Expanded(
            child: Semantics(
              selected: e.key == value,
              button: true,
              label: e.value,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(e.key);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 38,
                  decoration: BoxDecoration(color: e.key == value ? c.inverse : Colors.transparent, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (icons?[e.key] != null) ...[
                      Icon(icons![e.key], size: 15, color: e.key == value ? c.onInverse : c.text2),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(e.value.toUpperCase(),
                            style: T.button.copyWith(fontSize: 11.5, letterSpacing: 1.2, color: e.key == value ? c.onInverse : c.text2), maxLines: 1),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Fila de una lista dentro de una tarjeta: icono, texto y algo a la derecha.
class ListRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  const ListRow({super.key, required this.title, this.icon, this.iconColor, this.detail, this.trailing, this.onTap, this.titleColor});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onTap,
      scale: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 21, color: iconColor ?? titleColor ?? c.text), const SizedBox(width: 14)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: T.body.copyWith(color: titleColor ?? c.text)),
              if (detail != null) ...[const SizedBox(height: 2), Text(detail!, style: T.small.copyWith(color: c.text2))],
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

/// Varias filas en una sola tarjeta, separadas por líneas finas.
class RowGroup extends StatelessWidget {
  final List<Widget> children;
  final String? footer;
  const RowGroup({super.key, required this.children, this.footer});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(const Padding(padding: EdgeInsets.only(left: 16), child: Hairline()));
      rows.add(children[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(padding: EdgeInsets.zero, child: Column(children: rows)),
      if (footer != null)
        Padding(padding: const EdgeInsets.fromLTRB(4, 10, 4, 0), child: Text(footer!, style: T.small.copyWith(color: context.c.text2))),
    ]);
  }
}

/// Hoja que sube desde abajo, plana, con su tirador.
Future<V?> showAppSheet<V>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<V>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    elevation: 0,
    // Los colores se leen dentro de la hoja: si se cambia de claro a oscuro con la hoja abierta, cambia con ella.
    builder: (ctx) => _SheetFrame(builder: builder),
  );
}

class _SheetFrame extends StatelessWidget {
  final WidgetBuilder builder;
  const _SheetFrame({required this.builder});

  @override
  Widget build(BuildContext ctx) {
    final c = ctx.c;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(R.sheet)),
          border: Border(top: BorderSide(color: c.line2)),
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: c.line2, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Flexible(child: Builder(builder: builder)),
          ]),
        ),
      ),
    );
  }
}

/// Encabezado de una hoja: etiqueta, título y una explicación corta.
class SheetHeader extends StatelessWidget {
  final String? eyebrow;
  final String title;
  final String? detail;
  const SheetHeader({super.key, this.eyebrow, required this.title, this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (eyebrow != null) ...[Eyebrow(eyebrow!), const SizedBox(height: 6)],
      Text(title, style: T.title),
      if (detail != null) ...[const SizedBox(height: 6), Text(detail!, style: T.small.copyWith(color: context.c.text2))],
    ]);
  }
}

/// Punto de estado. Late despacio cuando [pulse] es true (conectando).
class StatusDot extends StatefulWidget {
  final Color color;
  final bool pulse;
  final double size;
  const StatusDot({super.key, required this.color, this.pulse = false, this.size = 7});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.pulse) {
      if (!_anim.isAnimating) _anim.repeat(reverse: true);
    } else {
      _anim.stop();
      _anim.value = 1;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_anim),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: widget.size * 1.4)],
        ),
      ),
    );
  }
}

/// Línea de progreso fina que corre de lado a lado (conectando, enviando).
class ThinProgress extends StatelessWidget {
  final Color? color;
  const ThinProgress({super.key, this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 2,
        child: LinearProgressIndicator(minHeight: 2, color: color ?? context.c.text, backgroundColor: Colors.transparent),
      );
}

/// El símbolo de la app: una casa de línea fina con una señal inalámbrica dentro.
class AppMark extends StatelessWidget {
  final double size;
  final Color? color;
  const AppMark({super.key, this.size = 30, this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MarkPainter(color ?? context.c.text));
}

class _MarkPainter extends CustomPainter {
  final Color color;
  _MarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.065
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // Techo y paredes
    canvas.drawPath(Path()..moveTo(p(0.08, 0.47).dx, p(0.08, 0.47).dy)..lineTo(p(0.5, 0.1).dx, p(0.5, 0.1).dy)..lineTo(p(0.92, 0.47).dx, p(0.92, 0.47).dy), line);
    canvas.drawPath(
        Path()
          ..moveTo(p(0.2, 0.38).dx, p(0.2, 0.38).dy)
          ..lineTo(p(0.2, 0.9).dx, p(0.2, 0.9).dy)
          ..lineTo(p(0.8, 0.9).dx, p(0.8, 0.9).dy)
          ..lineTo(p(0.8, 0.38).dx, p(0.8, 0.38).dy),
        line);
    // Señal: un punto y dos ondas hacia arriba
    final center = p(0.5, 0.75);
    canvas.drawCircle(center, s * 0.055, Paint()..color = color);
    for (final r in [0.15, 0.27]) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: s * r), -2.36, 1.57, false, line);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}

/// Logo y nombre de la app, para la barra de arriba del inicio.
class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Control Domótica',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const AppMark(size: 28),
        const SizedBox(width: 12),
        // Con letra grande en un teléfono angosto, el nombre se achica en vez de salirse.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('CONTROL DOMÓTICA', maxLines: 1, style: T.button.copyWith(letterSpacing: 2.6, color: context.c.text)),
          ),
        ),
      ]),
    );
  }
}

/// El logo de la app dentro de un círculo relleno (pantalla «Acerca de»).
class AppGlyph extends StatelessWidget {
  final double size;
  const AppGlyph({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c.inverse),
      alignment: Alignment.center,
      child: AppMark(size: size * 0.56, color: c.onInverse),
    );
  }
}

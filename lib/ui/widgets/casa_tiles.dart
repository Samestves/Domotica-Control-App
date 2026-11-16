import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/controls.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'glass.dart';

IconData controlIcon(ControlSpec c, {required bool on}) => switch (c.kind) {
      ControlKind.light => on ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
      ControlKind.door when c.isGarage => on ? Icons.garage_rounded : Icons.garage_outlined,
      ControlKind.door => on ? Icons.door_front_door_rounded : Icons.door_front_door_outlined,
      ControlKind.blind => on ? Icons.blinds_rounded : Icons.blinds_closed_rounded,
    };

/// Color del icono cuando el control está activo: amarillo para luces, azul para el resto.
Color _accent(ControlKind k) => k == ControlKind.light ? const Color(0xFFFFB800) : C.blue;
Color _accentBg(ControlKind k) => k == ControlKind.light ? const Color(0xFFFFF1C2) : const Color(0xFFDCEBFF);

/// Icono en un círculo que se «enciende» con el color del control.
class _IconDisc extends StatelessWidget {
  final IconData icon;
  final bool on;
  final ControlKind kind;
  const _IconDisc({required this.icon, required this.on, required this.kind});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? _accentBg(kind) : C.fill,
        boxShadow: on && kind == ControlKind.light ? const [BoxShadow(color: Color(0x80FFD54F), blurRadius: 16)] : null,
      ),
      child: Icon(icon, size: 22, color: on ? _accent(kind) : C.label2),
    );
  }
}

/// Tarjeta de un accesorio (luz o puerta): vidrio cuando está apagado, blanca cuando está activo.
class AccessoryTile extends StatelessWidget {
  final Session session;
  final ControlSpec spec;
  final bool showPins;
  const AccessoryTile({super.key, required this.session, required this.spec, required this.showPins});

  @override
  Widget build(BuildContext context) {
    final enabled = spec.isEnabledOn(session.device);
    final on = session.values[spec.vpin] == '1';
    final isLight = spec.kind == ControlKind.light;
    final status = !enabled ? 'Sin conectar' : (isLight ? (on ? 'Encendida' : 'Apagada') : (on ? 'Abierta' : 'Cerrada'));
    final usable = enabled && session.connected;

    return Pressable(
      onTap: usable
          ? () {
              HapticFeedback.selectionClick();
              session.send(spec.vpin, on ? 0 : 1);
            }
          : null,
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showPinSheet(context, session, spec);
      },
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Glass(
          radius: R.tile,
          color: on ? C.glassSolid : C.glass,
          shadow: false,
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(children: [
            _IconDisc(icon: controlIcon(spec, on: on), on: on, kind: spec.kind),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(spec.label, style: T.subhead.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(status, style: T.footnote.copyWith(color: on ? _accent(spec.kind) : C.label2, fontWeight: on ? FontWeight.w600 : null)),
                if (showPins) Text(pinLabel(session.device, spec), style: T.caption.copyWith(fontSize: 11), maxLines: 1),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Persiana con un deslizador de 0° a 180°. Mientras se arrastra, envía como mucho un mensaje cada 120 ms.
class BlindTile extends StatefulWidget {
  final Session session;
  final ControlSpec spec;
  final bool showPins;
  const BlindTile({super.key, required this.session, required this.spec, required this.showPins});

  @override
  State<BlindTile> createState() => _BlindTileState();
}

class _BlindTileState extends State<BlindTile> {
  double? _dragging;
  Timer? _throttle;

  Session get _s => widget.session;
  ControlSpec get _spec => widget.spec;

  @override
  void dispose() {
    _throttle?.cancel();
    super.dispose();
  }

  void _onChanged(double v) {
    setState(() => _dragging = v);
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(milliseconds: 120), () => _s.send(_spec.vpin, _dragging!.round(), quiet: true));
  }

  void _onChangeEnd(double v) {
    _throttle?.cancel();
    _s.send(_spec.vpin, v.round());
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _spec.isEnabledOn(_s.device);
    final value = _dragging ?? (double.tryParse(_s.values[_spec.vpin] ?? '0') ?? 0);
    final percent = (value / CasaPins.blindMax * 100).round();
    final open = percent > 0;

    return GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        showPinSheet(context, _s, _spec);
      },
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Glass(
          radius: R.tile,
          color: open ? C.glassSolid : C.glass,
          shadow: false,
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 6),
          child: Column(children: [
            Row(children: [
              _IconDisc(icon: controlIcon(_spec, on: open), on: open, kind: _spec.kind),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_spec.label, style: T.subhead.copyWith(fontWeight: FontWeight.w600)),
                  Text(!enabled ? 'Sin conectar' : (open ? 'Abierta' : 'Cerrada'), style: T.footnote.copyWith(color: open ? C.blue : C.label2, fontWeight: open ? FontWeight.w600 : null)),
                  if (widget.showPins) Text(pinLabel(_s.device, _spec), style: T.caption.copyWith(fontSize: 11)),
                ]),
              ),
              if (open) Text('$percent %', style: T.title3.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
            SizedBox(
              height: 40,
              child: Slider(
                value: value.clamp(0, CasaPins.blindMax.toDouble()),
                max: CasaPins.blindMax.toDouble(),
                onChanged: _s.connected && enabled ? _onChanged : null,
                onChangeEnd: _onChangeEnd,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Seguridad: armar y desarmar, sirena manual y avisos de la placa.
/// Cambia de aspecto según el estado: vidrio (desarmada), oscuro (armada) o rojo latiendo (sonando).
class SecurityCard extends StatefulWidget {
  final Session session;
  const SecurityCard({super.key, required this.session});

  @override
  State<SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends State<SecurityCard> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _send(int pin, int value) {
    HapticFeedback.mediumImpact();
    widget.session
      ..clearAlert()
      ..send(pin, value);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final armed = s.values[CasaPins.armed] == '1';
    final sounding = s.values[CasaPins.siren] == '1';
    final notice = s.values[CasaPins.notice];
    if (sounding && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!sounding && _pulse.isAnimating) _pulse.stop();

    final dark = armed || sounding;
    final fg = dark ? Colors.white : C.label;
    final fg2 = dark ? const Color(0xB3FFFFFF) : C.label2;
    final title = sounding ? 'Alarma sonando' : (armed ? 'Armada' : 'Desarmada');
    final description = notice ??
        (armed
            ? 'Si el garaje o la puerta principal quedan abiertos 20 s, suena la sirena.'
            : 'Ármala para vigilar el garaje y la puerta principal.');

    final card = Glass(
      radius: R.card,
      color: armed && !sounding ? const Color(0xEB1C1C1E) : null,
      gradient: sounding ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFF5147), Color(0xFFD70F3A)]) : null,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sounding ? const Color(0x33FFFFFF) : (armed ? C.green : C.fill),
            ),
            child: Icon(
              sounding ? Icons.notifications_active_rounded : (armed ? Icons.shield_rounded : Icons.shield_outlined),
              color: dark ? Colors.white : C.label2,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Seguridad', style: T.footnote.copyWith(color: fg2, fontWeight: FontWeight.w500)),
              Text(title, style: T.title3.copyWith(color: fg)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(description, style: T.subhead.copyWith(color: fg2)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: _CardButton(
              label: sounding ? 'Apagar alarma' : (armed ? 'Desarmar' : 'Armar'),
              background: dark ? Colors.white : C.blue,
              foreground: sounding ? C.red : (dark ? C.label : Colors.white),
              onTap: s.connected ? () => _send(CasaPins.armed, armed || sounding ? 0 : 1) : null,
            ),
          ),
          if (!sounding) ...[
            const SizedBox(width: 10),
            _CardButton(
              label: 'Sirena',
              icon: Icons.campaign_rounded,
              background: dark ? const Color(0x26FFFFFF) : const Color(0x1AFF3B30),
              foreground: dark ? Colors.white : C.red,
              onTap: s.connected ? () => _send(CasaPins.siren, 1) : null,
            ),
          ],
        ]),
      ]),
    );

    if (!sounding) return card;
    // Halo rojo que late mientras suena la alarma.
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, child) => DecoratedBox(
        decoration: ShapeDecoration(
          shape: squircle(R.card),
          shadows: [BoxShadow(color: C.red.withValues(alpha: 0.25 + 0.3 * _pulse.value), blurRadius: 18 + 18 * _pulse.value)],
        ),
        child: child,
      ),
      child: card,
    );
  }
}

class _CardButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color background, foreground;
  final VoidCallback? onTap;
  const _CardButton({required this.label, required this.background, required this.foreground, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: ShapeDecoration(shape: squircle(R.control), color: background),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 19, color: foreground), const SizedBox(width: 6)],
            Text(label, style: T.headline.copyWith(color: foreground, fontSize: 16)),
          ]),
        ),
      ),
    );
  }
}

/// Resumen de la casa en cápsulas, como el de la app Casa de Apple.
class SummaryStrip extends StatelessWidget {
  final Session session;
  const SummaryStrip({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final v = session.values;
    final d = session.device;
    /// «2 de 6» activos de un tipo, o «Todas» si no hay ninguno. El icono dice de qué tipo es.
    (String, String) count(ControlKind k, bool Function(String?) isOn, String onWord, String offWord) {
      final all = casaControls.where((c) => c.kind == k && c.isEnabledOn(d)).toList();
      final n = all.where((c) => isOn(v[c.vpin])).length;
      return n == 0 ? ('Todas', offWord) : ('$n de ${all.length}', onWord);
    }

    final lights = count(ControlKind.light, (x) => x == '1', 'encendidas', 'apagadas');
    final doors = count(ControlKind.door, (x) => x == '1', 'abiertas', 'cerradas');
    final blinds = count(ControlKind.blind, (x) => (int.tryParse(x ?? '') ?? 0) > 0, 'abiertas', 'cerradas');

    return Row(children: [
      Expanded(child: _SummaryChip(icon: Icons.lightbulb_rounded, color: const Color(0xFFFFB800), value: lights.$1, label: lights.$2)),
      const SizedBox(width: 8),
      Expanded(child: _SummaryChip(icon: Icons.door_front_door_rounded, color: C.blue, value: doors.$1, label: doors.$2)),
      const SizedBox(width: 8),
      Expanded(child: _SummaryChip(icon: Icons.blinds_rounded, color: C.teal, value: blinds.$1, label: blinds.$2)),
    ]);
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _SummaryChip({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 20,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 8),
        Text(value, style: T.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(label, style: T.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Encender o apagar todas las luces de una vez.
class AllLightsRow extends StatelessWidget {
  final Session session;
  const AllLightsRow({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final usable = session.connected;
    void all(int v) {
      HapticFeedback.selectionClick();
      session.send(CasaPins.allLights, v, remember: false);
    }

    return Row(children: [
      Expanded(child: _QuickAction(icon: Icons.lightbulb_rounded, iconColor: const Color(0xFFFFB800), label: 'Encender todas', onTap: usable ? () => all(1) : null)),
      const SizedBox(width: 10),
      Expanded(child: _QuickAction(icon: Icons.lightbulb_outline_rounded, iconColor: C.label2, label: 'Apagar todas', onTap: usable ? () => all(0) : null)),
    ]);
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;
  const _QuickAction({required this.icon, required this.iconColor, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Glass(
          radius: R.tile,
          shadow: false,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(label, style: T.subhead.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

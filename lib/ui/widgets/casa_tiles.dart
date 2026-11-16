import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/controls.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'common.dart';

/// Base de las tarjetas cuadradas (luces y puertas): icono y acción arriba, nombre y pin abajo.
class _SquareTile extends StatelessWidget {
  final Session session;
  final ControlSpec spec;
  final Widget leading;
  final Widget trailing;
  final String? status;
  final VoidCallback? onTap;

  const _SquareTile({
    required this.session,
    required this.spec,
    required this.leading,
    required this.trailing,
    this.status,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = spec.isEnabledOn(session.device);
    return Panel(
      onTap: enabled && session.connected ? onTap : null,
      onLongPress: () => showPinSheet(context, session, spec),
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [leading, if (enabled) trailing]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            if (status != null) Text(status!, style: const TextStyle(fontSize: 12.5, color: C.ink2)),
            const SizedBox(height: 3),
            PinTag(pinLabel(session.device, spec)),
          ]),
        ]),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final bool on;
  final Color onColor, onIconColor;
  const _IconBadge({required this.icon, required this.on, required this.onColor, required this.onIconColor});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: on ? onColor : C.fill,
        borderRadius: BorderRadius.circular(11),
        boxShadow: on ? [BoxShadow(color: onColor, blurRadius: 16)] : null,
      ),
      child: Icon(icon, size: 19, color: on ? onIconColor : C.ink2),
    );
  }
}

class LightTile extends StatelessWidget {
  final Session session;
  final ControlSpec spec;
  const LightTile({super.key, required this.session, required this.spec});

  bool get _on => session.values[spec.vpin] == '1';

  void _set(bool on) {
    HapticFeedback.selectionClick();
    session.send(spec.vpin, on ? 1 : 0);
  }

  @override
  Widget build(BuildContext context) {
    return _SquareTile(
      session: session,
      spec: spec,
      onTap: () => _set(!_on),
      leading: _IconBadge(icon: spec.icon, on: _on, onColor: const Color(0xFFFFF3C4), onIconColor: const Color(0xFF7A6100)),
      trailing: CupertinoSwitch(value: _on, activeTrackColor: C.ok, onChanged: session.connected ? _set : null),
    );
  }
}

class DoorTile extends StatelessWidget {
  final Session session;
  final ControlSpec spec;
  const DoorTile({super.key, required this.session, required this.spec});

  @override
  Widget build(BuildContext context) {
    final open = session.values[spec.vpin] == '1';
    return _SquareTile(
      session: session,
      spec: spec,
      status: open ? 'Abierta' : 'Cerrada',
      onTap: () {
        HapticFeedback.mediumImpact();
        session.send(spec.vpin, open ? 0 : 1);
      },
      leading: _IconBadge(icon: spec.icon, on: open, onColor: const Color(0xFFDCEBFF), onIconColor: C.accent),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: const Color(0xFFE7F0FF), borderRadius: BorderRadius.circular(99)),
        child: Text(open ? 'Cerrar' : 'Abrir', style: const TextStyle(color: C.accent, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }
}

/// Persiana con slider de 0° a 180°. Mientras se arrastra, envía como mucho un mensaje cada 120 ms.
class BlindTile extends StatefulWidget {
  final Session session;
  final ControlSpec spec;
  const BlindTile({super.key, required this.session, required this.spec});

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
    return Panel(
      onLongPress: () => showPinSheet(context, _s, _spec),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: Column(children: [
          Row(children: [
            Icon(_spec.icon, color: C.ink2, size: 20),
            const SizedBox(width: 8),
            Text(_spec.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(width: 8),
            Flexible(child: PinTag(pinLabel(_s.device, _spec))),
            const Spacer(),
            Text(percent == 0 ? 'Cerrada' : '$percent %',
                style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
          Slider(
            value: value.clamp(0, CasaPins.blindMax.toDouble()),
            max: CasaPins.blindMax.toDouble(),
            onChanged: _s.connected && enabled ? _onChanged : null,
            onChangeEnd: _onChangeEnd,
          ),
        ]),
      ),
    );
  }
}

/// Seguridad: armar y desarmar, sirena manual y avisos de la placa.
class SecurityCard extends StatelessWidget {
  final Session session;
  const SecurityCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final armed = s.values[CasaPins.armed] == '1';
    final sounding = s.values[CasaPins.siren] == '1';
    final notice = s.values[CasaPins.notice];
    final bg = sounding ? C.danger : (armed ? C.night : C.card);
    final fg = sounding || armed ? Colors.white : C.ink;
    final status = sounding ? '¡Alarma sonando!' : (armed ? 'Armada' : 'Desarmada');

    void send(int pin, int value) {
      HapticFeedback.mediumImpact();
      s.clearAlert();
      s.send(pin, value);
    }

    return Panel(
      color: bg,
      onLongPress: () => showPinSheet(context, s, casaSiren),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(sounding ? Icons.warning_amber_rounded : Icons.shield_outlined, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Seguridad', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .7))),
              Text(status, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg)),
            ]),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              backgroundColor: armed || sounding ? Colors.white : C.accent,
              foregroundColor: armed || sounding ? C.ink : Colors.white,
            ),
            onPressed: s.connected ? () => send(CasaPins.armed, armed || sounding ? 0 : 1) : null,
            child: Text(sounding ? 'Apagar' : (armed ? 'Desarmar' : 'Armar')),
          ),
        ]),
        const SizedBox(height: 8),
        Text(
          notice ?? (armed ? 'Si el garaje o la puerta principal quedan abiertos 20 s, suena la sirena.' : 'Ármala para vigilar el garaje y la puerta principal.'),
          style: TextStyle(fontSize: 13, color: fg.withValues(alpha: .8)),
        ),
        if (!sounding)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: armed ? Colors.white : C.danger, padding: EdgeInsets.zero),
              onPressed: s.connected ? () => send(CasaPins.siren, 1) : null,
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: const Text('Sonar sirena'),
            ),
          ),
      ]),
    );
  }
}

/// Encender o apagar todas las luces de una vez.
class AllLightsCard extends StatelessWidget {
  final Session session;
  const AllLightsCard({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final lights = casaControls.where((c) => c.kind == ControlKind.light && c.isEnabledOn(session.device));
    final on = lights.where((c) => session.values[c.vpin] == '1').length;
    final usable = session.connected;
    return Panel(
      child: Row(children: [
        const Icon(Icons.lightbulb_outline, color: C.ink2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Todas las luces', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            Text('$on de ${lights.length} encendidas', style: const TextStyle(fontSize: 12.5, color: C.ink2)),
          ]),
        ),
        TextButton(onPressed: usable ? () => session.send(CasaPins.allLights, 0, remember: false) : null, child: const Text('Apagar')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: usable ? () => session.send(CasaPins.allLights, 1, remember: false) : null,
          child: const Text('Encender'),
        ),
      ]),
    );
  }
}

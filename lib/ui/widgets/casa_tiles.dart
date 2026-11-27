import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/controls.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'common.dart';
import 'kit.dart';

IconData controlIcon(ControlSpec c, {required bool on}) => switch (c.kind) {
      ControlKind.light => on ? Ic.lightOn : Ic.light,
      ControlKind.door when c.isGarage => on ? Ic.garageOpen : Ic.garage,
      ControlKind.door => on ? Ic.doorOpen : Ic.door,
      ControlKind.blind => on ? Ic.blindOpen : Ic.blind,
    };

bool isOn(Session s, ControlSpec spec) =>
    spec.kind == ControlKind.blind ? (int.tryParse(s.values[spec.vpin] ?? '') ?? 0) > 0 : s.values[spec.vpin] == '1';

int blindPercent(Session s, ControlSpec spec) => ((double.tryParse(s.values[spec.vpin] ?? '0') ?? 0) / CasaPins.blindMax * 100).round();

String stateWord(Session s, ControlSpec spec) {
  if (!spec.isEnabledOn(s.device)) return 'Sin conectar';
  if (s.unconfirmed.contains(spec.vpin)) return 'Sin respuesta';
  if (s.pending.contains(spec.vpin)) return 'Enviando…';
  final on = isOn(s, spec);
  return switch (spec.kind) {
    ControlKind.light => on ? 'Encendida' : 'Apagada',
    ControlKind.door => on ? 'Abierta' : 'Cerrada',
    ControlKind.blind => on ? 'Abierta' : 'Cerrada',
  };
}

/// Mientras la placa no confirma la orden anterior de este control, otro toque no hace nada:
/// un doble toque abriría y cerraría la puerta (o prendería y apagaría la luz) sin querer.
void _toggle(Session s, ControlSpec spec) {
  if (s.pending.contains(spec.vpin)) return;
  HapticFeedback.selectionClick();
  s.send(spec.vpin, isOn(s, spec) ? 0 : 1, confirm: true);
}

void _editPins(BuildContext context, Session s, ControlSpec spec) {
  HapticFeedback.mediumImpact();
  showPinSheet(context, s, spec);
}

/// Cambio de icono con un pequeño salto: se nota que algo pasó.
Widget _swapIcon(IconData icon, double size, Color color) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: _popIn,
      child: Icon(icon, key: ValueKey(icon), size: size, color: color),
    );

/// Aparece creciendo con un pequeño rebote. Función fija (no se crea en cada dibujo) y sin CurvedAnimation:
/// así no quedan escuchas pegadas a la animación, aunque la tarjeta se redibuje muchas veces (sirena sonando).
Widget _popIn(Widget child, Animation<double> a) => ScaleTransition(
      scale: a.drive(CurveTween(curve: Curves.easeOutBack)).drive(Tween(begin: 0.6, end: 1.0)),
      child: FadeTransition(opacity: a, child: child),
    );

/// Indicador pequeño en la esquina: girando mientras espera a la placa, aviso si no respondió.
Widget _confirmMark(Session s, int pin, Color color, Palette c) {
  final Widget child;
  if (s.pending.contains(pin)) {
    child = SizedBox(key: const ValueKey('wait'), width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: color));
  } else if (s.unconfirmed.contains(pin)) {
    child = Icon(Ic.warning, key: const ValueKey('fail'), size: 18, color: c.red);
  } else {
    child = const SizedBox(key: ValueKey('off'), width: 14, height: 14);
  }
  return AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: child);
}

/// Todas las luces en un solo interruptor: si hay alguna encendida, lo apaga todo; si no, lo enciende todo.
/// Debajo dice cuántas hay encendidas. Las puertas abiertas las dice la tarjeta de seguridad, donde importan,
/// y cada habitación dice lo suyo: no hace falta un resumen de cifras aparte.
class AllLightsRow extends StatelessWidget {
  final Session session;
  const AllLightsRow({super.key, required this.session});

  List<int> get _lights => casaControls.where((x) => x.kind == ControlKind.light && x.isEnabledOn(session.device)).map((x) => x.vpin).toList();

  void _all(int v) {
    session.expect(_lights);
    session.send(CasaPins.allLights, v, remember: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lights = _lights;
    final n = lights.where((p) => session.values[p] == '1').length;
    final anyOn = n > 0;
    final busy = lights.any(session.pending.contains);
    final failed = lights.any(session.unconfirmed.contains);
    final usable = session.connected && !busy;
    final detail = failed
        ? 'Alguna luz no respondió'
        : busy
            ? 'Enviando…'
            : (n == 0 ? 'Todas apagadas' : (n == lights.length ? 'Todas encendidas' : '$n de ${lights.length} encendidas'));

    return Semantics(
      button: true,
      toggled: anyOn,
      label: 'Todas las luces',
      child: Tap(
        onTap: usable ? () => _all(anyOn ? 0 : 1) : null,
        scale: 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(children: [
            _swapIcon(anyOn ? Ic.lightOn : Ic.light, 24, anyOn ? c.text : c.text2),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Todas las luces', style: T.callout),
                const SizedBox(height: 3),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(detail, key: ValueKey(detail), style: T.small.copyWith(color: failed ? c.red : c.text2)),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Toggle(value: anyOn, large: true, busy: busy, icon: Ic.lightOn, onChanged: usable ? (v) => _all(v ? 1 : 0) : null),
          ]),
        ),
      ),
    );
  }
}

/// Seguridad: armar y desarmar, sirena manual y avisos de la placa.
class SecurityCard extends StatefulWidget {
  final Session session;
  const SecurityCard({super.key, required this.session});

  @override
  State<SecurityCard> createState() => _SecurityCardState();
}

class _SecurityCardState extends State<SecurityCard> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Armar, desarmar y la sirena comparten el mismo lugar en pantalla: mientras cualquiera de ellos
  /// espera a la placa, no se acepta otro toque (si no, un doble toque arma y desarma).
  bool get _waiting => widget.session.pending.any((p) => p == CasaPins.armed || p == CasaPins.siren);

  void _send(int pin, int value) {
    if (_waiting) return;
    HapticFeedback.mediumImpact();
    widget.session
      ..clearAlert()
      ..send(pin, value, confirm: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.session;
    final armed = s.values[CasaPins.armed] == '1';
    final sounding = s.values[CasaPins.siren] == '1';
    final notice = s.values[CasaPins.notice];
    if (sounding && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!sounding && _pulse.isAnimating) _pulse.stop();

    final title = sounding ? 'Alarma sonando' : (armed ? 'Armada' : 'Desarmada');
    // Las dos entradas que vigila la alarma: si alguna está abierta, se dice aquí, antes de armar.
    final open = casaControls
        .where((x) => (x.vpin == CasaPins.mainDoor || x.isGarage) && x.isEnabledOn(s.device) && isOn(s, x))
        .toList();
    final openText = open.isEmpty
        ? null
        : open.length > 1
            ? 'La puerta principal y el portón del garaje están abiertos.'
            : (open.single.isGarage ? 'El portón del garaje está abierto.' : 'La puerta principal está abierta.');
    // Un aviso de la placa que solo repite el título («Seguridad desarmada») no se muestra.
    final news = notice == null || RegExp(r'^seguridad (armada|desarmada)\.?$', caseSensitive: false).hasMatch(notice.trim()) ? null : notice;
    // Primero lo que pasa ahora: la alarma, una entrada abierta; después el último aviso de la placa.
    final description = sounding
        ? (_cause(notice, true) ?? 'Se abrió una entrada vigilada.')
        : openText != null
            ? (armed ? '$openText Si sigue así 20 s, suena la sirena.' : '$openText Si la armas así, la sirena suena en 20 s.')
            : (news ?? (armed ? 'Si el garaje o la puerta principal quedan abiertos 20 s, suena la sirena.' : 'Ármala para vigilar el garaje y la puerta principal.'));
    final warn = !sounding && openText != null;
    final accent = sounding ? c.red : (armed ? c.green : c.text2);
    PillState stateOf(int pin) => s.pending.contains(pin) ? PillState.busy : (s.unconfirmed.contains(pin) ? PillState.failed : PillState.idle);

    Widget card(double glow) => Panel(
          color: sounding ? c.red.withValues(alpha: 0.08 + 0.08 * glow) : null,
          border: sounding ? c.red.withValues(alpha: 0.5 + 0.5 * glow) : (armed ? c.green.withValues(alpha: 0.6) : null),
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _swapIcon(sounding ? Ic.sirenOn : (armed ? Ic.shieldOn : Ic.shield), 30, accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Eyebrow('Seguridad', color: sounding ? c.red : null),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(title, key: ValueKey(title), style: T.heading.copyWith(color: sounding ? c.red : c.text)),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            Text(description, style: T.small.copyWith(color: warn ? c.amber : c.text2)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: PillButton(
                  sounding ? 'Apagar alarma' : (armed ? 'Desarmar' : 'Armar'),
                  kind: sounding ? PillKind.dangerFilled : (armed ? PillKind.secondary : PillKind.primary),
                  expand: true,
                  state: stateOf(CasaPins.armed),
                  onTap: s.connected ? () => _send(CasaPins.armed, armed || sounding ? 0 : 1) : null,
                ),
              ),
              if (!sounding) ...[
                const SizedBox(width: 10),
                PillButton('Sirena',
                    icon: Ic.siren, kind: PillKind.danger, state: stateOf(CasaPins.siren), onTap: s.connected ? () => _send(CasaPins.siren, 1) : null),
              ],
            ]),
          ]),
        );

    if (!sounding) return card(0);
    return AnimatedBuilder(animation: _pulse, builder: (_, _) => card(_pulse.value));
  }
}

/// El aviso de la placa sin repetir el título: «Alarma sonando: entrada abierta» → «Entrada abierta».
String? _cause(String? notice, bool sounding) {
  if (notice == null || !sounding) return notice;
  if (!RegExp(r'^alarma', caseSensitive: false).hasMatch(notice.trim())) return null; // un aviso viejo, no la causa
  final rest = notice.replaceFirst(RegExp(r'^alarma sonando[:.,\s-]*', caseSensitive: false), '').trim();
  if (rest.isEmpty) return null;
  return rest[0].toUpperCase() + rest.substring(1);
}

/// Una habitación que se abre y se cierra. Cerrada, ya deja prender luces y abrir puertas con un toque.
class RoomCard extends StatelessWidget {
  final Session session;
  final String room;
  final bool expanded;
  final VoidCallback onToggle;
  final bool showPins;
  const RoomCard({super.key, required this.session, required this.room, required this.expanded, required this.onToggle, required this.showPins});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final controls = casaControls.where((x) => x.room == room).toList();
    final quick = controls.where((x) => x.kind != ControlKind.blind).toList();
    final blinds = controls.where((x) => x.kind == ControlKind.blind).toList();
    final anyOn = controls.any((x) => isOn(session, x));

    return Panel(
      padding: EdgeInsets.zero,
      border: anyOn ? c.line2 : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: room,
          child: Tap(
            onTap: onToggle,
            scale: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Icon(Ic.room(room), size: 26, color: anyOn ? c.text : c.text2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(room, style: T.heading.copyWith(fontSize: 17)),
                    if (_summary() case final summary?) ...[
                      const SizedBox(height: 3),
                      Text(summary, style: T.small.copyWith(color: c.text2)),
                    ],
                  ]),
                ),
                if (!expanded)
                  for (final x in quick) ...[const SizedBox(width: 8), _QuickToggle(session: session, spec: x)],
                const SizedBox(width: 10),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Ic.chevronDown, size: 18, color: c.text3),
                ),
              ]),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (quick.isNotEmpty)
                      LayoutBuilder(builder: (context, box) {
                        final half = (box.maxWidth - 10) / 2;
                        return Wrap(spacing: 10, runSpacing: 10, children: [
                          for (final (i, x) in quick.indexed)
                            // La última de un número impar ocupa todo el ancho, en una sola fila baja.
                            quick.length.isOdd && i == quick.length - 1
                                ? SizedBox(width: box.maxWidth, child: ControlTile(session: session, spec: x, showPins: showPins, wide: true))
                                : SizedBox(width: half, child: ControlTile(session: session, spec: x, showPins: showPins)),
                        ]);
                      }),
                    for (final b in blinds) ...[
                      if (quick.isNotEmpty || b != blinds.first) const SizedBox(height: 10),
                      BlindControl(session: session, spec: b, showPins: showPins),
                    ],
                  ]),
                ),
        ),
      ]),
    );
  }

  /// «Luz encendida · puerta abierta». Con todo apagado y cerrado no dice nada: solo se nombra lo que cambia.
  String? _summary() {
    final controls = casaControls.where((x) => x.room == room && x.isEnabledOn(session.device)).toList();
    final parts = <String>[];
    final lights = controls.where((x) => x.kind == ControlKind.light).toList();
    final lightsOn = lights.where((x) => isOn(session, x)).length;
    if (lightsOn > 0) parts.add(lights.length == 1 ? 'Luz encendida' : '$lightsOn de ${lights.length} luces');
    for (final d in controls.where((x) => x.kind == ControlKind.door && isOn(session, x))) {
      parts.add(d.isGarage ? 'Portón abierto' : '${d.label} abierta');
    }
    for (final b in controls.where((x) => x.kind == ControlKind.blind && isOn(session, x))) {
      parts.add('${b.label} ${blindPercent(session, b)} %');
    }
    if (parts.isEmpty) return controls.isEmpty ? 'Sin piezas conectadas' : null;
    return parts.join(' · ');
  }
}

/// Cómo se ve un control: encendido va relleno del color del texto (blanco en oscuro, negro en claro).
({Color bg, Color fg, Color border, Color? glow}) _look(Palette c, ControlKind k, {required bool on, required bool connected}) {
  if (on) return (bg: c.inverse, fg: c.onInverse, border: c.inverse, glow: k == ControlKind.light && c.isDark ? c.inverse.withValues(alpha: 0.28) : null);
  return (bg: c.surface2, fg: connected ? c.text2 : c.text3, border: c.line2, glow: null);
}

/// Botón redondo para prender o abrir sin desplegar la habitación.
class _QuickToggle extends StatelessWidget {
  final Session session;
  final ControlSpec spec;
  const _QuickToggle({required this.session, required this.spec});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (!spec.isEnabledOn(session.device)) return const SizedBox.shrink();
    final on = isOn(session, spec);
    final look = _look(c, spec.kind, on: on, connected: session.connected);
    final waiting = session.pending.contains(spec.vpin);
    final failed = session.unconfirmed.contains(spec.vpin);
    return Semantics(
      button: true,
      toggled: on,
      label: '${spec.label} de ${spec.room}',
      child: Tap(
        onTap: session.connected ? () => _toggle(session, spec) : null,
        onLongPress: () => _editPins(context, session, spec),
        scale: 0.88,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(alignment: Alignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: look.bg,
                border: Border.all(color: failed ? c.red : look.border),
                boxShadow: [BoxShadow(color: look.glow ?? Colors.transparent, blurRadius: 18)],
              ),
              child: Center(child: _swapIcon(controlIcon(spec, on: on), 20, look.fg)),
            ),
            if (waiting) SizedBox(width: 42, height: 42, child: CircularProgressIndicator(strokeWidth: 1.5, color: on ? c.text2 : c.text)),
          ]),
        ),
      ),
    );
  }
}

/// Tarjeta de una luz o una puerta dentro de la habitación desplegada. Toda la tarjeta es el interruptor:
/// encendida va rellena; en la esquina, un indicador solo mientras espera a la placa o si no respondió.
/// [wide]: en una sola fila, para cuando ocupa todo el ancho.
class ControlTile extends StatelessWidget {
  final Session session;
  final ControlSpec spec;
  final bool showPins;
  final bool wide;
  const ControlTile({super.key, required this.session, required this.spec, required this.showPins, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = spec.isEnabledOn(session.device);
    final on = isOn(session, spec);
    final usable = enabled && session.connected;
    final look = _look(c, spec.kind, on: on, connected: session.connected);
    final failed = session.unconfirmed.contains(spec.vpin);

    return Semantics(
      button: true,
      toggled: on,
      label: '${spec.label} de ${spec.room}',
      child: Tap(
        onTap: usable ? () => _toggle(session, spec) : null,
        onLongPress: () => _editPins(context, session, spec),
        scale: 0.95,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Panel(
            radius: R.tile,
            color: on ? look.bg : c.surface2,
            border: failed ? c.red : (on ? look.border : c.line),
            glow: look.glow,
            padding: wide ? const EdgeInsets.fromLTRB(14, 12, 14, 12) : const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: wide
                ? Row(children: [
                    _swapIcon(controlIcon(spec, on: on), 26, on ? look.fg : c.text2),
                    const SizedBox(width: 14),
                    Expanded(child: _words(c, look.fg, on: on, failed: failed)),
                    _confirmMark(session, spec.vpin, on ? look.fg : c.text, c),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      _swapIcon(controlIcon(spec, on: on), 26, on ? look.fg : c.text2),
                      const Spacer(),
                      _confirmMark(session, spec.vpin, on ? look.fg : c.text, c),
                    ]),
                    const SizedBox(height: 18),
                    _words(c, look.fg, on: on, failed: failed),
                  ]),
          ),
        ),
      ),
    );
  }
}

extension on ControlTile {
  /// Nombre, estado y (en el modo técnico) el pin.
  Widget _words(Palette c, Color fg, {required bool on, required bool failed}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(spec.label, style: T.callout.copyWith(color: on ? fg : c.text)),
        const SizedBox(height: 4),
        Eyebrow(stateWord(session, spec), color: failed ? c.red : (on ? fg.withValues(alpha: 0.7) : c.text3)),
        if (showPins) ...[
          const SizedBox(height: 6),
          Text(pinLabel(session.device, spec), style: T.small.copyWith(fontSize: 11.5, color: on ? fg.withValues(alpha: 0.6) : c.text3)),
        ],
      ]);
}

/// Persiana: deslizador de 0 a 100 % y atajos para cerrar, dejar a la mitad o abrir.
/// Mientras se arrastra, envía como mucho un mensaje cada 120 ms.
class BlindControl extends StatefulWidget {
  final Session session;
  final ControlSpec spec;
  final bool showPins;
  const BlindControl({super.key, required this.session, required this.spec, required this.showPins});

  @override
  State<BlindControl> createState() => _BlindControlState();
}

class _BlindControlState extends State<BlindControl> {
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
    _s.send(_spec.vpin, v.round(), confirm: true);
    setState(() => _dragging = null);
  }

  void _set(double fraction) => _s.send(_spec.vpin, (CasaPins.blindMax * fraction).round(), confirm: true);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = _spec.isEnabledOn(_s.device);
    final usable = enabled && _s.connected;
    final value = _dragging ?? (double.tryParse(_s.values[_spec.vpin] ?? '0') ?? 0);
    final percent = (value / CasaPins.blindMax * 100).round();
    final open = percent > 0;
    final failed = _s.unconfirmed.contains(_spec.vpin);

    return GestureDetector(
      onLongPress: () => _editPins(context, _s, _spec),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Panel(
          radius: R.tile,
          color: c.surface2,
          border: failed ? c.red : (open ? c.text.withValues(alpha: 0.55) : c.line),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              _swapIcon(controlIcon(_spec, on: open), 26, open ? c.text : c.text2),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_spec.label, style: T.callout),
                  const SizedBox(height: 3),
                  Eyebrow(stateWord(_s, _spec), color: failed ? c.red : (open ? c.text2 : c.text3)),
                  if (widget.showPins) ...[const SizedBox(height: 4), Text(pinLabel(_s.device, _spec), style: T.small.copyWith(fontSize: 11.5, color: c.text3))],
                ]),
              ),
              _confirmMark(_s, _spec.vpin, c.text, c),
              const SizedBox(width: 8),
              Text('$percent %', style: T.stat.copyWith(fontSize: 24, color: open ? c.text : c.text3)),
            ]),
            const SizedBox(height: 6),
            Semantics(
              label: 'Apertura de ${_spec.label} de ${_spec.room}',
              child: SizedBox(
                height: 36,
                child: Slider(
                  value: value.clamp(0, CasaPins.blindMax.toDouble()),
                  max: CasaPins.blindMax.toDouble(),
                  onChanged: usable ? _onChanged : null,
                  onChangeEnd: _onChangeEnd,
                ),
              ),
            ),
            Row(children: [
              Expanded(child: PillButton('Cerrar', small: true, kind: percent == 0 ? PillKind.primary : PillKind.secondary, expand: true, onTap: usable ? () => _set(0) : null)),
              const SizedBox(width: 8),
              Expanded(child: PillButton('50 %', small: true, kind: percent == 50 ? PillKind.primary : PillKind.secondary, expand: true, onTap: usable ? () => _set(0.5) : null)),
              const SizedBox(width: 8),
              Expanded(child: PillButton('Abrir', small: true, kind: percent == 100 ? PillKind.primary : PillKind.secondary, expand: true, onTap: usable ? () => _set(1) : null)),
            ]),
          ]),
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/link.dart';
import '../../core/protocol.dart';
import '../../main.dart';
import '../../models/controls.dart';
import '../../models/device.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'glass.dart';
import 'status.dart';

/// Estado de la conexión bajo el título grande, con «Reintentar» si se cayó.
class ConnectionSubtitle extends StatelessWidget {
  final Session session;
  const ConnectionSubtitle({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    final failed = st == LinkState.error && !session.retrying;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(child: ConnectionLine(state: st, transport: session.device.transport, retrying: session.retrying)),
        if (failed || st == LinkState.disconnected) ...[
          const SizedBox(width: 10),
          GestureDetector(
            onTap: session.connect,
            child: Text(failed ? 'Reintentar' : 'Conectar', style: T.footnote.copyWith(color: C.blue, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
      if (failed && session.error != null) ...[
        const SizedBox(height: 4),
        Text(session.error!, style: T.footnote.copyWith(color: C.red)),
      ],
    ]);
  }
}

/// Registro de los últimos mensajes enviados (→) y recibidos (←).
class MessageConsole extends StatelessWidget {
  final Session session;
  final int lines;
  const MessageConsole({super.key, required this.session, this.lines = 5});

  @override
  Widget build(BuildContext context) {
    final items = session.log.take(lines).toList();
    return Glass(
      color: const Color(0xE61C1C1E),
      radius: R.tile,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.terminal_rounded, size: 16, color: Color(0x99EBEBF5)),
          const SizedBox(width: 6),
          Text('Mensajes', style: T.footnote.copyWith(color: const Color(0x99EBEBF5), fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty) Text('Sin mensajes todavía', style: T.mono.copyWith(color: const Color(0x66EBEBF5))),
        for (final l in items)
          Text(
            '${l.incoming ? '←' : '→'} ${l.text}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.mono.copyWith(color: l.incoming ? const Color(0xFFFFD60A) : const Color(0xFF7CE0A3)),
          ),
      ]),
    );
  }
}

/// Abre la hoja para cambiar a qué GPIO va un control, si está invertido y si existe en la maqueta.
Future<void> showPinSheet(BuildContext context, Session session, ControlSpec spec) {
  final app = AppScope.read(context);
  return showGlassSheet<void>(context, (_) => _PinSheet(session: session, spec: spec, onSaved: app.saveChanges));
}

class _PinSheet extends StatefulWidget {
  final Session session;
  final ControlSpec spec;
  final Future<void> Function() onSaved;
  const _PinSheet({required this.session, required this.spec, required this.onSaved});

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  late final TextEditingController _gpio;
  late bool _inverted;
  late bool _enabled;
  String? _error;

  ControlSpec get _spec => widget.spec;
  Session get _session => widget.session;

  @override
  void initState() {
    super.initState();
    final current = _spec.pinsFor(_session.device);
    _gpio = TextEditingController(text: '${current.gpio}');
    _inverted = current.inverted;
    _enabled = current.enabled;
  }

  @override
  void dispose() {
    _gpio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final g = int.tryParse(_gpio.text.trim());
    final problem = g == null ? 'Escribe un número.' : gpioProblem(g);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await _apply(PinConfig(g!, inverted: _inverted, enabled: _enabled), custom: true);
  }

  Future<void> _reset() async {
    await _apply(PinConfig(_spec.gpio, inverted: _spec.inverted, enabled: _spec.enabled), custom: false);
  }

  /// Guarda el ajuste en la app, lo envía a la placa y cierra la hoja.
  Future<void> _apply(PinConfig p, {required bool custom}) async {
    final pins = _session.device.pins;
    custom ? pins[_spec.vpin] = p : pins.remove(_spec.vpin);
    await widget.onSaved();
    _session.sendRaw(cfgMsg(_spec.vpin, p.gpio, inverted: p.inverted, enabled: p.enabled));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final connected = _session.connected;
    final custom = _session.device.pins.containsKey(_spec.vpin);
    final isLight = _spec.kind == ControlKind.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_spec.room} · ${_spec.label}', style: T.title2),
            const SizedBox(height: 2),
            Text('Pin virtual V${_spec.vpin}  ·  de fábrica en el GPIO ${_spec.gpio}', style: T.footnote),
          ]),
        ),
        const SizedBox(height: 18),
        GlassGroup(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Expanded(child: Text('GPIO del ESP32', style: T.body)),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _gpio,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  style: T.body.copyWith(color: C.blue, fontWeight: FontWeight.w600),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
            ]),
          ),
          _SwitchRow(label: 'Invertir', value: _inverted, onChanged: (v) => setState(() => _inverted = v)),
          _SwitchRow(label: 'Conectado en la maqueta', value: _enabled, onChanged: (v) => setState(() => _enabled = v)),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            _error ??
                (isLight
                    ? 'Invertir: si al encender se apaga, y al revés. Pasa con la mayoría de los módulos de relé.'
                    : 'Invertir: si el servo gira hacia el lado contrario, por cómo quedó montado.'),
            style: T.footnote.copyWith(color: _error == null ? C.label2 : C.red),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: _save, child: Text(connected ? 'Guardar y enviar a la placa' : 'Guardar')),
        if (custom) TextButton(onPressed: _reset, child: Text('Volver al GPIO ${_spec.gpio}')),
        if (!connected)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('La placa no está conectada. El ajuste se guarda y se envía solo al conectar.',
                style: T.footnote, textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(children: [
        Expanded(child: Text(label, style: T.body)),
        CupertinoSwitch(value: value, activeTrackColor: C.green, onChanged: onChanged),
      ]),
    );
  }
}

/// «V10 · GPIO 2»: pin virtual y físico de un control, para el modo técnico.
String pinLabel(SavedDevice d, ControlSpec s) {
  final p = s.pinsFor(d);
  if (!p.enabled) return 'V${s.vpin} · sin conectar';
  return 'V${s.vpin} · GPIO ${p.gpio}${p.inverted ? ' · inv' : ''}';
}

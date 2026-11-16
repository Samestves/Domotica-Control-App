import 'package:flutter/material.dart';

import '../../core/link.dart';
import '../../main.dart';
import '../../models/controls.dart';
import '../../models/device.dart';
import '../../core/protocol.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'status.dart';

/// Barra con el estado de la conexión y un botón para reconectar.
class ConnectionBar extends StatelessWidget {
  final Session session;
  const ConnectionBar({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    final err = st == LinkState.error ? session.error : null;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      child: Row(children: [
        StatusDot(st),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(session.retrying ? 'Reconectando…' : stateLabel(st), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(err ?? session.device.subtitle, style: TextStyle(fontSize: 12, color: err != null ? C.danger : C.ink2)),
          ]),
        ),
        if (st != LinkState.connected)
          TextButton(onPressed: st == LinkState.connecting ? null : session.connect, child: const Text('Conectar')),
      ]),
    );
  }
}

/// Consola con los últimos mensajes enviados (→) y recibidos (←).
class MessageConsole extends StatelessWidget {
  final Session session;
  final int lines;
  const MessageConsole({super.key, required this.session, this.lines = 6});

  @override
  Widget build(BuildContext context) {
    final items = session.log.take(lines).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('MENSAJES', style: TextStyle(color: Color(0xFF6B7F95), fontSize: 10, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        if (items.isEmpty) const Text('Sin mensajes todavía', style: TextStyle(color: Color(0xFF6B7F95), fontSize: 12, fontFamily: 'monospace')),
        for (final l in items)
          Text(
            '${l.incoming ? '←' : '→'} ${l.text}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: l.incoming ? const Color(0xFFFFD07A) : const Color(0xFF9FE6B8)),
          ),
      ]),
    );
  }
}

/// Abre la hoja para cambiar a qué GPIO va un control y si está invertido.
Future<void> showPinSheet(BuildContext context, Session session, ControlSpec spec) {
  final app = AppScope.read(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: C.bg,
    builder: (_) => _PinSheet(session: session, spec: spec, onSaved: app.saveChanges),
  );
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${_spec.room} · ${_spec.label}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text('Pin virtual V${_spec.vpin} · por defecto GPIO ${_spec.gpio}', style: const TextStyle(color: C.ink2)),
        const SizedBox(height: 16),
        TextField(
          controller: _gpio,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: 'GPIO del ESP32',
            helperText: 'El número del pin donde está conectado el cable',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Invertir'),
            subtitle: Text(_spec.kind == ControlKind.light
                ? 'Actívalo si al encender se apaga, y al revés. Pasa con la mayoría de los módulos de relé.'
                : 'Actívalo si el servo gira hacia el lado contrario, por cómo quedó montado.'),
            value: _inverted,
            onChanged: (v) => setState(() => _inverted = v),
          ),
        ),
        const SizedBox(height: 8),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Conectado en la maqueta'),
            subtitle: const Text('Apágalo si esta pieza no existe en la maqueta.'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: _save, child: Text(connected ? 'Guardar y enviar a la placa' : 'Guardar')),
        if (custom) TextButton(onPressed: _reset, child: Text('Volver al GPIO ${_spec.gpio}')),
        if (!connected)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('La placa no está conectada. El ajuste se guarda y se envía solo al conectar.',
                style: TextStyle(color: C.ink2, fontSize: 12.5)),
          ),
      ]),
    );
  }
}

String pinLabel(SavedDevice d, ControlSpec s) {
  final p = s.pinsFor(d);
  if (!p.enabled) return 'V${s.vpin} · sin conectar';
  return 'V${s.vpin} · GPIO ${p.gpio}${p.inverted ? ' · inv' : ''}';
}

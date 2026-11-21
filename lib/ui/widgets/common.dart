import 'package:flutter/material.dart';

import '../../core/protocol.dart';
import '../../main.dart';
import '../../models/controls.dart';
import '../../models/device.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// Registro de los últimos mensajes enviados (→) y recibidos (←), en letra de máquina.
class MessageConsole extends StatelessWidget {
  final Session session;
  final int lines;
  const MessageConsole({super.key, required this.session, this.lines = 6});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = session.log.take(lines).toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (items.isEmpty) Text('Sin mensajes todavía', style: T.mono.copyWith(color: c.text3)),
        for (final l in items)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: l.incoming ? '← ' : '→ ', style: TextStyle(color: l.incoming ? c.amber : c.green)),
              TextSpan(text: l.text, style: TextStyle(color: l.incoming ? c.text : c.text2)),
            ]),
            maxLines: 3,
            style: T.mono,
          ),
      ]),
    );
  }
}

/// Abre la hoja para cambiar a qué pin va un control (GPIO, o canal del PCA9685 en puertas y persianas),
/// si está invertido y si existe en la maqueta.
Future<void> showPinSheet(BuildContext context, Session session, ControlSpec spec) {
  final app = AppScope.read(context);
  return showAppSheet<void>(context, (_) => _PinSheet(session: session, spec: spec, onSaved: app.saveChanges));
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
  bool get _pca => _spec.onPca;

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
    final problem = g == null ? 'Escribe un número.' : (_pca ? channelProblem(g) : gpioProblem(g));
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    await _apply(PinConfig(g!, inverted: _inverted, enabled: _enabled, pca: _pca), custom: true);
  }

  Future<void> _reset() async {
    await _apply(PinConfig(_spec.gpio, inverted: _spec.inverted, enabled: _spec.enabled, pca: _pca), custom: false);
  }

  /// Guarda el ajuste en la app, lo envía a la placa y cierra la hoja.
  Future<void> _apply(PinConfig p, {required bool custom}) async {
    final pins = _session.device.pins;
    custom ? pins[_spec.vpin] = p : pins.remove(_spec.vpin);
    await widget.onSaved();
    _session.sendRaw(cfgMsg(_spec.vpin, p.code, inverted: p.inverted, enabled: p.enabled));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final connected = _session.connected;
    final custom = _session.device.pins.containsKey(_spec.vpin);
    final isLight = _spec.kind == ControlKind.light;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SheetHeader(
            eyebrow: '${_spec.room} · pin virtual V${_spec.vpin}',
            title: _spec.label,
            detail: _pca ? 'De fábrica va en el canal ${_spec.gpio} del módulo PCA9685.' : 'De fábrica va en el GPIO ${_spec.gpio}.',
          ),
        ),
        const SizedBox(height: 20),
        RowGroup(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Text(_pca ? 'Canal del PCA9685' : 'GPIO del ESP32', style: T.body)),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _gpio,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  style: T.heading.copyWith(color: c.text),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
            ]),
          ),
          ListRow(title: 'Invertir', trailing: Toggle(value: _inverted, onChanged: (v) => setState(() => _inverted = v))),
          ListRow(title: 'Conectado en la maqueta', trailing: Toggle(value: _enabled, onChanged: (v) => setState(() => _enabled = v))),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Text(
            _error ??
                (isLight
                    ? 'Invertir: si al encender se apaga, y al revés. Pasa con la mayoría de los módulos de relé.'
                    : 'Invertir: si el servo gira hacia el lado contrario, por cómo quedó montado.'),
            style: T.small.copyWith(color: _error == null ? c.text2 : c.red),
          ),
        ),
        const SizedBox(height: 20),
        PillButton(connected ? 'Guardar y enviar' : 'Guardar', expand: true, onTap: _save),
        if (custom) ...[
          const SizedBox(height: 10),
          PillButton(_pca ? 'Volver al canal ${_spec.gpio}' : 'Volver al GPIO ${_spec.gpio}', kind: PillKind.secondary, expand: true, onTap: _reset),
        ],
        if (!connected)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('La placa no está conectada. El ajuste se guarda y se envía solo al conectar.',
                style: T.small.copyWith(color: c.text2), textAlign: TextAlign.center),
          ),
      ]),
    );
  }
}

/// «V10 · GPIO 2» o «V4 · canal 4»: pin virtual y físico de un control, para el modo técnico.
String pinLabel(SavedDevice d, ControlSpec s) {
  final p = s.pinsFor(d);
  if (!p.enabled) return 'V${s.vpin} · sin conectar';
  return 'V${s.vpin} · ${p.pca ? 'canal' : 'GPIO'} ${p.gpio}${p.inverted ? ' · inv' : ''}';
}

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
            Text(stateLabel(st), style: const TextStyle(fontWeight: FontWeight.w600)),
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

/// Hoja para cambiar a qué GPIO va un control y si está invertido.
Future<void> showPinSheet(BuildContext context, Session session, ControlSpec spec) async {
  final d = session.device;
  final current = d.pins[spec.vpin] ?? PinConfig(spec.gpio ?? 0, false);
  final gpio = TextEditingController(text: '${current.gpio}');
  var inverted = current.inverted;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: C.bg,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(spec.label, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          Text('Pin virtual V${spec.vpin}', style: const TextStyle(color: C.ink2)),
          const SizedBox(height: 16),
          TextField(
            controller: gpio,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'GPIO del ESP32', helperText: 'El número del pin donde está conectado el cable'),
          ),
          const SizedBox(height: 12),
          Panel(
            padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Invertir'),
              subtitle: const Text('Actívalo si al encender se apaga, y al revés. Pasa con la mayoría de los módulos de relé.'),
              value: inverted,
              onChanged: (v) => setS(() => inverted = v),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final g = int.tryParse(gpio.text.trim());
              if (g == null || g < 0 || g > 39) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Escribe un GPIO entre 0 y 39.')));
                return;
              }
              d.pins[spec.vpin] = PinConfig(g, inverted);
              await AppScope.read(context).update(d);
              session.sendRaw(cfgMsg(spec.vpin, g, inverted));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(session.connected ? 'Guardar y enviar a la placa' : 'Guardar'),
          ),
          if (!session.connected)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('La placa no está conectada: el ajuste se guarda en la app. Vuelve a guardarlo cuando esté conectada.', style: TextStyle(color: C.ink2, fontSize: 12.5)),
            ),
        ]),
      ),
    ),
  );
  gpio.dispose();
}

String pinLabel(SavedDevice d, ControlSpec s) {
  final p = d.pins[s.vpin];
  final g = p?.gpio ?? s.gpio;
  if (g == null) return 'V${s.vpin}';
  return 'V${s.vpin} · GPIO $g${(p?.inverted ?? false) ? ' · inv' : ''}';
}

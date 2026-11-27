import 'package:flutter/material.dart';

import '../../core/link.dart';
import '../../models/device.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// En qué está la conexión de una placa, tal como se le muestra al usuario.
enum Conn { connected, needsClave, connecting, reconnecting, failed, off }

Conn connOf(Session s) {
  if (s.needsClave) return Conn.needsClave;
  if (s.connected) return Conn.connected;
  if (s.reconnecting) return Conn.reconnecting;
  if (s.state == LinkState.connecting) return Conn.connecting;
  if (s.state == LinkState.error) return Conn.failed;
  return Conn.off;
}

Color connColor(Palette c, Conn k) => switch (k) {
      Conn.connected => c.green,
      Conn.needsClave || Conn.connecting || Conn.reconnecting => c.amber,
      Conn.failed => c.red,
      Conn.off => c.text3,
    };

String connLabel(Conn k) => switch (k) {
      Conn.connected => 'Conectado',
      Conn.needsClave => 'Falta la clave',
      Conn.connecting => 'Conectando…',
      Conn.reconnecting => 'Reconectando…',
      Conn.failed => 'Sin conexión',
      Conn.off => 'Desconectado',
    };

IconData profileIcon(Profile p) => switch (p) {
      Profile.casa => Ic.house,
      Profile.carro => Ic.car,
    };

IconData transportIcon(Transport t) => switch (t) {
      Transport.ble => Ic.bluetooth,
      Transport.wifi => Ic.wifi,
      Transport.demo => Ic.demo,
    };

/// Un estado en una pastilla suave: lo dice el texto, el color solo acompaña. Mientras algo está en marcha
/// (conectando), un círculo pequeño gira a su lado.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool busy;
  const StatusPill({super.key, required this.label, required this.color, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.fromLTRB(busy ? 8 : 11, 5, 11, 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (busy) ...[
          SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: color)),
          const SizedBox(width: 7),
        ],
        Flexible(
          child: Text(label, style: T.small.copyWith(color: color, fontWeight: FontWeight.w700, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// El estado de la conexión de una placa, en su pastilla: «Conectado», «Conectando…», «Sin conexión».
class ConnectionTag extends StatelessWidget {
  final Session session;
  const ConnectionTag({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final k = connOf(session);
    return StatusPill(label: connLabel(k), color: connColor(context.c, k), busy: k == Conn.connecting || k == Conn.reconnecting);
  }
}

/// Una línea que explica el estado cuando hace falta: el error, o en qué intento va.
String? connDetail(Session s) => switch (connOf(s)) {
      Conn.reconnecting => 'Intento ${s.attempt} de ${s.maxAttempts}',
      Conn.failed => s.error,
      Conn.needsClave => s.claveMessage,
      _ => null,
    };

/// El botón que corresponde al estado mientras no está conectada: Conectar, Cancelar o Reintentar (nunca se queda
/// atrapada «conectando»). Conectada no hace falta uno: «Desconectar» es lo que menos se usa y vive en el menú «⋯».
class ConnectionAction extends StatelessWidget {
  final Session session;
  final bool small;
  const ConnectionAction({super.key, required this.session, this.small = true});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return switch (connOf(s)) {
      Conn.connected || Conn.needsClave => const SizedBox.shrink(),
      Conn.connecting || Conn.reconnecting => PillButton('Cancelar', kind: PillKind.secondary, small: small, onTap: s.disconnect),
      Conn.failed => PillButton('Reintentar', small: small, onTap: s.connect),
      Conn.off => PillButton('Conectar', small: small, onTap: s.connect),
    };
  }
}

/// Conectar o desconectar, según el estado: para los menús «⋯».
(IconData, String) connectionMenuItem(Session s) => s.linked || s.busy
    ? (Ic.unlink, s.linked ? 'Desconectar' : 'Cancelar la conexión')
    : (Ic.link, 'Conectar');

void toggleConnection(Session s) => s.linked || s.busy ? s.disconnect() : s.connect();

/// Estado y botón juntos, con la explicación debajo. Va bajo el título de cada panel.
class ConnectionBar extends StatelessWidget {
  final Session session;
  const ConnectionBar({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final detail = connDetail(session);
    final k = connOf(session);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          ConnectionTag(session: session),
          if (detail != null) ...[
            const SizedBox(height: 5),
            Text(detail, style: T.small.copyWith(color: k == Conn.failed ? context.c.red : context.c.text2), maxLines: 3),
          ],
        ]),
      ),
      const SizedBox(width: 12),
      ConnectionAction(session: session),
    ]);
  }
}

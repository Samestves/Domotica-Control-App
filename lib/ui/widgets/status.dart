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
      Conn.connecting => 'Conectando',
      Conn.reconnecting => 'Reconectando',
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

/// «● CONECTADO»: el estado en mayúsculas con su punto de color.
class ConnectionTag extends StatelessWidget {
  final Session session;
  const ConnectionTag({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final k = connOf(session);
    final color = connColor(context.c, k);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StatusDot(color: color, pulse: k == Conn.connecting || k == Conn.reconnecting),
      const SizedBox(width: 9),
      Flexible(child: Eyebrow(connLabel(k), color: color)),
    ]);
  }
}

/// Una línea que explica el estado cuando hace falta: el error, o en qué intento va.
String? connDetail(Session s) => switch (connOf(s)) {
      Conn.reconnecting => 'Intento ${s.attempt} de ${s.maxAttempts}',
      Conn.failed => s.error,
      Conn.needsClave => s.claveMessage,
      _ => null,
    };

/// El botón que corresponde al estado: siempre hay uno, para no quedar atrapado «conectando».
class ConnectionAction extends StatelessWidget {
  final Session session;
  final bool small;
  const ConnectionAction({super.key, required this.session, this.small = true});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return switch (connOf(s)) {
      Conn.connected || Conn.needsClave => PillButton('Desconectar', kind: PillKind.secondary, small: small, onTap: s.disconnect),
      Conn.connecting || Conn.reconnecting => PillButton('Cancelar', kind: PillKind.secondary, small: small, onTap: s.disconnect),
      Conn.failed => PillButton('Reintentar', small: small, onTap: s.connect),
      Conn.off => PillButton('Conectar', small: small, onTap: s.connect),
    };
  }
}

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

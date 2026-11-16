import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/link.dart';
import '../main.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../version.dart';
import 'add_device_screen.dart';
import 'carro_panel.dart';
import 'casa_panel.dart';
import 'theme.dart';
import 'widgets/glass.dart';
import 'widgets/large_title_scaffold.dart';
import 'widgets/status.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static Future<void> open(BuildContext context, SavedDevice d) async {
    final s = AppScope.read(context).session(d);
    if (!s.connected) s.connect();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => d.profile == Profile.casa ? CasaPanel(device: d) : CarroPanel(device: d),
    ));
  }

  static void _add(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddDeviceScreen()));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final alerts = app.devices.map(app.session).where((s) => s.lastAlert != null).toList();
    final connected = app.connectedCount;

    return LargeTitleScaffold(
      title: 'Dispositivos',
      subtitle: Row(children: [
        StatusDot(connected > 0 ? LinkState.connected : LinkState.disconnected, size: 7),
        const SizedBox(width: 8),
        Text(
          connected == 0 ? 'Ninguno conectado' : '$connected de ${app.devices.length} conectados',
          style: T.subhead.copyWith(color: C.label2),
        ),
      ]),
      actions: [GlassIconButton(icon: Icons.add_rounded, tooltip: 'Agregar dispositivo', onTap: () => _add(context))],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          sliver: SliverList.list(children: [
            for (final s in alerts) ...[_AlertBanner(session: s), const SizedBox(height: 12)],
            if (app.devices.isEmpty) const _EmptyState(),
            for (final d in app.devices) ...[_DeviceCard(device: d), const SizedBox(height: 12)],
            _AddRow(onTap: () => _add(context)),
            const SizedBox(height: 28),
            const Center(child: _VersionBadge()),
          ]),
        ),
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final SavedDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session(device);
    return Pressable(
      onTap: () => HomeScreen.open(context, device),
      onLongPress: () => _showDeviceOptions(context, s),
      child: Glass(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Row(children: [
          ProfileBadge(device.profile),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name, style: T.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(transportIcon(device.transport), size: 14, color: C.label2)),
                  TextSpan(text: device.transport == Transport.demo ? ' Placa simulada' : ' ${device.board} · ${device.transport.label}'),
                ]),
                style: T.footnote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              _StateLine(session: s),
            ]),
          ),
          _ConnectButton(session: s),
        ]),
      ),
    );
  }
}

/// Estado de la conexión con su punto de color.
class _StateLine extends StatelessWidget {
  final Session session;
  const _StateLine({required this.session});

  @override
  Widget build(BuildContext context) {
    final st = session.retrying ? LinkState.connecting : session.state;
    return Row(children: [
      StatusDot(st, size: 7),
      const SizedBox(width: 7),
      Text(session.retrying ? 'Reconectando…' : stateLabel(st), style: T.footnote.copyWith(color: stateColor(st), fontWeight: FontWeight.w600)),
    ]);
  }
}

/// «Conectar» cuando está desconectada; una flecha cuando ya está lista para abrir.
class _ConnectButton extends StatelessWidget {
  final Session session;
  const _ConnectButton({required this.session});

  @override
  Widget build(BuildContext context) {
    if (session.connected) return const Icon(Icons.chevron_right_rounded, color: C.label3, size: 28);
    if (session.state == LinkState.connecting || session.retrying) {
      return const Padding(padding: EdgeInsets.all(8), child: CupertinoActivityIndicator());
    }
    return Pressable(
      onTap: session.connect,
      scale: 0.92,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: const ShapeDecoration(shape: StadiumBorder(), color: Color(0x1A007AFF)),
        child: Text('Conectar', style: T.subhead.copyWith(color: C.blue, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final Session session;
  const _AlertBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => HomeScreen.open(context, session.device),
      child: Glass(
        gradient: const LinearGradient(colors: [Color(0xFFFF5147), Color(0xFFE5243B)]),
        padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
        child: Row(children: [
          const Icon(Icons.notifications_active_rounded, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(session.lastAlert!, style: T.headline.copyWith(color: Colors.white))),
          IconButton(
            onPressed: session.clearAlert,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            tooltip: 'Descartar aviso',
          ),
        ]),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Glass(
        padding: const EdgeInsets.symmetric(vertical: 18),
        shadow: false,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.add_circle_rounded, color: C.blue, size: 22),
          const SizedBox(width: 8),
          Text('Agregar dispositivo', style: T.headline.copyWith(color: C.blue)),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        const Icon(Icons.sensors_rounded, size: 44, color: C.label3),
        const SizedBox(height: 12),
        const Text('Todavía no hay placas', style: T.title3),
        const SizedBox(height: 6),
        Text('Agrega tu ESP32 o Arduino para controlarlo desde aquí.', style: T.subhead.copyWith(color: C.label2), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// Versión de la app en una cápsula; al tocarla muestra «Acerca de».
class _VersionBadge extends StatelessWidget {
  const _VersionBadge();

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => showGlassSheet<void>(context, (_) => const _AboutSheet()),
      scale: 0.94,
      child: Glass(
        radius: 99,
        shadow: false,
        padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const AppGlyph(size: 22),
          const SizedBox(width: 8),
          Text('Control Domótica', style: T.footnote.copyWith(color: C.label, fontWeight: FontWeight.w600)),
          Text('  ·  $appVersion', style: T.footnote),
        ]),
      ),
    );
  }
}

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const AppGlyph(size: 76),
        const SizedBox(height: 14),
        const Text('Control Domótica', style: T.title2),
        const SizedBox(height: 4),
        Text('Versión $appVersion  ·  compilación $appBuild', style: T.footnote),
        const SizedBox(height: 22),
        const GlassGroup(children: [
          _AboutRow(icon: Icons.home_rounded, color: Color(0xFF16A37A), title: 'Casa domótica', detail: 'Luces, puertas, persianas y alarma de la maqueta'),
          _AboutRow(icon: Icons.directions_car_filled_rounded, color: C.blue, title: 'Auto Robot', detail: 'Conducción en horizontal, como un control remoto'),
          _AboutRow(icon: Icons.bluetooth_rounded, color: C.teal, title: 'Conexión', detail: 'Bluetooth LE o Wi‑Fi, varias placas a la vez'),
        ]),
        const SizedBox(height: 14),
        const Text('Mantén presionado un dispositivo para ver sus opciones.', style: T.footnote, textAlign: TextAlign.center),
      ]),
    );
  }
}

class _AboutRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, detail;
  const _AboutRow({required this.icon, required this.color, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: ShapeDecoration(shape: squircle(9), color: color),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: T.subhead.copyWith(fontWeight: FontWeight.w600)),
            Text(detail, style: T.footnote),
          ]),
        ),
      ]),
    );
  }
}

/// Opciones de un dispositivo: conectar o desconectar, y eliminar con confirmación.
void _showDeviceOptions(BuildContext context, Session s) {
  final d = s.device;
  showGlassSheet<void>(context, (sheet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ProfileBadge(d.profile, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.name, style: T.headline),
              Text('${d.profile.label} · ${d.subtitle}', style: T.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        GlassGroup(children: [
          _SheetAction(
            icon: s.connected ? Icons.link_off_rounded : Icons.link_rounded,
            label: s.connected ? 'Desconectar' : 'Conectar',
            onTap: () {
              Navigator.pop(sheet);
              s.connected ? s.disconnect() : s.connect();
            },
          ),
          _SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Eliminar dispositivo',
            color: C.red,
            onTap: () async {
              Navigator.pop(sheet);
              final ok = await _confirmDelete(context, d);
              if (ok && context.mounted) AppScope.read(context).remove(d);
            },
          ),
        ]),
      ]),
    );
  });
}

Future<bool> _confirmDelete(BuildContext context, SavedDevice d) async {
  final ok = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text('¿Eliminar «${d.name}»?'),
      content: const Text('Se borra de la app con sus ajustes de pines. La placa no cambia.'),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
      ],
    ),
  );
  return ok ?? false;
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, required this.onTap, this.color = C.blue});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Text(label, style: T.body.copyWith(color: color)),
        ]),
      ),
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final alerts = app.devices.map(app.session).where((s) => s.lastAlert != null).toList();

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dispositivos', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1)),
                    const SizedBox(height: 4),
                    Row(children: [
                      StatusDot(app.connectedCount > 0 ? LinkState.connected : LinkState.disconnected),
                      const SizedBox(width: 8),
                      Text('${app.connectedCount} de ${app.devices.length} conectados', style: const TextStyle(color: C.ink2)),
                    ]),
                  ],
                ),
              ),
            ),
            for (final s in alerts)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(child: _AlertBanner(session: s)),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverList.separated(
                itemCount: app.devices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _DeviceCard(device: app.devices[i]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverToBoxAdapter(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddDeviceScreen())),
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar dispositivo'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: C.accent,
                    side: const BorderSide(color: Color(0xFFC4CCD6), width: 1.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: 24),
              sliver: SliverToBoxAdapter(
                child: Text('$appVersion · Mantén presionado un dispositivo para eliminarlo',
                    textAlign: TextAlign.center, style: TextStyle(color: C.ink2, fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  final Session session;
  const _AlertBanner({required this.session});

  @override
  Widget build(BuildContext context) {
    return Panel(
      color: C.danger,
      onTap: () => HomeScreen.open(context, session.device),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Text(session.lastAlert!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
        IconButton(
          onPressed: session.clearAlert,
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: 'Descartar aviso',
        ),
      ]),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final SavedDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session(device);
    final st = s.state;
    final tint = device.profile == Profile.casa ? const Color(0xFFE5F7EC) : const Color(0xFFE7F0FF);
    final ic = device.profile == Profile.casa ? const Color(0xFF16893D) : const Color(0xFF0A5FD1);

    return Panel(
      onTap: () => HomeScreen.open(context, device),
      onLongPress: () => _options(context),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(14)),
          child: Icon(profileIcon(device.profile), color: ic),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(device.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(device.subtitle, style: const TextStyle(fontSize: 12.5, color: C.ink2), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              StatusDot(st, size: 7),
              const SizedBox(width: 7),
              Text(stateLabel(st), style: TextStyle(fontSize: 12, color: stateColor(st), fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          TransportChip(device.transport),
          const SizedBox(height: 6),
          IconButton(
            tooltip: s.connected ? 'Desconectar' : 'Conectar',
            onPressed: st == LinkState.connecting ? null : () => s.connected ? s.disconnect() : s.connect(),
            icon: Icon(s.connected ? Icons.link_off : Icons.link, color: C.accent),
          ),
        ]),
      ]),
    );
  }

  void _options(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: C.bg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(device.name, style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: Text('${device.profile.label} · ${device.subtitle}')),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: C.danger),
            title: const Text('Eliminar dispositivo', style: TextStyle(color: C.danger)),
            onTap: () {
              Navigator.pop(ctx);
              AppScope.read(context).remove(device);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

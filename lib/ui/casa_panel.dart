import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/casa_tiles.dart';
import 'widgets/common.dart';

/// Panel de la maqueta del grupo, ordenado por habitaciones.
class CasaPanel extends StatefulWidget {
  final SavedDevice device;
  const CasaPanel({super.key, required this.device});

  @override
  State<CasaPanel> createState() => _CasaPanelState();
}

class _CasaPanelState extends State<CasaPanel> {
  String? _shownAlert;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session(widget.device);
    _maybeAlert(s);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (k) {
              if (k == 'test') s.sendRaw('TEST');
              if (k == 'off') s.disconnect();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'test', child: Text('Probar salidas una por una')),
              PopupMenuItem(value: 'off', child: Text('Desconectar')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          ConnectionBar(session: s),
          const SizedBox(height: 12),
          SecurityCard(session: s),
          const SizedBox(height: 10),
          AllLightsCard(session: s),
          for (final room in casaRooms) _RoomSection(session: s, room: room),
          const SizedBox(height: 20),
          MessageConsole(session: s),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text('Mantén presionado un control para cambiar su pin, invertirlo o marcarlo como no conectado.',
                style: TextStyle(color: C.ink2, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  /// Vibra y suena una vez por cada alarma nueva.
  void _maybeAlert(Session s) {
    final a = s.lastAlert;
    if (a == null) {
      _shownAlert = null;
      return;
    }
    if (a == _shownAlert) return;
    _shownAlert = a;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    });
  }
}

class _RoomSection extends StatelessWidget {
  final Session session;
  final String room;
  const _RoomSection({required this.session, required this.room});

  @override
  Widget build(BuildContext context) {
    final controls = casaControls.where((c) => c.room == room);
    final squares = controls.where((c) => c.kind != ControlKind.blind).toList();
    final blinds = controls.where((c) => c.kind == ControlKind.blind);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(room, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -.4)),
      ),
      if (squares.isNotEmpty)
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            for (final c in squares)
              c.kind == ControlKind.light ? LightTile(session: session, spec: c) : DoorTile(session: session, spec: c),
          ],
        ),
      for (final c in blinds) ...[
        const SizedBox(height: 10),
        BlindTile(session: session, spec: c),
      ],
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../voice/voice_controller.dart';
import 'theme.dart';
import 'widgets/casa_tiles.dart';
import 'widgets/clave.dart';
import 'widgets/voice_bar.dart';
import 'widgets/common.dart';
import 'widgets/glass.dart';
import 'widgets/large_title_scaffold.dart';

/// Panel de la maqueta del grupo, ordenado por habitaciones.
class CasaPanel extends StatefulWidget {
  final SavedDevice device;

  /// Sesión a mostrar. Por defecto, la de la app para este dispositivo.
  final Session? session;

  const CasaPanel({super.key, required this.device, this.session});

  @override
  State<CasaPanel> createState() => _CasaPanelState();
}

class _CasaPanelState extends State<CasaPanel> {
  String? _shownAlert;
  final _voice = VoiceController();

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final s = widget.session ?? app.session(widget.device);
    final showPins = app.showPins;
    _maybeAlert(s);

    return LargeTitleScaffold(
      title: widget.device.name,
      subtitle: ConnectionSubtitle(session: s),
      actions: [_Menu(session: s, showPins: showPins, onShowPins: app.setShowPins)],
      bottomBar: showsClaveCard(s) ? null : VoiceBar(session: s, voice: _voice),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          sliver: SliverList.list(children: showsClaveCard(s) ? [ClaveCard(session: s)] : [
            SummaryStrip(session: s),
            const SizedBox(height: 14),
            SecurityCard(session: s),
            const SizedBox(height: 12),
            AllLightsRow(session: s),
            for (final room in casaRooms) _RoomSection(session: s, room: room, showPins: showPins),
            const SectionTitle('Mensajes', small: true),
            MessageConsole(session: s),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Text('Mantén presionado un control para cambiar su pin, invertirlo o marcarlo como no conectado.',
                  style: T.footnote, textAlign: TextAlign.center),
            ),
          ]),
        ),
      ],
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

class _Menu extends StatelessWidget {
  final Session session;
  final bool showPins;
  final ValueChanged<bool> onShowPins;
  const _Menu({required this.session, required this.showPins, required this.onShowPins});

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<String> item(String value, IconData icon, String label, {Color color = C.label}) => PopupMenuItem(
          value: value,
          child: Row(children: [
            Expanded(child: Text(label, style: T.body.copyWith(color: color))),
            Icon(icon, size: 20, color: color),
          ]),
        );

    return PopupMenuButton<String>(
      tooltip: 'Más opciones',
      offset: const Offset(0, 52),
      onSelected: (k) => switch (k) {
        'pins' => onShowPins(!showPins),
        'test' => session.sendRaw('TEST'),
        'sync' => session.sendRaw('SYNC'),
        'clave' => showChangeClaveSheet(context, session),
        'off' => session.disconnect(),
        'on' => session.connect(),
        _ => null,
      },
      itemBuilder: (_) => [
        item('pins', Icons.memory_rounded, showPins ? 'Ocultar pines' : 'Mostrar pines'),
        item('test', Icons.play_circle_outline_rounded, 'Probar salidas una por una'),
        item('sync', Icons.sync_rounded, 'Leer estado de la placa'),
        if (session.connected && session.keyed) item('clave', Icons.lock_rounded, 'Cambiar la clave'),
        const PopupMenuDivider(),
        session.linked
            ? item('off', Icons.link_off_rounded, 'Desconectar', color: C.red)
            : item('on', Icons.link_rounded, 'Conectar', color: C.blue),
      ],
      child: const IgnorePointer(child: GlassIconButton(icon: Icons.more_horiz_rounded, tooltip: 'Más opciones')),
    );
  }
}

class _RoomSection extends StatelessWidget {
  final Session session;
  final String room;
  final bool showPins;
  const _RoomSection({required this.session, required this.room, required this.showPins});

  @override
  Widget build(BuildContext context) {
    final controls = casaControls.where((c) => c.room == room).toList();
    final squares = controls.where((c) => c.kind != ControlKind.blind).toList();
    final blinds = controls.where((c) => c.kind == ControlKind.blind);
    final lightsOn = controls.where((c) => c.kind == ControlKind.light && session.values[c.vpin] == '1').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        room,
        trailing: lightsOn == 0 ? null : Capsule('$lightsOn encendida${lightsOn == 1 ? '' : 's'}', icon: Icons.lightbulb_rounded, color: const Color(0xFFE0A100)),
      ),
      if (squares.isNotEmpty)
        LayoutBuilder(builder: (context, box) {
          final half = (box.maxWidth - 10) / 2;
          // Si quedan en número impar, la última ocupa todo el ancho para que no quede un hueco.
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (i, c) in squares.indexed)
              SizedBox(
                width: squares.length.isOdd && i == squares.length - 1 ? box.maxWidth : half,
                child: AccessoryTile(session: session, spec: c, showPins: showPins),
              ),
          ]);
        }),
      for (final c in blinds) ...[
        const SizedBox(height: 10),
        BlindTile(session: session, spec: c, showPins: showPins),
      ],
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/pantalla.dart';
import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../voice/voice_controller.dart';
import 'theme.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/casa_tiles.dart';
import 'widgets/clave.dart';
import 'widgets/common.dart';
import 'widgets/kit.dart';
import 'widgets/status.dart';
import 'widgets/voice_bar.dart';

/// Panel de la maqueta: resumen, seguridad y las habitaciones, que se despliegan.
class CasaPanel extends StatefulWidget {
  final SavedDevice device;

  /// Sesión a mostrar. Por defecto, la de la app para este dispositivo.
  final Session? session;

  /// Habitaciones abiertas al entrar (para las capturas).
  final Set<String> initiallyOpen;

  const CasaPanel({super.key, required this.device, this.session, this.initiallyOpen = const {}});

  @override
  State<CasaPanel> createState() => _CasaPanelState();
}

class _CasaPanelState extends State<CasaPanel> {
  String? _shownAlert;
  final _voice = VoiceController();
  late final Set<String> _open = {...widget.initiallyOpen};

  @override
  void initState() {
    super.initState();
    // El micrófono se prepara al entrar, así la primera orden no espera.
    WidgetsBinding.instance.addPostFrameCallback((_) => _voice.warmUp());
    Pantalla.encendida(true);
  }

  @override
  void dispose() {
    Pantalla.encendida(false);
    _voice.dispose();
    super.dispose();
  }

  void _toggleRoom(String room) {
    HapticFeedback.selectionClick();
    setState(() => _open.contains(room) ? _open.remove(room) : _open.add(room));
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final s = widget.session ?? app.session(widget.device);
    final showPins = app.showPins;
    final rooms = casaRooms;
    final allOpen = _open.length == rooms.length;
    _maybeAlert(s);

    return AppScaffold(
      title: widget.device.name,
      subtitle: ConnectionBar(session: s),
      actions: [_Menu(session: s, showPins: showPins, onShowPins: app.setShowPins)],
      bottomBar: showsClaveCard(s) ? null : VoiceBar(session: s, voice: _voice),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
          sliver: SliverList.list(
            children: showsClaveCard(s)
                ? [ClaveCard(session: s)]
                : [
                    _Scenes(session: s, voice: _voice),
                    const SizedBox(height: 12),
                    Panel(padding: EdgeInsets.zero, child: AllLightsRow(session: s)),
                    const SizedBox(height: 12),
                    SecurityCard(session: s),
                    SectionHeader(
                      'Habitaciones',
                      trailing: Tap(
                        onTap: () => setState(() => allOpen ? _open.clear() : _open.addAll(rooms)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Eyebrow(allOpen ? 'Plegar todas' : 'Ver todas', color: c.text),
                        ),
                      ),
                    ),
                    for (final room in rooms) ...[
                      RoomCard(session: s, room: room, expanded: _open.contains(room), onToggle: () => _toggleRoom(room), showPins: showPins),
                      const SizedBox(height: 10),
                    ],
                    // Lo técnico (los mensajes con la placa y cómo cambiar pines) solo en el modo técnico: el panel queda
                    // para usar la casa.
                    if (showPins) ...[
                      const SectionHeader('Registro'),
                      MessageConsole(session: s),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text('Mantén presionado un control para cambiar su pin, invertirlo o marcarlo como no conectado.',
                            style: T.small.copyWith(color: c.text3), textAlign: TextAlign.center),
                      ),
                    ],
                  ],
          ),
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

/// Escenas: lo mismo que decir «buenas noches», «me voy» o «ya llegué», en un toque. Pasan por la voz, así que el
/// resultado se confirma igual (la barra de abajo dice si la casa lo hizo) y la lógica es una sola.
class _Scenes extends StatelessWidget {
  final Session session;
  final VoiceController voice;
  const _Scenes({required this.session, required this.voice});

  static const _all = [
    (Ic.night, 'Buenas noches', 'buenas noches'),
    (Ic.leave, 'Me voy', 'me voy'),
    (Ic.arrive, 'Ya llegué', 'ya llegué'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = session.connected;
    // Mismo alto para las tres aunque «Buenas noches» ocupe dos líneas en un teléfono angosto.
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, (icon, label, phrase)) in _all.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              enabled: on,
              label: 'Escena $label',
              excludeSemantics: true,
              child: Tap(
                onTap: on
                    ? () {
                        HapticFeedback.lightImpact();
                        voice.handle(session, phrase);
                      }
                    : null,
                child: Opacity(
                  opacity: on ? 1 : 0.38,
                  child: Panel(
                    padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(icon, size: 24, color: c.text),
                      const SizedBox(height: 10),
                      Text(label, style: T.callout, maxLines: 2),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _Menu extends StatelessWidget {
  final Session session;
  final bool showPins;
  final ValueChanged<bool> onShowPins;
  const _Menu({required this.session, required this.showPins, required this.onShowPins});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    PopupMenuItem<String> item(String value, IconData icon, String label, {bool enabled = true}) => PopupMenuItem(
          value: value,
          enabled: enabled,
          child: Row(children: [
            Icon(icon, size: 20, color: enabled ? c.text : c.text3),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: T.body.copyWith(color: enabled ? c.text : c.text3))),
          ]),
        );

    return PopupMenuButton<String>(
      tooltip: 'Más opciones',
      offset: const Offset(0, 50),
      onSelected: (k) => switch (k) {
        'conexion' => toggleConnection(session),
        'pins' => onShowPins(!showPins),
        'test' => session.sendRaw('TEST'),
        'sync' => session.sendRaw('SYNC'),
        'clave' => showChangeClaveSheet(context, session),
        _ => null,
      },
      itemBuilder: (_) {
        final (icon, label) = connectionMenuItem(session);
        return [
          item('conexion', icon, label),
          item('pins', Ic.pins, showPins ? 'Ocultar pines' : 'Mostrar pines'),
          item('test', Ic.play, 'Probar salidas una por una', enabled: session.connected),
          item('sync', Ic.sync, 'Leer estado de la placa', enabled: session.connected),
          if (session.connected && session.keyed) item('clave', Ic.lock, 'Cambiar la clave'),
        ];
      },
      child: const IgnorePointer(child: RoundButton(icon: Ic.more, tooltip: 'Más opciones', size: 40)),
    );
  }
}

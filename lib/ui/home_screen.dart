import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import '../version.dart';
import 'add_device_screen.dart';
import 'carro_panel.dart';
import 'casa_panel.dart';
import 'credits_screen.dart';
import 'theme.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/board_update_sheet.dart';
import 'widgets/clave.dart';
import 'widgets/kit.dart';
import 'widgets/news_sheet.dart';
import 'widgets/status.dart';
import 'widgets/update_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  /// true mientras se abre una pantalla: un doble toque no abre dos (dos paneles del carrito se pisarían la orientación).
  static bool _opening = false;

  static Future<void> _push(BuildContext context, Widget screen) async {
    if (_opening) return;
    _opening = true;
    try {
      final done = Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      await Future<void>.delayed(const Duration(milliseconds: 450)); // lo que dura la transición
      _opening = false;
      await done;
    } finally {
      _opening = false;
    }
  }

  static Future<void> open(BuildContext context, SavedDevice d) async {
    if (_opening) return;
    final s = AppScope.read(context).session(d);
    if (!s.linked && !s.busy) s.connect();
    await _push(context, d.profile == Profile.casa ? CasaPanel(device: d) : CarroPanel(device: d));
  }

  static void _add(BuildContext context) => _push(context, const AddDeviceScreen());

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Recién actualizada: cuenta una vez qué trae esta versión. Es también la prueba de que se actualizó.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = AppScope.read(context);
      if (!app.newsPending) return;
      app.markNewsSeen();
      showNewsSheet(context, justUpdated: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = context.c;
    final alerts = app.devices.map(app.session).where((s) => s.lastAlert != null).toList();
    final connected = app.connectedCount;

    return AppScaffold(
      brand: const Brand(),
      title: 'Dispositivos',
      subtitle: Row(children: [
        StatusDot(color: connected > 0 ? c.green : c.text3),
        const SizedBox(width: 9),
        Eyebrow(connected == 0 ? 'Ninguno conectado' : '$connected de ${app.devices.length} conectados', color: connected > 0 ? c.green : c.text2),
      ]),
      actions: [
        RoundButton(icon: Ic.settings, tooltip: 'Ajustes', size: 40, onTap: () => showSettingsSheet(context)),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
          sliver: SliverList.list(children: [
            for (final s in alerts) ...[_AlertBanner(session: s), const SizedBox(height: 12)],
            if (app.update != null) ...[UpdateBanner(release: app.update!), const SizedBox(height: 12)],
            for (final d in app.devices)
              if (app.boardUpdate(d) case final r?) ...[BoardUpdateBanner(device: d, release: r), const SizedBox(height: 12)],
            if (app.devices.isEmpty) _EmptyState(onAdd: () => HomeScreen._add(context)),
            for (final d in app.devices) ...[_DeviceCard(device: d), const SizedBox(height: 12)],
            if (app.devices.isNotEmpty) _AddCard(onTap: () => HomeScreen._add(context)),
            if (app.devices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text('Mantén presionada una tarjeta para ver sus opciones.',
                    style: T.small.copyWith(color: c.text3), textAlign: TextAlign.center),
              ),
          ]),
        ),
      ],
    );
  }
}

/// Tarjeta de una placa: qué es, cómo está y el botón para conectar, cancelar o desconectar.
class _DeviceCard extends StatelessWidget {
  final SavedDevice device;
  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session(device);
    final c = context.c;
    final k = connOf(s);
    final detail = connDetail(s) ?? (k == Conn.connected ? _summary(s) : null);

    return Tap(
      onTap: () => HomeScreen.open(context, device),
      onLongPress: () => _showDeviceOptions(context, s),
      child: Panel(
        padding: EdgeInsets.zero,
        border: k == Conn.connected ? c.line2 : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Arriba: qué es. Toda la tarjeta abre el panel; la flecha solo lo indica.
          Semantics(
            button: true,
            label: 'Abrir ${device.name}',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(profileIcon(device.profile), size: 16, color: c.text2),
                      const SizedBox(width: 8),
                      Flexible(child: Eyebrow(device.subtitle)),
                    ]),
                    const SizedBox(height: 8),
                    Text(device.name, style: T.title.copyWith(fontSize: 24)),
                  ]),
                ),
                const SizedBox(width: 12),
                Icon(Ic.chevronRight, size: 20, color: k == Conn.connected ? c.text : c.text3),
              ]),
            ),
          ),
          const Hairline(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ConnectionTag(session: s),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(detail, style: T.small.copyWith(color: k == Conn.failed ? c.red : c.text2)),
                  ],
                ]),
              ),
              const SizedBox(width: 10),
              ConnectionAction(session: s),
            ]),
          ),
          // Mientras conecta, una línea fina corre por debajo.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: s.busy ? ThinProgress(color: c.amber) : const SizedBox(height: 2),
          ),
        ]),
      ),
    );
  }

  /// «2 luces encendidas · 1 puerta abierta» para la casa conectada.
  static String? _summary(Session s) {
    if (s.device.profile != Profile.casa) return 'Listo para manejar';
    final v = s.values;
    final lights = casaControls.where((x) => x.kind == ControlKind.light && v[x.vpin] == '1').length;
    final doors = casaControls.where((x) => x.kind == ControlKind.door && v[x.vpin] == '1').length;
    final parts = [
      if (lights > 0) lights == 1 ? '1 luz encendida' : '$lights luces encendidas',
      if (doors > 0) '$doors puerta${doors == 1 ? '' : 's'} abierta${doors == 1 ? '' : 's'}',
      if (s.values[CasaPins.armed] == '1') 'alarma armada',
    ];
    return parts.isEmpty ? 'Todo apagado y cerrado' : parts.join(' · ');
  }
}

/// Al final de la lista: un lugar punteado para otra placa, en vez de un «+» suelto arriba que compite con Ajustes.
class _AddCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: 'Agregar dispositivo',
      excludeSemantics: true,
      child: Tap(
        onTap: onTap,
        child: DashedPanel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Ic.plus, size: 20, color: c.text2),
            const SizedBox(width: 10),
            Text('Agregar dispositivo', style: T.callout.copyWith(color: c.text2)),
          ]),
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
    final c = context.c;
    return Tap(
      onTap: () => HomeScreen.open(context, session.device),
      child: Panel(
        color: c.red.withValues(alpha: 0.12),
        border: c.red,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          Icon(Ic.sirenOn, color: c.red, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow('Alarma', color: c.red),
              const SizedBox(height: 2),
              Text(session.lastAlert!, style: T.callout),
            ]),
          ),
          IconButton(onPressed: session.clearAlert, icon: Icon(Ic.close, color: c.text2), tooltip: 'Descartar aviso'),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Icon(Ic.board, size: 44, color: c.text3),
        const SizedBox(height: 14),
        const Text('Todavía no hay placas', style: T.heading),
        const SizedBox(height: 6),
        Text('Agrega tu ESP32 o Arduino para controlarlo desde aquí.', style: T.small.copyWith(color: c.text2), textAlign: TextAlign.center),
        const SizedBox(height: 22),
        PillButton('Agregar dispositivo', icon: Ic.plus, onTap: onAdd),
      ]),
    );
  }
}

/// Ajustes de la app: apariencia y modo técnico.
Future<void> showSettingsSheet(BuildContext context) => showAppSheet<void>(context, (_) => const _SettingsSheet());

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: SheetHeader(title: 'Ajustes')),
        const SectionHeader('Apariencia', padding: EdgeInsets.fromLTRB(4, 24, 4, 10)),
        Segmented<ThemeMode>(
          value: app.themeMode,
          items: const {ThemeMode.system: 'Sistema', ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro'},
          icons: const {ThemeMode.system: Ic.system, ThemeMode.light: Ic.sun, ThemeMode.dark: Ic.moon},
          onChanged: app.setThemeMode,
        ),
        const SectionHeader('Modo técnico', padding: EdgeInsets.fromLTRB(4, 24, 4, 10)),
        RowGroup(
          footer: 'Muestra en cada control su pin virtual y el GPIO del ESP32, y el registro de mensajes con la placa.',
          children: [
            ListRow(
              icon: Ic.pins,
              title: 'Mostrar pines',
              trailing: Toggle(value: app.showPins, onChanged: app.setShowPins),
              onTap: () => app.setShowPins(!app.showPins),
            ),
          ],
        ),
        const SectionHeader('Avisos', padding: EdgeInsets.fromLTRB(4, 24, 4, 10)),
        RowGroup(
          footer: 'La app revisa cada 12 horas, aunque esté cerrada, si hay una versión nueva de la app o de tus placas, '
              'y avisa una vez por versión. En teléfonos Xiaomi, permite el «Inicio automático» de la app para que no se atrase.',
          children: [
            ListRow(
              icon: Ic.bell,
              title: 'Avisar versiones nuevas',
              trailing: Toggle(value: app.avisos, onChanged: app.setAvisos),
              onTap: () => app.setAvisos(!app.avisos),
            ),
          ],
        ),
        const SizedBox(height: 18),
        RowGroup(children: [
          ListRow(
            icon: Ic.download,
            title: 'Buscar actualización',
            detail: app.update == null ? 'Se revisa sola al abrir la app' : 'Hay una nueva: ${app.update!.title}',
            trailing: Icon(Ic.chevronRight, size: 18, color: context.c.text3),
            onTap: () {
              final found = app.update;
              Navigator.pop(context);
              showUpdateSheet(context, release: found);
            },
          ),
          ListRow(
            icon: Ic.info,
            title: 'Acerca de',
            detail: '$appVersion · compilación $appBuild',
            trailing: Icon(Ic.chevronRight, size: 18, color: context.c.text3),
            onTap: () {
              Navigator.pop(context);
              showAppSheet<void>(context, (_) => const _AboutSheet());
            },
          ),
        ]),
      ]),
    );
  }
}

class _AboutSheet extends StatefulWidget {
  const _AboutSheet();

  @override
  State<_AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<_AboutSheet> {
  // Guiño escondido: 3 toques seguidos al logo abren la firma de la app.
  int _taps = 0;
  DateTime _lastTap = DateTime(0);
  bool _bump = false;

  void _tapLogo() {
    final now = DateTime.now();
    _taps = now.difference(_lastTap) < const Duration(milliseconds: 700) ? _taps + 1 : 1;
    _lastTap = now;
    HapticFeedback.selectionClick();
    setState(() => _bump = true);
    Future.delayed(const Duration(milliseconds: 110), () {
      if (mounted) setState(() => _bump = false);
    });
    if (_taps >= 3) {
      _taps = 0;
      showCredits(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(children: [
        GestureDetector(
          key: const ValueKey('logo-acerca'),
          onTap: _tapLogo,
          child: AnimatedScale(
            scale: _bump ? 0.9 : 1,
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOut,
            child: const AppGlyph(size: 68),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Control Domótica', style: T.title),
        const SizedBox(height: 6),
        Eyebrow('Versión $appVersion · compilación $appBuild'),
        const SizedBox(height: 22),
        RowGroup(children: [
          ListRow(icon: Ic.house, title: 'Casa domótica', detail: 'Luces, puertas, persianas, alarma y voz'),
          ListRow(icon: Ic.car, title: 'Auto Robot', detail: 'Manejo en horizontal, como un control remoto'),
          ListRow(icon: Ic.bluetooth, title: 'Conexión', detail: 'Bluetooth LE o Wi-Fi, varias placas a la vez'),
        ]),
        const SizedBox(height: 14),
        RowGroup(children: [
          ListRow(
            icon: Ic.demo,
            title: 'Novedades',
            detail: 'Qué trae la $appVersion',
            trailing: Icon(Ic.chevronRight, size: 18, color: c.text3),
            onTap: () {
              Navigator.pop(context);
              showNewsSheet(context);
            },
          ),
        ]),
      ]),
    );
  }
}

/// Opciones de un dispositivo: conectar o desconectar, cambiar la clave y eliminar con confirmación.
void _showDeviceOptions(BuildContext context, Session s) {
  final d = s.device;
  showAppSheet<void>(context, (sheet) {
    final c = sheet.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SheetHeader(eyebrow: '${d.profile.label} · ${d.subtitle}', title: d.name),
        ),
        const SizedBox(height: 20),
        // Se redibuja si la conexión cambia con la hoja abierta (por ejemplo, se acaban los reintentos).
        ListenableBuilder(
          listenable: s,
          builder: (_, _) => RowGroup(children: [
            ListRow(
              icon: s.linked || s.busy ? Ic.unlink : Ic.link,
              title: s.linked ? 'Desconectar' : (s.busy ? 'Cancelar la conexión' : 'Conectar'),
              onTap: () {
                Navigator.pop(sheet);
                s.linked || s.busy ? s.disconnect() : s.connect();
              },
            ),
            // Qué programa tiene la placa (lo dice al conectarse desde casa-0.9 y carro-0.5) y si hay uno más nuevo.
            if (d.transport != Transport.demo) _firmwareRow(context, sheet, d),
            ListRow(
              icon: Ic.edit,
              title: 'Cambiar nombre',
              onTap: () {
                Navigator.pop(sheet);
                showAppSheet<void>(context, (_) => _RenameSheet(device: d));
              },
            ),
            // Solo un teléfono conectado que ya entró con la clave actual puede cambiarla. Si este teléfono tiene la
            // clave guardada, la fila se ve aunque esté desconectado, para que se sepa dónde está.
            if ((s.connected && s.keyed) || d.clave != null)
              ListRow(
                icon: Ic.lock,
                iconColor: s.connected && s.keyed ? null : c.text3,
                title: 'Cambiar la clave',
                titleColor: s.connected && s.keyed ? null : c.text3,
                detail: s.connected && s.keyed ? 'Los otros teléfonos tendrán que escribir la nueva' : 'Conéctate para cambiarla',
                onTap: s.connected && s.keyed
                    ? () {
                        Navigator.pop(sheet);
                        showChangeClaveSheet(context, s);
                      }
                    : null,
              ),
            ListRow(
              icon: Ic.trash,
              title: 'Eliminar dispositivo',
              titleColor: c.red,
              onTap: () async {
                Navigator.pop(sheet);
                final ok = await _confirmDelete(context, d);
                if (ok && context.mounted) AppScope.read(context).remove(d);
              },
            ),
          ]),
        ),
      ]),
    );
  });
}

Widget _firmwareRow(BuildContext context, BuildContext sheet, SavedDevice d) {
  final c = sheet.c;
  final update = AppScope.read(context).boardUpdate(d);
  return ListRow(
    icon: Ic.board,
    title: 'Programa de la placa',
    detail: switch ((d.firmware, update)) {
      (null, _) => 'Se ve al conectarse, desde casa-0.9 y carro-0.5',
      (final mine?, null) => '$mine · al día',
      (final mine?, final r?) => '$mine · hay ${r.version}',
    },
    trailing: update == null ? null : Eyebrow('Actualizar', color: c.green),
    onTap: update == null
        ? null
        : () {
            Navigator.pop(sheet);
            showBoardUpdateSheet(context, d);
          },
  );
}

/// Hoja para cambiar el nombre de un dispositivo.
class _RenameSheet extends StatefulWidget {
  final SavedDevice device;
  const _RenameSheet({required this.device});

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final _name = TextEditingController(text: widget.device.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.device.name = n;
    AppScope.read(context).saveChanges();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SheetHeader(eyebrow: widget.device.subtitle, title: 'Cambiar nombre'),
        ),
        const SizedBox(height: 20),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _name,
            autofocus: true,
            style: T.body,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(height: 20),
        PillButton('Guardar nombre', expand: true, onTap: _name.text.trim().isEmpty ? null : _save),
      ]),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context, SavedDevice d) async {
  final ok = await showAppSheet<bool>(context, (sheet) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetHeader(title: '¿Eliminar «${d.name}»?', detail: 'Se borra de la app con sus ajustes de pines. La placa no cambia.'),
        const SizedBox(height: 22),
        PillButton('Eliminar', kind: PillKind.dangerFilled, expand: true, onTap: () => Navigator.pop(sheet, true)),
        const SizedBox(height: 10),
        PillButton('Cancelar', kind: PillKind.secondary, expand: true, onTap: () => Navigator.pop(sheet, false)),
      ]),
    );
  });
  return ok ?? false;
}

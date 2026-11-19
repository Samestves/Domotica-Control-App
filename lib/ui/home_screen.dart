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
import 'widgets/kit.dart';
import 'widgets/status.dart';
import 'widgets/update_sheet.dart';

class HomeScreen extends StatelessWidget {
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
        RoundButton(icon: Ic.plus, tooltip: 'Agregar dispositivo', size: 40, onTap: () => _add(context)),
        RoundButton(icon: Ic.settings, tooltip: 'Ajustes', size: 40, onTap: () => showSettingsSheet(context)),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
          sliver: SliverList.list(children: [
            for (final s in alerts) ...[_AlertBanner(session: s), const SizedBox(height: 12)],
            if (app.update != null) ...[UpdateBanner(release: app.update!), const SizedBox(height: 12)],
            if (app.devices.isEmpty) _EmptyState(onAdd: () => _add(context)),
            for (final d in app.devices) ...[_DeviceCard(device: d), const SizedBox(height: 12)],
            const SizedBox(height: 28),
            Center(
              child: Tap(
                onTap: () => showAppSheet<void>(context, (_) => const _AboutSheet()),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Eyebrow('Control Domótica · $appVersion', color: c.text3),
                ),
              ),
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
          // Arriba: qué es y la flecha para entrar. Toda esta parte abre el panel.
          Semantics(
            button: true,
            label: 'Abrir ${device.name}',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(profileIcon(device.profile), size: 16, color: c.text2),
                      const SizedBox(width: 8),
                      Flexible(child: Eyebrow('${device.profile.label} · ${device.transport == Transport.demo ? 'Demo' : device.transport.label}')),
                    ]),
                    const SizedBox(height: 8),
                    Text(device.name, style: T.title.copyWith(fontSize: 24)),
                  ]),
                ),
                const SizedBox(width: 12),
                RoundButton(icon: Ic.chevronRight, tooltip: 'Abrir', size: 40, filled: k == Conn.connected, onTap: () => HomeScreen.open(context, device)),
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
        const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: SheetHeader(eyebrow: 'Control Domótica', title: 'Ajustes')),
        const SectionHeader('Apariencia', padding: EdgeInsets.fromLTRB(4, 24, 4, 10)),
        Segmented<ThemeMode>(
          value: app.themeMode,
          items: const {ThemeMode.system: 'Sistema', ThemeMode.light: 'Claro', ThemeMode.dark: 'Oscuro'},
          icons: const {ThemeMode.system: Ic.system, ThemeMode.light: Ic.sun, ThemeMode.dark: Ic.moon},
          onChanged: app.setThemeMode,
        ),
        const SectionHeader('Modo técnico', padding: EdgeInsets.fromLTRB(4, 24, 4, 10)),
        RowGroup(
          footer: 'Muestra en cada control su pin virtual y el GPIO del ESP32.',
          children: [
            ListRow(
              icon: Ic.pins,
              title: 'Mostrar pines',
              trailing: Toggle(value: app.showPins, onChanged: app.setShowPins),
              onTap: () => app.setShowPins(!app.showPins),
            ),
          ],
        ),
        const SizedBox(height: 18),
        RowGroup(children: [
          ListRow(
            icon: Ic.download,
            title: 'Buscar actualización',
            detail: app.update == null ? 'Tienes $appVersion' : 'Hay una nueva: ${app.update!.title}',
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
        Text('Mantén presionado un dispositivo para ver sus opciones.', style: T.small.copyWith(color: c.text2), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// Opciones de un dispositivo: conectar o desconectar, y eliminar con confirmación.
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

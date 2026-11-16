// ignore_for_file: invalid_use_of_visible_for_testing_member
// Dibuja las pantallas principales de la app en imágenes PNG, con la letra real.
// Sirve para revisar el diseño en la PC sin instalar nada en el teléfono.
//
//   flutter test capturas --update-goldens
//
// Las imágenes quedan en capturas/salida/.
import 'dart:io';

import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/ui/add_device_screen.dart';
import 'package:control_domotica/ui/carro_panel.dart';
import 'package:control_domotica/ui/casa_panel.dart';
import 'package:control_domotica/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tamaño de un teléfono típico en puntos lógicos, a 3x.
const _portrait = Size(393, 852);
const _landscape = Size(852, 393);

Future<void> _loadFonts() async {
  Future<ByteData> asset(String path) => rootBundle.load(path);
  Future<ByteData> file(String path) async => ByteData.sublistView(File(path).readAsBytesSync());

  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(asset('assets/fonts/Inter-$w.ttf'));
  }
  final display = FontLoader('InterDisplay')
    ..addFont(asset('assets/fonts/InterDisplay-SemiBold.ttf'))
    ..addFont(asset('assets/fonts/InterDisplay-Bold.ttf'));
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['USERPROFILE']}/develop/flutter';
  final icons = FontLoader('MaterialIcons')
    ..addFont(file('$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await Future.wait([inter.load(), display.load(), icons.load()]);
}

void _setSize(WidgetTester t, Size logical) {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = logical * 3;
  addTearDown(t.view.reset);
}

/// Una app con dos placas demo y una real guardadas, como la tendría el usuario.
Future<AppState> _state() async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState();
  await app.load();
  await app.add(SavedDevice(
    id: 'esp32',
    name: 'Casa Domotica',
    profile: Profile.casa,
    transport: Transport.ble,
    address: '3C:71:BF:19:A7:1A',
  ));
  return app;
}

Future<void> _shoot(WidgetTester t, AppState app, Widget screen, String name, {Size size = _portrait}) async {
  _setSize(t, size);
  await t.pumpWidget(ControlApp(state: app, home: screen));
  await t.pump(const Duration(seconds: 1));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('salida/$name.png'));
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('inicio', (t) async {
    final app = await _state();
    await t.runAsync(() async {
      await app.session(app.devices.first).connect();
    });
    await _shoot(t, app, const HomeScreen(), '01_inicio');
    await t.tap(find.text('Control Domótica'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('salida/07_acerca_de.png'));
    await t.runAsync(app.session(app.devices.first).disconnect);
  });

  testWidgets('agregar dispositivo', (t) async {
    final app = await _state();
    await _shoot(t, app, const AddDeviceScreen(), '02_agregar');
  });

  testWidgets('casa conectada', (t) async {
    final app = await _state();
    final casa = app.devices.firstWhere((d) => d.id == 'demo-casa');
    final s = app.session(casa);
    await t.runAsync(() async {
      await s.connect();
      s
        ..send(10, 1)
        ..send(12, 1)
        ..send(1, 1)
        ..send(5, 120);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _shoot(t, app, CasaPanel(device: casa), '03_casa');
    await t.drag(find.byType(Scrollable).first, const Offset(0, -900));
    await t.pump(const Duration(milliseconds: 500));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('salida/04_casa_abajo.png'));
    await t.longPress(find.text('Persiana 1'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('salida/08_hoja_pines.png'));
    await t.runAsync(s.disconnect);
  });

  testWidgets('casa con alarma', (t) async {
    final app = await _state();
    final casa = app.devices.firstWhere((d) => d.id == 'demo-casa');
    final s = Session(casa, linkFor: (_) => DemoLink('casa', casaGrace: const Duration(milliseconds: 50)));
    await t.runAsync(() async {
      await s.connect();
      s
        ..send(17, 1)
        ..send(0, 1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await _shoot(t, app, _SessionPanel(session: s), '05_casa_alarma');
    await t.runAsync(s.disconnect);
  });

  testWidgets('carro', (t) async {
    final app = await _state();
    final carro = app.devices.firstWhere((d) => d.id == 'demo-carro');
    await _shoot(t, app, CarroPanel(device: carro), '06_carro', size: _landscape);
  });
}

/// Muestra el panel de la casa con una sesión creada a mano (para simular la alarma rápido).
class _SessionPanel extends StatelessWidget {
  final Session session;
  const _SessionPanel({required this.session});

  @override
  Widget build(BuildContext context) => CasaPanel(device: session.device, session: session);
}

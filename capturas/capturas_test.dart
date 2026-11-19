// ignore_for_file: invalid_use_of_visible_for_testing_member
// Dibuja las pantallas principales de la app en imágenes PNG, con la letra y los iconos reales,
// en modo oscuro y en modo claro. Sirve para revisar el diseño en la PC sin instalar nada en el teléfono.
//
//   flutter test capturas --update-goldens
//
// Las imágenes quedan en capturas/salida/.
import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/models/pins.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/ui/add_device_screen.dart';
import 'package:control_domotica/ui/carro_panel.dart';
import 'package:control_domotica/ui/casa_panel.dart';
import 'package:control_domotica/ui/credits_screen.dart';
import 'package:control_domotica/ui/home_screen.dart';
import 'package:control_domotica/ui/widgets/news_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tamaño de un teléfono típico en puntos lógicos, a 3x.
const _portrait = Size(393, 852);
const _landscape = Size(852, 393);

const _themes = {'oscuro': ThemeMode.dark, 'claro': ThemeMode.light};

Future<void> _loadFonts() async {
  final ddin = FontLoader('DDIN')
    ..addFont(rootBundle.load('assets/fonts/D-DIN.otf'))
    ..addFont(rootBundle.load('assets/fonts/D-DIN-Bold.otf'));
  final loaders = [ddin];
  for (final style in const ['Light', 'Fill', 'Bold']) {
    loaders.add(FontLoader('Phosphor$style')..addFont(rootBundle.load('assets/fonts/Phosphor-$style.ttf')));
  }
  await Future.wait(loaders.map((l) => l.load()));
}

void _setSize(WidgetTester t, Size logical) {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = logical * 3;
  addTearDown(t.view.reset);
}

/// Una app con dos placas demo y una real guardadas, como la tendría el usuario.
Future<AppState> _state({DeviceLink Function(SavedDevice)? linkFor}) async {
  SharedPreferences.setMockInitialValues({});
  final app = AppState(linkFor: linkFor);
  await app.load();
  await app.add(SavedDevice(id: 'esp32', name: 'Casa Domótica', profile: Profile.casa, transport: Transport.ble, address: '3C:71:BF:19:A7:1A'));
  return app;
}

Future<void> _show(WidgetTester t, AppState app, Widget screen, ThemeMode mode, {Size size = _portrait}) async {
  _setSize(t, size);
  await t.pumpWidget(ControlApp(state: app, home: screen, forceTheme: mode));
  await t.pump(const Duration(seconds: 1));
}

Future<void> _shot(String name) => expectLater(find.byType(MaterialApp), matchesGoldenFile('salida/$name.png'));

void main() {
  setUpAll(_loadFonts);

  for (final MapEntry(key: tema, value: mode) in _themes.entries) {
    group(tema, () {
      testWidgets('inicio', (t) async {
        final app = await _state();
        await t.runAsync(() async {
          await app.session(app.devices.first).connect();
          app.session(app.devices.first)
            ..send(10, 1)
            ..send(12, 1);
          await Future<void>.delayed(const Duration(milliseconds: 300));
        });
        await _show(t, app, const HomeScreen(), mode);
        await _shot('01_inicio_$tema');
        await t.tap(find.byTooltip('Ajustes'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await _shot('07_ajustes_$tema');
        await t.runAsync(app.session(app.devices.first).disconnect);
      });

      // La firma siempre es oscura: basta una captura.
      testWidgets('firma escondida', skip: mode != ThemeMode.dark, (t) async {
        final app = await _state();
        await _show(t, app, const CreditsScreen(), mode);
        // Cuadro a cuadro, como en el teléfono, para que terminen las animaciones.
        for (var i = 0; i < 60; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        await _shot('12_firma');
      });

      testWidgets('novedades', (t) async {
        final app = await _state();
        await _show(t, app, const HomeScreen(), mode);
        showNewsSheet(t.element(find.byType(HomeScreen)), justUpdated: true);
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await _shot('13_novedades_$tema');
      });

      testWidgets('cambiar la clave', (t) async {
        final app = await _state(linkFor: (d) => d.transport == Transport.demo ? DemoLink(d.profile.name) : _KeyedHouseLink());
        final casa = app.devices.firstWhere((d) => d.id == 'esp32')..clave = '1234';
        final s = app.session(casa);
        await t.runAsync(() async {
          await s.connect();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await _show(t, app, const HomeScreen(), mode);
        await t.longPress(find.text('Casa Domótica'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await _shot('14_opciones_clave_$tema');
        await t.tap(find.text('Cambiar la clave'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await t.enterText(find.byType(TextField), '482913');
        await t.pump();
        await t.tap(find.text('GUARDAR CLAVE NUEVA'));
        for (var i = 0; i < 5; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await t.pump(const Duration(milliseconds: 20));
        }
        await t.pump(const Duration(seconds: 1));
        await _shot('15_clave_cambiada_$tema');
        await t.runAsync(s.disconnect);
      });

      testWidgets('agregar dispositivo', (t) async {
        final app = await _state();
        await _show(t, app, const AddDeviceScreen(), mode);
        await _shot('02_agregar_$tema');

        // Wi-Fi: redes de ejemplo, como las que vería el teléfono cerca de la maqueta.
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('control_domotica/red'), (call) async {
          return switch (call.method) {
            'permisoWifi' => true,
            'redPlaca' => null,
            'redesWifi' => [
                {'ssid': 'Casa Domotica', 'nivel': -48, 'segura': true, 'ghz': 2},
                {'ssid': 'MiCasa_5G', 'nivel': -55, 'segura': true, 'ghz': 5},
                {'ssid': 'Vecino', 'nivel': -80, 'segura': true, 'ghz': 2},
              ],
            _ => null,
          };
        });
        await t.tap(find.text('WI-FI'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await _shot('02b_agregar_wifi_$tema');
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('control_domotica/red'), null);
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
        await _show(t, app, CasaPanel(device: casa, initiallyOpen: const {'Sala'}), mode);
        await _shot('03_casa_$tema');
        await t.drag(find.byType(Scrollable).first, const Offset(0, -560));
        await t.pump(const Duration(milliseconds: 500));
        await _shot('04_casa_salas_$tema');
        await t.longPress(find.text('Luz 1'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await _shot('08_hoja_pines_$tema');
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
        await _show(t, app, CasaPanel(device: casa, session: s), mode);
        await _shot('05_casa_alarma_$tema');
        await t.runAsync(s.disconnect);
      });

      testWidgets('casa reconectando', (t) async {
        final app = await _state();
        final casa = app.devices.firstWhere((d) => d.id == 'esp32');
        final s = Session(casa, linkFor: (_) => _DeadLink());
        await t.runAsync(() async {
          await s.connect();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await _show(t, app, CasaPanel(device: casa, session: s), mode);
        await _shot('11_reconectando_$tema');
        await t.runAsync(s.disconnect);
      });

      testWidgets('casa pide crear la clave', (t) async {
        final app = await _state();
        final casa = app.devices.firstWhere((d) => d.id == 'esp32');
        final s = Session(casa, linkFor: (_) => _NewHouseLink());
        await t.runAsync(() async {
          await s.connect();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await _show(t, app, CasaPanel(device: casa, session: s), mode);
        await _shot('09_crear_clave_$tema');
        await t.runAsync(s.disconnect);
      });

      testWidgets('carro', (t) async {
        final app = await _state();
        final carro = app.devices.firstWhere((d) => d.id == 'demo-carro');
        final s = app.session(carro);
        await t.runAsync(() async {
          await s.connect();
          await Future<void>.delayed(const Duration(milliseconds: 900));
          s.send(CarPins.invert, '0100');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await _show(t, app, CarroPanel(device: carro), mode, size: _landscape);
        await _shot('06_carro_$tema');
        await t.tap(find.byTooltip('Ruedas'));
        await t.pump();
        await t.pump(const Duration(seconds: 1));
        await _shot('10_carro_ruedas_$tema');
        await t.runAsync(s.disconnect);
      });
    });
  }
}

/// Una casa con clave que acepta la guardada y también la nueva.
class _KeyedHouseLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {
    if (line.startsWith('AUTH') || line.startsWith('CLAVE')) emitLine('AUTH:OK');
  }
}

/// Una casa recién cargada: todavía no tiene clave.
class _NewHouseLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {
    if (line.startsWith('AUTH')) emitLine('AUTH:NUEVA');
  }
}

/// Una placa apagada: cada intento falla, y la app queda reintentando.
class _DeadLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.error, 'La placa dejó de responder. ¿Se apagó o está lejos?');

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {}
}

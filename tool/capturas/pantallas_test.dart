// Capturas de todas las pantallas de la app, con las fuentes reales, para revisar el diseño sin un teléfono.
//
//   flutter test tool/capturas/pantallas_test.dart
//
// Guarda los PNG en build/capturas/. No es parte de las pruebas normales (vive fuera de test/).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/ui/add_device_screen.dart';
import 'package:control_domotica/ui/carro_panel.dart';
import 'package:control_domotica/ui/casa_panel.dart';
import 'package:control_domotica/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _out = 'build/capturas';
final _shot = GlobalKey();

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(rootBundle.load(f));
  }
  await loader.load();
}

/// Un teléfono común: 390 × 844 puntos (a 3x).
Future<void> _phone(WidgetTester t, {double w = 390, double h = 844}) async {
  t.view.devicePixelRatio = 3;
  t.view.physicalSize = Size(w * 3, h * 3);
}

Future<void> _snap(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 400));
  final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

Future<AppState> _app(WidgetTester t, {ThemeMode theme = ThemeMode.dark, Widget home = const HomeScreen()}) async {
  // Es una prueba, aunque viva fuera de test/ para no correr con las demás.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({'novedades_vistas': 999});
  final app = AppState();
  await app.load();
  await t.pumpWidget(RepaintBoundary(key: _shot, child: ControlApp(state: app, home: home, forceTheme: theme)));
  await t.pump(const Duration(milliseconds: 300));
  return app;
}

/// Cierra las conexiones demo para que no queden temporizadores al terminar.
Future<void> _end(WidgetTester t, AppState app) async {
  for (final d in app.devices) {
    await app.session(d).disconnect();
  }
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 2));
}

void main() {
  setUpAll(() async {
    Directory(_out).createSync(recursive: true);
    await _font('DDIN', ['assets/fonts/D-DIN.otf', 'assets/fonts/D-DIN-Bold.otf']);
    await _font('PhosphorLight', ['assets/fonts/Phosphor-Light.ttf']);
    await _font('PhosphorFill', ['assets/fonts/Phosphor-Fill.ttf']);
    await _font('PhosphorBold', ['assets/fonts/Phosphor-Bold.ttf']);
  });

  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    final tag = theme == ThemeMode.dark ? 'oscuro' : 'claro';

    testWidgets('inicio $tag', (t) async {
      await _phone(t);
      final app = await _app(t, theme: theme);
      await _snap(t, '01-inicio-$tag');
      for (final d in app.devices) {
        app.session(d).connect();
      }
      await t.pump(const Duration(seconds: 2));
      await _snap(t, '02-inicio-conectado-$tag');

      await t.tap(find.byTooltip('Ajustes'));
      await t.pump(const Duration(milliseconds: 600));
      await _snap(t, '03-ajustes-$tag');
      await t.tapAt(const Offset(195, 40));
      await t.pump(const Duration(milliseconds: 600));

      await t.longPress(find.text('Casa (demo)'));
      await t.pump(const Duration(milliseconds: 600));
      await _snap(t, '04-opciones-$tag');
      await _end(t, app);
    });

    testWidgets('casa $tag', (t) async {
      await _phone(t);
      final app = await _app(t, theme: theme);
      final casa = app.devices.firstWhere((d) => d.profile == Profile.casa);
      app.session(casa).connect();
      await t.pump(const Duration(seconds: 2));
      await t.pumpWidget(RepaintBoundary(key: _shot, child: ControlApp(state: app, home: CasaPanel(device: casa), forceTheme: theme)));
      await t.pump(const Duration(seconds: 1));
      await _snap(t, '05-casa-$tag');
      // Toda la pantalla de una vez, para ver el largo completo.
      await _phone(t, h: 2600);
      await t.pump(const Duration(milliseconds: 500));
      await _snap(t, '06-casa-completa-$tag');
      await _end(t, app);
    });

    testWidgets('carrito $tag', (t) async {
      await _phone(t, w: 844, h: 390);
      final app = await _app(t, theme: theme);
      final carro = app.devices.firstWhere((d) => d.profile == Profile.carro);
      app.session(carro).connect();
      // La demo «conecta» en 0,6 s y espera la clave 2,5 s (no la usa); después dice su lápiz: es el robot.
      await t.pump(const Duration(seconds: 4));
      await t.pumpWidget(RepaintBoundary(key: _shot, child: ControlApp(state: app, home: CarroPanel(device: carro), forceTheme: theme)));
      await t.pump(const Duration(seconds: 1));
      await _snap(t, '07-carro-$tag');

      // Con una palabra escrita: la vista previa con las letras del robot.
      await t.enterText(find.byType(TextField), 'Hola Feria');
      await t.pump(const Duration(milliseconds: 300));
      await _snap(t, '07b-robot-texto-$tag');

      // Escribiendo: el avance letra por letra.
      await t.tap(find.bySemanticsLabel('Escribir'));
      await t.pump(const Duration(milliseconds: 2900));
      await _snap(t, '07c-robot-escribiendo-$tag');
      await t.tap(find.bySemanticsLabel('Parar: Escritura'));
      await t.pump(const Duration(seconds: 1));

      // Sus ajustes: ruedas, lápiz y medidas.
      await t.tap(find.byTooltip('Ajustes del robot'));
      await t.pump(const Duration(seconds: 1));
      await _snap(t, '07d-robot-ajustes-$tag');
      await _end(t, app);
    });

    testWidgets('agregar $tag', (t) async {
      await _phone(t);
      final app = await _app(t, theme: theme, home: const AddDeviceScreen());
      await t.pump(const Duration(seconds: 1));
      await _snap(t, '08-agregar-$tag');
      await _end(t, app);
    });
  }
}

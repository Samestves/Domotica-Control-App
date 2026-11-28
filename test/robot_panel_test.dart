import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/models/pins.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/ui/carro_panel.dart';
import 'package:control_domotica/ui/widgets/drive_controls.dart';
import 'package:control_domotica/ui/widgets/robot_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El robot de la demo (igual que carro-0.6), anotando todo lo que recibe.
class _Robot extends DemoLink {
  final sent = <String>[];
  _Robot() : super('carro', letterTime: const Duration(milliseconds: 400));

  @override
  Future<void> sendLine(String line) async {
    sent.add(line);
    await super.sendLine(line);
  }
}

void main() {
  /// Panel del robot conectado, en un teléfono acostado.
  Future<(Session, _Robot)> open(WidgetTester t, {Size size = const Size(860, 400)}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final robot = _Robot();
    final app = AppState(linkFor: (_) => robot);
    await app.load();
    final d = SavedDevice(id: 'r', name: 'Auto Robot', profile: Profile.carro, transport: Transport.ble, address: 'X');
    await app.add(d);
    final s = app.session(d);
    await t.pumpWidget(ControlApp(state: app, home: CarroPanel(device: d)));
    await t.runAsync(s.connect);
    // La demo tarda 0,6 s en «conectar»; después la clave espera 2,5 s (el robot de la demo no la usa) y llega SYNC.
    for (var i = 0; i < 40 && !(s.connected && isRobot(s)); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(s.connected && isRobot(s), isTrue, reason: 'conectado, la placa dice su lápiz: es el robot');
    return (s, robot);
  }

  /// Deja pasar [ms]. Las respuestas de la demo a un toque esperan con el reloj de la prueba; la lista de
  /// mensajes de la sesión (la conexión se abrió con el reloj de verdad) llega con el reloj de verdad.
  Future<void> settle(WidgetTester t, [int ms = 300]) async {
    await t.pump(Duration(milliseconds: ms));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }

  Future<void> close(WidgetTester t, Session s) async {
    await t.pumpWidget(const SizedBox());
    await t.runAsync(s.disconnect);
    await t.pump(const Duration(seconds: 1));
  }

  testWidgets('el robot tiene su tablero: manejar, escribir, lápiz y parar (sin acelerador ni luces)', (t) async {
    final (s, _) = await open(t);
    expect(find.byType(DriveTile), findsOneWidget);
    expect(find.byType(WriteTile), findsOneWidget);
    expect(find.byType(PenTile), findsOneWidget);
    expect(find.bySemanticsLabel('Parar: Todo'), findsOneWidget);
    expect(find.byType(Throttle), findsNothing, reason: 'el robot se maneja solo con el joystick');
    expect(find.bySemanticsLabel('Luces'), findsNothing);
    expect(find.text('Aquí ves cómo lo va a dibujar'), findsOneWidget);
    expect(t.takeException(), isNull, reason: 'nada se sale de su tarjeta');
    await close(t, s);
  });

  testWidgets('en un teléfono chico (640 × 360) el tablero entra sin desbordarse', (t) async {
    final (s, _) = await open(t, size: const Size(640, 360));
    expect(find.byType(WriteTile), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t, s);
  });

  testWidgets('escribir: la vista previa, el avance letra por letra y «Listo»', (t) async {
    final (s, robot) = await open(t);
    await t.enterText(find.byType(TextField), 'hola!');
    await t.pump();
    expect(find.text('5 letras de 3 cm'), findsOneWidget, reason: 'cuenta lo que va a dibujar, con el alto de las letras');
    expect(find.bySemanticsLabel('Vista previa: HOLA!'), findsOneWidget, reason: 'muestra lo que va a dibujar, en mayúsculas');

    await t.tap(find.bySemanticsLabel('Escribir'));
    await settle(t);
    expect(robot.sent, contains('ESCRIBIR:HOLA!'));
    expect(find.textContaining('Letra 1 de 5'), findsOneWidget);
    expect(find.text('Escribiendo · letra 1 de 5'), findsOneWidget, reason: 'la tarjeta de manejar también lo dice');
    expect(t.widget<Joystick>(find.byType(Joystick)).enabled, isFalse, reason: 'escribiendo, el joystick no maneja');
    expect(find.bySemanticsLabel('Parar: Escritura'), findsOneWidget);
    expect(find.bySemanticsLabel('Lápiz: Abajo'), findsOneWidget, reason: 'se ve el lápiz que baja');

    for (var i = 0; i < 12 && writingProgress(s) != null; i++) {
      await settle(t, 300);
    }
    expect(writingProgress(s), isNull);
    expect(find.text('Listo: escribió «HOLA!»'), findsOneWidget);
    expect(t.widget<Joystick>(find.byType(Joystick)).enabled, isTrue);
    await close(t, s);
  });

  testWidgets('«Parar» detiene la escritura y lo dice', (t) async {
    final (s, robot) = await open(t);
    await t.enterText(find.byType(TextField), 'HOLA MUNDO');
    await t.pump();
    await t.tap(find.bySemanticsLabel('Escribir'));
    await settle(t, 500);
    expect(writingProgress(s), isNotNull);

    await t.tap(find.bySemanticsLabel('Parar: Escritura'));
    await settle(t);
    expect(robot.sent, contains('PARAR'));
    expect(writingProgress(s), isNull);
    expect(find.text('Se detuvo a mitad'), findsOneWidget);
    expect(find.bySemanticsLabel('Lápiz: Arriba'), findsOneWidget, reason: 'el marcador sube');
    await close(t, s);
  });

  testWidgets('el lápiz se baja y se sube con un toque', (t) async {
    final (s, robot) = await open(t);
    await t.tap(find.bySemanticsLabel('Lápiz: Arriba'));
    await settle(t);
    expect(robot.sent, contains('V${CarPins.pen}:1'));
    expect(find.bySemanticsLabel('Lápiz: Abajo'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Lápiz: Abajo'));
    await settle(t);
    expect(robot.sent, contains('V${CarPins.pen}:0'));
    await close(t, s);
  });

  testWidgets('el teclado no se cierra solo: al abrirse, el campo sigue siendo el mismo y con el foco', (t) async {
    // El bug de la 0.9.9: al subir el teclado la tarjeta cambiaba de forma, el campo se rearmaba, perdía el foco
    // y el teclado bajaba al instante (y volvía a empezar).
    final (s, _) = await open(t);
    await t.showKeyboard(find.byType(TextField));
    final field = t.state<EditableTextState>(find.byType(EditableText));
    expect(t.testTextInput.isVisible, isTrue);
    for (final inset in [220.0, 300.0, 0.0, 220.0]) {
      t.view.viewInsets = FakeViewPadding(bottom: inset); // el teclado sube (o Android lo acomoda)
      await t.pump();
      expect(t.state<EditableTextState>(find.byType(EditableText)), same(field), reason: 'con el teclado a $inset: el mismo campo');
      expect(field.widget.focusNode.hasFocus, isTrue, reason: 'con el teclado a $inset: sigue con el foco');
      expect(t.testTextInput.isVisible, isTrue, reason: 'con el teclado a $inset: el teclado sigue arriba');
    }
    t.view.resetViewInsets();
    await t.pump();
    await close(t, s);
  });

  testWidgets('con el teclado abierto queda solo escribir, sin perder el texto', (t) async {
    final (s, _) = await open(t);
    await t.enterText(find.byType(TextField), 'SOL');
    t.view.viewInsets = const FakeViewPadding(bottom: 220); // el teclado
    addTearDown(t.view.resetViewInsets);
    await t.pump();
    expect(find.byType(DriveTile), findsNothing, reason: 'no hay alto para el joystick');
    expect(find.byType(WriteTile), findsOneWidget);
    expect(t.takeException(), isNull);
    expect(find.text('SOL'), findsOneWidget, reason: 'el texto sigue ahí');

    t.view.resetViewInsets();
    await t.pump();
    expect(find.byType(DriveTile), findsOneWidget);
    expect(find.text('SOL'), findsOneWidget);
    await close(t, s);
  });

  testWidgets('los ajustes del robot: dos ruedas y el lápiz, y las medidas se guardan en la placa', (t) async {
    final (s, robot) = await open(t, size: const Size(900, 1400)); // la hoja se ve entera
    await t.tap(find.byTooltip('Ajustes del robot'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('Ruedas y lápiz'), findsOneWidget);
    expect(find.text('Rueda izquierda'), findsOneWidget);
    expect(find.text('Rueda derecha'), findsOneWidget);
    expect(find.text('Lápiz'), findsWidgets);

    final letter = find.widgetWithText(TextField, '30');
    await t.enterText(letter, '45');
    await t.pump();
    await t.ensureVisible(find.bySemanticsLabel('Guardar medidas'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.bySemanticsLabel('Guardar medidas'));
    await settle(t);
    expect(robot.sent, contains('V${CarPins.measures}:65,120,45,1000'));
    expect(RobotMeasures.of(s).letterMm, 45);
    await close(t, s);
  });

  test('el estado de la escritura se lee de V29', () {
    final s = Session(SavedDevice(id: 'x', name: 'R', profile: Profile.carro, transport: Transport.demo), linkFor: (_) => _Silent());
    expect(writingProgress(s), isNull);
    s.values[CarPins.writing] = '3/5';
    expect(writingProgress(s), (3, 5));
    s.values[CarPins.writing] = '0';
    expect(writingProgress(s), isNull);
    s.values[CarPins.measures] = '43,97,25,800';
    expect(RobotMeasures.of(s).letterText, '2,5 cm');
  });
}

class _Silent extends DeviceLink {
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> sendLine(String line) async {}
}

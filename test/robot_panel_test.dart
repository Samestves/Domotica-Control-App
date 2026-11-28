import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/models/pins.dart';
import 'package:control_domotica/models/robot.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/ui/carro_panel.dart';
import 'package:control_domotica/ui/widgets/drive_controls.dart';
import 'package:control_domotica/ui/widgets/robot_paper.dart';
import 'package:control_domotica/ui/widgets/robot_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El robot de la demo (igual que carro-0.7), anotando todo lo que recibe.
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
  /// Cada prueba con su propia placa: el tablero elegido (manejar o escribir) se recuerda por placa.
  var boards = 0;

  /// Panel del robot conectado, en un teléfono acostado.
  Future<(Session, _Robot)> open(WidgetTester t, {Size size = const Size(860, 400)}) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final robot = _Robot();
    final app = AppState(linkFor: (_) => robot);
    await app.load();
    final d = SavedDevice(id: 'robot-${boards++}', name: 'Auto Robot', profile: Profile.carro, transport: Transport.ble, address: 'X');
    await app.add(d);
    final s = app.session(d);
    await t.pumpWidget(ControlApp(state: app, home: CarroPanel(device: d)));
    await t.runAsync(s.connect);
    // La demo tarda 0,6 s en «conectar»; después la clave espera 2,5 s (el robot de la demo no la usa) y llega SYNC.
    for (var i = 0; i < 40 && !(s.connected && isRobot(s) && robotKnowsPaper(s)); i++) {
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

  Future<void> toWrite(WidgetTester t) async {
    await t.tap(find.bySemanticsLabel('Escribir').first); // el selector de arriba
    await t.pump(); // empieza la transición
    await t.pump(const Duration(milliseconds: 400)); // termina
    await t.pump(); // y el tablero de manejar se va
  }

  Finder writeButton() => find.descendant(of: find.byType(WriteTile), matching: find.bySemanticsLabel('Escribir'));

  group('Manejar', () {
    testWidgets('los controles del carrito, en cuadros: joystick, acelerador, reversa, velocidad, parar, lápiz, hoja y cara',
        (t) async {
      final (s, _) = await open(t);
      expect(find.bySemanticsLabel('Manejar'), findsOneWidget, reason: 'el selector de modo, arriba');
      expect(find.byType(DriveTile), findsOneWidget);
      expect(find.byType(Throttle), findsOneWidget, reason: 'el acelerador de antes, también en el robot');
      for (final tile in ['Reversa: No', 'Velocidad: Normal', 'Parar: Todo', 'Lápiz: Arriba']) {
        expect(find.bySemanticsLabel(tile), findsOneWidget, reason: tile);
      }
      expect(find.byType(PaperTile), findsOneWidget);
      expect(find.byType(FaceTile), findsOneWidget, reason: 'con lugar, la cara en vivo');
      expect(find.byType(WriteTile), findsNothing, reason: 'escribir es el otro modo');
      expect(t.takeException(), isNull, reason: 'nada se sale de su tarjeta');
      await close(t, s);
    });

    testWidgets('en un teléfono chico (640 × 360) los dos tableros entran sin desbordarse', (t) async {
      final (s, _) = await open(t, size: const Size(640, 360));
      expect(find.byType(DriveTile), findsOneWidget);
      expect(find.byType(FaceTile), findsNothing, reason: 'angosto: la cara no entra');
      expect(t.takeException(), isNull);
      await toWrite(t);
      expect(find.byType(WriteTile), findsOneWidget);
      expect(t.takeException(), isNull);
      await close(t, s);
    });

    testWidgets('reversa y velocidad lenta: el joystick vale un tercio para ubicar el robot', (t) async {
      final (s, robot) = await open(t);
      await t.tap(find.bySemanticsLabel('Reversa: No'));
      await settle(t);
      expect(robot.sent, contains('V${CarPins.reverse}:1'));
      expect(find.bySemanticsLabel('Reversa: Puesta'), findsOneWidget);

      await t.tap(find.bySemanticsLabel('Velocidad: Normal'));
      await t.pump();
      expect(find.bySemanticsLabel('Velocidad: Lenta'), findsOneWidget);
      robot.sent.clear();
      final gesture = await t.startGesture(t.getCenter(find.byType(Joystick)));
      await gesture.moveBy(const Offset(0, -150)); // a fondo hacia adelante
      await t.pump(const Duration(milliseconds: 120));
      final ys = robot.sent
          .where((l) => l.startsWith('V${CarPins.joystick}:'))
          .map((l) => int.parse(l.split(':')[1].split(',')[1]))
          .toList();
      expect(ys, isNotEmpty);
      expect(ys.reduce((a, b) => a > b ? a : b), inInclusiveRange(30, 35), reason: 'a fondo es 35 en vez de 100');
      await gesture.up();
      await settle(t);
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
  });

  group('La hoja', () {
    testWidgets('«0,0» pone el robot en la esquina y la hoja lo muestra donde está', (t) async {
      final (s, robot) = await open(t);
      expect(find.textContaining('toca 0,0'), findsOneWidget, reason: 'sin 0,0, explica qué hacer');
      await t.tap(find.bySemanticsLabel('0,0'));
      await settle(t);
      expect(robot.sent, contains('CERO'));
      expect(robotPose(s), const RobotPose(0, 0, 0));
      expect(find.text('x 0,0 · y 0,0 cm · 0°'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Hoja Carta: el robot está en 0,0, 0,0 cm')), findsOneWidget);
      await close(t, s);
    });

    testWidgets('un toque en la hoja e «Ir aquí» lo lleva hasta ahí, derecho para escribir', (t) async {
      final (s, robot) = await open(t);
      await t.tap(find.bySemanticsLabel('0,0'));
      await settle(t);
      await t.tapAt(t.getRect(find.byType(PaperView)).center); // el centro de la carta: (139,5; 108) mm
      await t.pump();
      await t.tap(find.bySemanticsLabel('Ir aquí'));
      await settle(t, 100);
      expect(robot.sent.where((l) => l.startsWith('IR:')).single, matches(RegExp(r'^IR:1[34]\d,10\d$')));
      expect(robotGoing(s), isTrue);
      expect(t.widget<Joystick>(find.byType(Joystick)).enabled, isFalse, reason: 'yendo, el joystick espera');
      for (var i = 0; i < 40 && robotGoing(s); i++) {
        await settle(t, 200);
      }
      final p = robotPose(s)!;
      expect(robotGoing(s), isFalse);
      expect((p.x - 140).abs() < 2 && (p.y - 108).abs() < 2 && p.deg == 0, isTrue, reason: 'llegó al centro, derecho: $p');
      await close(t, s);
    });

    testWidgets('la hoja se elige en los ajustes del robot', (t) async {
      final (s, robot) = await open(t, size: const Size(900, 1600)); // la hoja de ajustes se ve entera
      await t.tap(find.byTooltip('Ajustes del robot'));
      await t.pump(const Duration(milliseconds: 600));
      await t.ensureVisible(find.bySemanticsLabel('A4'));
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.bySemanticsLabel('A4'));
      await settle(t);
      expect(robot.sent, contains('V${CarPins.paper}:297,210'));
      expect(robotPaper(s), const Paper(297, 210));
      await t.tap(find.bySemanticsLabel('Sin hoja'));
      await settle(t);
      expect(robot.sent, contains('V${CarPins.paper}:0,0'));
      expect(robotPaper(s), isNull);
      await close(t, s);
    });
  });

  group('Escribir', () {
    testWidgets('el selector cambia al tablero de escribir: texto, vista previa, hoja, lápiz y parar', (t) async {
      final (s, _) = await open(t);
      await toWrite(t);
      expect(find.byType(WriteTile), findsOneWidget);
      expect(find.byType(PaperTile), findsOneWidget);
      expect(find.byType(DriveTile), findsNothing);
      expect(find.byType(Throttle), findsNothing);
      expect(find.text('Aquí ves cómo lo va a dibujar'), findsOneWidget);
      expect(t.takeException(), isNull);
      await close(t, s);
    });

    testWidgets('la vista previa, el avance letra por letra y «Listo»', (t) async {
      final (s, robot) = await open(t);
      await toWrite(t);
      await t.enterText(find.byType(TextField), 'hola!');
      await t.pump();
      expect(find.text('5 letras de 3 cm'), findsOneWidget, reason: 'cuenta lo que va a dibujar, con el alto de las letras');
      expect(find.bySemanticsLabel('Vista previa: HOLA!'), findsOneWidget, reason: 'muestra lo que va a dibujar, en mayúsculas');

      await t.tap(writeButton());
      await settle(t);
      expect(robot.sent, contains('ESCRIBIR:HOLA!'));
      expect(find.textContaining('Letra 1 de 5'), findsOneWidget);
      expect(find.bySemanticsLabel('Parar: Escritura'), findsOneWidget);
      expect(find.bySemanticsLabel('Lápiz: Abajo'), findsOneWidget, reason: 'se ve el lápiz que baja');

      for (var i = 0; i < 12 && writingProgress(s) != null; i++) {
        await settle(t, 300);
      }
      expect(writingProgress(s), isNull);
      expect(find.text('Listo: escribió «HOLA!»'), findsOneWidget);
      await close(t, s);
    });

    testWidgets('si no cabe en la hoja lo dice y no deja escribir; con letras más chicas, sí', (t) async {
      final (s, robot) = await open(t);
      await t.tap(find.bySemanticsLabel('0,0'));
      await settle(t);
      await toWrite(t);
      await t.enterText(find.byType(TextField), 'HOLA MUNDO'); // 29 cm con letras de 3: la carta mide 27,9
      await t.pump();
      expect(find.text('No cabe en la hoja: mueve el robot o achica las letras'), findsOneWidget);
      expect(t.widget<Semantics>(writeButton()).properties.enabled, isFalse);

      await t.tap(find.bySemanticsLabel('Letras de 2 cm'));
      await settle(t);
      expect(robot.sent, contains('V${CarPins.measures}:65,120,20,1000'));
      expect(find.text('9 letras de 2 cm · cabe en la hoja'), findsOneWidget);
      expect(t.widget<Semantics>(writeButton()).properties.enabled, isTrue);
      await close(t, s);
    });

    testWidgets('«Parar» detiene la escritura y lo dice', (t) async {
      final (s, robot) = await open(t);
      await toWrite(t);
      await t.enterText(find.byType(TextField), 'HOLA MUNDO');
      await t.pump();
      await t.tap(writeButton());
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

    testWidgets('el teclado no se cierra solo: al abrirse, el campo sigue siendo el mismo y con el foco', (t) async {
      // El bug de la 0.9.9: al subir el teclado la tarjeta cambiaba de forma, el campo se rearmaba, perdía el foco
      // y el teclado bajaba al instante (y volvía a empezar).
      final (s, _) = await open(t);
      await toWrite(t);
      await t.showKeyboard(find.byType(TextField));
      final field = t.state<EditableTextState>(find.byType(EditableText));
      expect(t.testTextInput.isVisible, isTrue);
      for (final inset in [220.0, 300.0, 0.0, 220.0]) {
        t.view.viewInsets = FakeViewPadding(bottom: inset); // el teclado sube (o Android lo acomoda)
        await t.pump();
        expect(t.state<EditableTextState>(find.byType(EditableText)), same(field), reason: 'con el teclado a $inset: el mismo campo');
        expect(field.widget.focusNode.hasFocus, isTrue, reason: 'con el teclado a $inset: sigue con el foco');
        expect(t.testTextInput.isVisible, isTrue, reason: 'con el teclado a $inset: el teclado sigue arriba');
        expect(t.takeException(), isNull, reason: 'con el teclado a $inset: nada se desborda');
      }
      t.view.resetViewInsets();
      await t.pump();
      await close(t, s);
    });

    testWidgets('con el teclado abierto queda solo escribir, sin perder el texto', (t) async {
      final (s, _) = await open(t);
      await toWrite(t);
      await t.enterText(find.byType(TextField), 'SOL');
      t.view.viewInsets = const FakeViewPadding(bottom: 220); // el teclado
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      expect(find.byType(PaperTile), findsNothing, reason: 'no hay alto para la hoja');
      expect(find.bySemanticsLabel('Manejar'), findsNothing, reason: 'ni para la barra de arriba');
      expect(find.byType(WriteTile), findsOneWidget);
      expect(t.takeException(), isNull);
      expect(find.text('SOL'), findsOneWidget, reason: 'el texto sigue ahí');

      t.view.resetViewInsets();
      await t.pump();
      expect(find.byType(PaperTile), findsOneWidget);
      expect(find.text('SOL'), findsOneWidget);
      await close(t, s);
    });
  });

  group('La cara', () {
    testWidgets('se pide al verla (CARA:1), llega en vivo y se deja de pedir al cambiar de tablero (CARA:0)', (t) async {
      final (s, robot) = await open(t);
      await settle(t);
      expect(robot.sent, contains('CARA:1'));
      expect(FaceTarget.parse(s.values[CarPins.face]), isNotNull, reason: 'la cara llega (V33)');
      expect(FaceLabel.parse(s.values[CarPins.faceLabel])?.text, 'HOLA');
      expect(s.log.where((l) => l.text.startsWith('V${CarPins.face}:')), isEmpty, reason: 'no llena el registro de mensajes');
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50)); // los ojos se animan
      }
      expect(t.takeException(), isNull);

      await toWrite(t);
      await settle(t);
      expect(robot.sent.last, 'CARA:0', reason: 'en el tablero de escribir no se ve: deja de pedirla');
      await close(t, s);
    });
  });

  group('Ajustes del robot', () {
    testWidgets('dos ruedas y el lápiz, y las medidas se guardan en la placa', (t) async {
      final (s, robot) = await open(t, size: const Size(900, 1600));
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
  });

  test('el estado del trabajo se lee de V29', () {
    final s = Session(SavedDevice(id: 'x', name: 'R', profile: Profile.carro, transport: Transport.demo), linkFor: (_) => _Silent());
    expect(writingProgress(s), isNull);
    s.values[CarPins.writing] = '3/5';
    expect(writingProgress(s), (3, 5));
    expect(robotBusy(s), isTrue);
    s.values[CarPins.writing] = 'ir';
    expect(writingProgress(s), isNull);
    expect(robotGoing(s) && robotBusy(s), isTrue);
    s.values[CarPins.writing] = '0';
    expect(robotBusy(s), isFalse);
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

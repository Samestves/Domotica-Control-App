import 'dart:io';

import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/models/letras.dart';
import 'package:control_domotica/models/pins.dart';
import 'package:control_domotica/models/robot.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/ui/widgets/robot_face.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('La hoja: las mismas cuentas que la placa (escritura.h)', () {
    test('la caja de un texto', () {
      expect(textBox('HOLA', 30), (x0: 0.0, y0: 0.0, x1: 110.0, y1: 30.0), reason: 'como Escritor::caja: 110 × 30 mm');
      expect(textBox('I', 30), (x0: 5.0, y0: 0.0, x1: 15.0, y1: 30.0), reason: 'la I solo ocupa su palito y sus rayas');
      expect(textBox('A,', 30)!.y0, -5, reason: 'la coma baja de la línea');
      expect(textBox('Ñ', 30)!.y1, 35, reason: 'la tilde de la Ñ sube');
      expect(textBox('', 30), isNull);
    });

    test('si cabe en una carta acostada (los mismos casos que la prueba de la placa)', () {
      const carta = Paper(279, 216);
      final hola = textBox('HOLA', 30)!;
      expect(fitsOnPaper(hola, const RobotPose(0, 0, 0), carta), isTrue);
      expect(fitsOnPaper(hola, const RobotPose(200, 0, 0), carta), isFalse, reason: 'se sale por la derecha');
      expect(fitsOnPaper(hola, const RobotPose(0, 190, 0), carta), isFalse, reason: 'se sale por arriba');
      expect(fitsOnPaper(hola, const RobotPose(20, 200, -90), carta), isTrue, reason: 'de costado, mirando hacia abajo');
      expect(fitsOnPaper(hola, const RobotPose(20, 100, -90), carta), isFalse, reason: 'de costado se sale por abajo');
      expect(fitsOnPaper(textBox(Letras.normalizar('HOLA MUNDO'), 30)!, const RobotPose(0, 0, 0), carta), isFalse, reason: '290 mm');
      expect(fitsOnPaper(textBox(Letras.normalizar('HOLA MUNDO'), 20)!, const RobotPose(0, 0, 0), carta), isTrue);
      expect(fitsOnPaper(textBox('A,', 30)!, const RobotPose(0, 0, 0), carta), isFalse, reason: 'la coma quedaría fuera');
    });

    test('lo que dice la placa se lee bien', () {
      expect(RobotPose.parse('120,45,90'), const RobotPose(120, 45, 90));
      expect(RobotPose.parse('-'), isNull, reason: 'sin 0,0');
      expect(Paper.parse('279,216'), const Paper(279, 216));
      expect(Paper.parse('0,0'), isNull, reason: 'sin hoja');
      expect(const Paper(279, 216).name, 'Carta');
      expect(const Paper(300, 205).name, '30 × 20,5 cm');
      final f = FaceTarget.parse('32,0,0,100,96,0,-50,70,100,0,60,13')!;
      expect((f.tired, f.happy, f.scale, f.lx, f.ly, f.blinkL, f.speed), (.32, 1.0, .96, -.5, .7, 1.0, 60));
      expect(f.sleeping && !f.shaking && f.bouncing && f.bluetooth && !f.wifi, isTrue, reason: 'marcas 1 + 4 + 8');
      expect(FaceLabel.parse('7,60000,ESCRIBIENDO 3/5')?.text, 'ESCRIBIENDO 3/5', reason: 'el texto puede tener comas o barras');
      expect(FaceLabel.parse('basura'), isNull);
    });
  });

  group('La cara en la app (el motor de cara.h)', () {
    test('las letras de la cara son las mismas que en la placa (firmware/carro_esp32/cara.h)', () {
      final h = File('firmware/carro_esp32/cara.h').readAsStringSync();
      final placa = <String, List<int>>{
        for (final m in RegExp(r"\{'(.)', \{([\d, ]+)\}\}").allMatches(h)) m.group(1)!: m.group(2)!.split(',').map((x) => int.parse(x.trim())).toList(),
      };
      expect(placa.length, greaterThan(40));
      for (final e in placa.entries) {
        expect(FaceFrame.glyph(e.key), e.value, reason: 'la letra «${e.key}»');
      }
      expect(placa.keys.toSet(), FaceFrame.glyphs.toSet(), reason: 'ni una de más ni una de menos');
    });

    test('tiene todas las letras de los mensajes del robot (antes «PARADO» salía «ARADO»)', () {
      for (final said in ['ESCRIBIENDO 3/5', 'PARADO', 'RUEDA IZQ', 'RUEDA DER', 'LAPIZ', 'LISTO', 'CLAVE?', 'NO SE ACTUALIZO', 'ACTUALIZANDO 45%', 'HOLA', 'DESCONECTADO', 'AUTO ROBOT', 'CONTROL DOMOTICA']) {
        for (final ch in said.split('')) {
          expect(ch == ' ' || FaceFrame.glyph(ch) != null, isTrue, reason: '«$ch» de «$said»');
        }
      }
    });

    int lit(FaceFrame f, {int from = 0, int to = 64}) {
      var n = 0;
      for (var y = from; y < to; y++) {
        for (var x = 0; x < 128; x++) {
          if (f.at(x, y)) n++;
        }
      }
      return n;
    }

    test('ojos abiertos, y al parpadear se cierran de a poco como en la placa', () {
      final engine = FaceEngine();
      final screens = [FaceFrame(), FaceFrame()];
      engine.drawScreens(screens);
      final open = lit(screens[0], from: 16);
      expect(open, greaterThan(1000), reason: 'un ojo grande en cada pantalla');
      expect(lit(screens[1], from: 16), open, reason: 'los dos iguales');

      engine.target = const FaceTarget(blinkL: 1, blinkR: 1);
      for (var i = 0; i < 6; i++) {
        engine.update(33);
      }
      engine.drawScreens(screens);
      expect(lit(screens[0], from: 16), lessThan(open ~/ 5), reason: 'cerrados: casi nada encendido');
    });

    test('el mensaje de la franja se ve mientras dura y después vuelven los íconos', () {
      final engine = FaceEngine();
      final screens = [FaceFrame(), FaceFrame()];
      engine.setLabel(const FaceLabel(1, 1000, 'HOLA'));
      engine.update(10);
      expect(engine.label, 'HOLA');
      engine.drawScreens(screens);
      final withLabel = lit(screens[0], to: 16);
      for (var i = 0; i < 40; i++) {
        engine.update(33);
      }
      expect(engine.label, isNull, reason: 'pasó su segundo');
      engine.setLabel(const FaceLabel(1, 1000, 'HOLA'));
      expect(engine.label, isNull, reason: 'el mismo mensaje (mismo número) no vuelve a salir');
      engine.drawScreens(screens);
      expect(lit(screens[0], to: 16), lessThan(withLabel), reason: 'sin el mensaje queda solo el ícono de conexión');
    });
  });

  test('la posición y la cara no llenan los mensajes ni redibujan toda la app', () async {
    final link = _Echo();
    final s = Session(SavedDevice(id: 'x', name: 'R', profile: Profile.carro, transport: Transport.ble), linkFor: (_) => link);
    var redraws = 0, telemetry = 0;
    s.addListener(() => redraws++);
    s.telemetry.addListener(() => telemetry++);
    await s.connect();
    final before = redraws;
    link.emitLine('V${CarPins.pose}:10,20,30');
    link.emitLine('V${CarPins.face}:0,0,0,0,100,0,0,0,0,0,0,8');
    await Future<void>.delayed(Duration.zero);
    expect(s.values[CarPins.pose], '10,20,30');
    expect(telemetry, 2);
    expect(redraws, before, reason: 'no redibuja toda la app');
    expect(s.log.where((l) => l.text.startsWith('V${CarPins.pose}')), isEmpty, reason: 'ni llena el registro');
    link.emitLine('V${CarPins.pen}:1');
    await Future<void>.delayed(Duration.zero);
    expect(redraws, greaterThan(before), reason: 'los demás pines sí, como siempre');
    await s.disconnect();
    s.dispose();
  });
}

class _Echo extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.connected);
  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);
  @override
  Future<void> sendLine(String line) async {}
}

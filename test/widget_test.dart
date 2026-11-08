import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/core/protocol.dart';
import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Protocolo', () {
    test('lee mensajes de pin virtual', () {
      final m = Msg.parse('V10:24.1');
      expect(m.pin, 10);
      expect(m.value, '24.1');
      expect(Msg.parse('V20:-40,85').value, '-40,85');
    });

    test('lee mensajes de sistema', () {
      expect(Msg.parse('PONG').kind, 'PONG');
      final ok = Msg.parse('OK:V1:23:1');
      expect(ok.kind, 'OK');
      expect(ok.value, 'V1:23:1');
      expect(ok.isPin, isFalse);
    });

    test('arma mensajes y quita saltos de línea', () {
      expect(pinMsg(6, 'Hola\nmundo'), 'V6:Hola mundo');
      expect(cfgMsg(1, 23, true), 'CFG:V1:23:1');
    });

    test('junta trozos en líneas completas', () {
      final b = LineBuffer();
      expect(b.add('V1:'), isEmpty);
      expect(b.add('1\nV2:0\nV3'), ['V1:1', 'V2:0']);
      expect(b.add(':90\n'), ['V3:90']);
    });
  });

  test('guarda y lee dispositivos con sus pines', () {
    final d = SavedDevice(id: 'x', name: 'Casa', profile: Profile.casa, transport: Transport.wifi, address: '192.168.1.40');
    d.pins[1] = const PinConfig(22, true);
    final back = SavedDevice.fromJson(d.toJson());
    expect(back.transport, Transport.wifi);
    expect(back.pins[1]!.gpio, 22);
    expect(back.pins[1]!.inverted, isTrue);
  });

  test('la placa demo responde y dispara la alarma', () async {
    final link = DemoLink('casa');
    final lines = <String>[];
    link.lines.listen(lines.add);
    await link.connect();
    expect(link.state, LinkState.connected);
    await link.sendLine('PING');
    await link.sendLine('V6:Hola');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(lines, containsAll(['PONG', 'V6:OK']));
    await link.dispose();
  });

  testWidgets('la pantalla de inicio muestra las placas demo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.load();
    await tester.pumpWidget(ControlApp(state: state));
    expect(find.text('Dispositivos'), findsOneWidget);
    expect(find.text('Casa (demo)'), findsOneWidget);
    expect(find.text('Auto Robot (demo)'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Agregar dispositivo'), findsOneWidget);
  });
}

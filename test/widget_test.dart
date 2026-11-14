import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/core/protocol.dart';
import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/controls.dart';
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
      expect(cfgMsg(1, 23, inverted: true), 'CFG:V1:23:1:1');
      expect(cfgMsg(11, 34, inverted: false, enabled: false), 'CFG:V11:34:0:0');
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
    d.pins[1] = const PinConfig(22, inverted: true, enabled: false);
    final back = SavedDevice.fromJson(d.toJson());
    expect(back.transport, Transport.wifi);
    expect(back.pins[1]!.gpio, 22);
    expect(back.pins[1]!.inverted, isTrue);
    expect(back.pins[1]!.enabled, isFalse);
  });

  test('valida los GPIO igual que la placa', () {
    expect(gpioProblem(23, output: true), isNull);
    expect(gpioProblem(34, output: false), isNull);
    expect(gpioProblem(34, output: true), isNotNull); // solo entrada
    expect(gpioProblem(7, output: true), isNotNull); // memoria interna
    expect(gpioProblem(24, output: true), isNotNull); // no existe
    expect(gpioProblem(40, output: true), isNotNull);
  });

  test('al conectar envía los pines guardados a la placa', () async {
    final d = SavedDevice(id: 'd', name: 'Casa', profile: Profile.casa, transport: Transport.demo);
    d.pins[1] = const PinConfig(22, inverted: false);
    final s = Session(d);
    await s.connect();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(s.log.map((l) => l.text), containsAll(['CFG:V1:22:0:1', 'OK:V1:22:0:1', 'SYNC']));
    await s.disconnect();
  });

  test('si la conexión se cae, reintenta sola; si el usuario desconecta, no', () async {
    final links = <_FlakyLink>[];
    final d = SavedDevice(id: 'r', name: 'Casa', profile: Profile.casa, transport: Transport.ble);
    final s = Session(d, linkFor: (_) {
      links.add(_FlakyLink());
      return links.last;
    });
    await s.connect();
    expect(s.connected, isTrue);

    links.last.drop();
    await Future<void>.delayed(Duration.zero);
    expect(s.retrying, isTrue);
    await Future<void>.delayed(Session.retryDelays.first + const Duration(milliseconds: 300));
    expect(links.length, 2);
    expect(s.connected, isTrue);

    await s.disconnect();
    await Future<void>.delayed(Session.retryDelays.first + const Duration(milliseconds: 300));
    expect(links.length, 2);
    expect(s.connected, isFalse);
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

/// Conexión de prueba que se puede tumbar a mano.
class _FlakyLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {}

  void drop() => setState(LinkState.error, 'caída simulada');
}

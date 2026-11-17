import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/models/controls.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/voice/voice_commands.dart';
import 'package:control_domotica/voice/voice_run.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VoiceCommand cmd(String phrase) {
    final r = parseCasaCommand(phrase);
    expect(r.problem, isNull, reason: phrase);
    return r.command!;
  }

  group('Frases', () {
    test('puertas', () {
      expect(cmd('Abre la puerta principal').sends, {1: 1});
      expect(cmd('abre la puerta principal').done, 'Puerta principal abierta');
      expect(cmd('cierra el portón').sends, {0: 0});
      expect(cmd('cierra el portón').done, 'Portón del garaje cerrado');
      expect(cmd('abre la puerta del baño').sends, {3: 1});
      expect(cmd('abrir puerta cuarto').sends, {4: 1});
    });

    test('luces, con o sin tildes y con sinónimos', () {
      expect(cmd('Enciende la luz de la cocina').sends, {12: 1});
      expect(cmd('prende la luz del baño').sends, {13: 1});
      expect(cmd('apaga la luz del garaje').done, 'Luz del garaje apagada');
      expect(cmd('enciende la luz de la sala').sends, {10: 1, 11: 1});
      expect(cmd('enciende la luz de la sala').done, 'Luces de la sala encendidas');
      expect(cmd('enciende la luz 2 de la sala').sends, {11: 1});
      expect(cmd('PRENDE LA COCINA').sends, {12: 1});
    });

    test('todas las luces', () {
      final c = cmd('apaga todas las luces');
      expect(c.sends, {CasaPins.allLights: 0});
      expect(c.expects.keys, unorderedEquals([10, 11, 12, 13, 14, 15]));
      expect(cmd('enciende las luces').sends, {CasaPins.allLights: 1});
    });

    test('persianas', () {
      expect(cmd('abre la persiana de la sala').sends, {5: 180});
      expect(cmd('baja la persiana del cuarto').sends, {6: 0});
      expect(cmd('pon la persiana de la sala a la mitad').sends, {5: 90});
      expect(cmd('sube la persiana del cuarto al 30 por ciento').sends, {6: 54});
      expect(cmd('abre la persiana 1 de la cocina').sends, {7: 180});
      expect(cmd('cierra las persianas de la cocina').sends, {7: 0, 8: 0});
      expect(cmd('abre la ventana de la sala').done, 'Persiana de la sala al 100 %');
    });

    test('seguridad', () {
      expect(cmd('arma la alarma').sends, {CasaPins.armed: 1});
      expect(cmd('desactiva la seguridad').sends, {CasaPins.armed: 0});
      expect(cmd('apaga la sirena').sends, {CasaPins.armed: 0});
    });

    test('lo que no entiende no mueve nada', () {
      expect(parseCasaCommand('abre la puerta').problem, '¿La puerta de qué parte de la casa?');
      expect(parseCasaCommand('hola casa').problem, isNotNull);
      expect(parseCasaCommand('').problem, 'No escuché nada.');
      expect(parseCasaCommand('abre la persiana del baño').problem, isNotNull);
    });

    test('avisa si la pieza está marcada como no conectada', () {
      final r = parseCasaCommand('abre la puerta del baño', isEnabled: (c) => c.vpin != 3);
      expect(r.problem, 'Puerta del baño está marcada como no conectada.');
    });
  });

  group('Confirmación de la placa', () {
    Future<Session> connected() async {
      final d = SavedDevice(id: 'v', name: 'Casa', profile: Profile.casa, transport: Transport.demo);
      final s = Session(d, linkFor: (_) => DemoLink('casa'));
      await s.connect();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      return s;
    }

    test('verde cuando la placa responde la orden', () async {
      final s = await connected();
      expect(await runVoiceCommand(s, cmd('abre la puerta principal')), isNull);
      expect(s.values[1], '1');
      expect(await runVoiceCommand(s, cmd('apaga todas las luces')), isNull);
      await s.disconnect();
    });

    test('rojo cuando la placa no responde', () async {
      final d = SavedDevice(id: 'm', name: 'Casa', profile: Profile.casa, transport: Transport.ble);
      final s = Session(d, linkFor: (_) => _MuteLink());
      await s.connect();
      await Future<void>.delayed(Session.claveTimeout + const Duration(milliseconds: 100));
      final problem = await runVoiceCommand(s, cmd('abre la puerta principal'), timeout: const Duration(milliseconds: 300));
      expect(problem, 'La casa no respondió.');
      await s.disconnect();
    });

    test('sin conexión no envía nada', () async {
      final d = SavedDevice(id: 'o', name: 'Casa', profile: Profile.casa, transport: Transport.demo);
      expect(await runVoiceCommand(Session(d), cmd('abre la puerta principal')), 'La casa no está conectada.');
    });
  });
}

/// Una placa conectada que nunca contesta.
class _MuteLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {}
}

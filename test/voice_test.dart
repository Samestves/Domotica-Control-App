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

  group('Frases peligrosas (auditoría del 18-nov)', () {
    test('pedir una luz nunca mueve una puerta', () {
      expect(parseCasaCommand('enciende la luz de la entrada').problem, 'En la entrada no hay luz.');
      expect(cmd('enciende la luz del portón').sends, {15: 1});
      expect(parseCasaCommand('enciende la puerta principal').problem, isNotNull);
      expect(parseCasaCommand('apaga la puerta del baño').problem, isNotNull);
    });

    test('«principal» solo es la entrada si no se nombra otro cuarto', () {
      expect(cmd('abre la puerta del cuarto principal').sends, {4: 1});
      expect(cmd('abre la puerta principal').sends, {1: 1});
    });

    test('con «no» o «menos» no se manda nada', () {
      for (final f in [
        'no abra la puerta principal',
        'no apagues la luz',
        'apaga la luz de la sala, no la de la cocina',
        'abre todas las puertas menos la principal',
        'cierra todo excepto el portón',
      ]) {
        expect(parseCasaCommand(f).command, isNull, reason: f);
      }
      expect(parseCasaCommand('no abra la puerta principal').problem, 'Dime solo lo que quieres que haga, sin «no».');
      expect(cmd('buenas noches').sends[CasaPins.armed], 1, reason: '«noches» no es «no»');
    });

    test('las frases de ambiente valen solo si son toda la orden', () {
      expect(cmd('me voy a bañar, prende la luz del baño').sends, {13: 1});
      expect(cmd('ya llegué enciende la luz del garaje').sends, {15: 1});
      expect(cmd('me voy').sends[CasaPins.armed], 1);
      expect(cmd('bueno, ya me voy').sends[CasaPins.armed], 1);
      expect(cmd('ya llegué').sends, {CasaPins.armed: 0, 10: 1, 11: 1});
      expect(parseCasaCommand('me voy a bañar').problem, isNotNull);
    });

    test('alarma: «para la noche» arma y «para la alarma» desarma', () {
      expect(cmd('arma la alarma para la noche').sends, {CasaPins.armed: 1});
      expect(cmd('para la alarma').sends, {CasaPins.armed: 0});
      expect(cmd('apaga la luz de la sala y la alarma').sends, {10: 0, 11: 0, CasaPins.armed: 0});
    });

    test('subir y bajar son de persianas; el garaje se abre con su portón', () {
      expect(cmd('sube todo').sends, {5: 180, 6: 180, 7: 180, 8: 180});
      expect(cmd('baja todo').sends, {5: 0, 6: 0, 7: 0, 8: 0});
      expect(cmd('cierra todo').sends.keys, unorderedEquals([0, 1, 2, 3, 4, 5, 6, 7, 8]), reason: 'cerrar sí incluye puertas');
      expect(cmd('abre el garaje').sends, {0: 1});
      expect(cmd('abre la entrada').sends, {1: 1});
      expect(parseCasaCommand('abre la sala').problem, isNotNull, reason: 'en la sala hay puerta y persiana: pregunta');
    });

    test('«las dos luces de la sala» son las dos', () {
      expect(cmd('enciende las dos luces de la sala').sends, {10: 1, 11: 1});
      expect(cmd('enciende la luz dos de la sala').sends, {11: 1});
    });
  });

  group('Frases', () {
    test('puertas', () {
      expect(cmd('Abre la puerta principal').sends, {1: 1});
      expect(cmd('abre la puerta principal').done, 'Puerta principal abierta');
      expect(cmd('cierra el portón').sends, {0: 0});
      expect(cmd('cierra el portón').done, 'Portón del garaje cerrado');
      expect(cmd('abre la puerta del baño').sends, {3: 1});
      expect(cmd('abrir puerta cuarto').sends, {4: 1});
      // Google a veces entiende «cierro» o «abro» en vez de «cierra» o «abre».
      expect(cmd('Cierro la puerta del garaje').sends, {0: 0});
      expect(cmd('abro la puerta de la entrada').sends, {1: 1});
      expect(cmd('prendo la luz de la cocina').sends, {12: 1});
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

    test('más formas de hablar de la alarma', () {
      expect(cmd('suena la alarma').sends, {CasaPins.siren: 1});
      expect(cmd('haz sonar la sirena').sends, {CasaPins.siren: 1});
      expect(cmd('activa la sirena').sends, {CasaPins.siren: 1});
      expect(cmd('dispara la alarma').done, 'Alarma sonando');
      expect(cmd('activa la alarma').sends, {CasaPins.armed: 1});
      expect(cmd('silencia la alarma').sends, {CasaPins.armed: 0});
      expect(parseCasaCommand('la alarma').problem, '¿Armo, desarmo o hago sonar la alarma?');
    });

    test('porcentaje como lo escribe Google', () {
      expect(cmd('abre la persiana del cuarto al 30%').sends, {6: 54});
      expect(cmd('abre la persiana del cuarto al 30%').done, 'Persiana del cuarto al 30 %');
      expect(cmd('pon la persiana de la sala a 50').sends, {5: 90});
      expect(cmd('abre un poco la persiana de la sala').sends, {5: 54});
      expect(cmd('abre la persiana de la sala al cincuenta por ciento').sends, {5: 90});
    });

    test('todas las de un tipo', () {
      expect(cmd('cierra todas las puertas').sends, {0: 0, 1: 0, 2: 0, 3: 0, 4: 0});
      expect(cmd('cierra todas las puertas').done, 'Todas las puertas cerradas');
      expect(cmd('abre las persianas').sends, {5: 180, 6: 180, 7: 180, 8: 180});
      expect(cmd('cierra todo').sends.keys, unorderedEquals([0, 1, 2, 3, 4, 5, 6, 7, 8]));
      expect(cmd('apaga todo').sends, {CasaPins.allLights: 0});
    });

    test('frases de ambiente', () {
      final night = cmd('buenas noches');
      expect(night.sends.keys.last, CasaPins.armed, reason: 'arma al final, con todo cerrado');
      expect(night.sends[CasaPins.allLights], 0);
      expect(night.sends[CasaPins.garage], 0);
      expect(cmd('me voy').done, 'Casa cerrada, luces apagadas y seguridad armada');
      expect(cmd('ya llegué').sends, {CasaPins.armed: 0, 10: 1, 11: 1});
    });
  });

  group('Varias órdenes en una frase', () {
    test('dos órdenes con «y»', () {
      final c = cmd('enciende la luz de la cocina y abre la puerta del baño');
      expect(c.sends, {12: 1, 3: 1});
      expect(c.done, 'Luz de la cocina encendida y puerta del baño abierta');
    });

    test('el lugar se toma de la otra orden', () {
      expect(cmd('enciende la luz y abre la puerta del cuarto').sends, {14: 1, 4: 1});
      expect(cmd('abre la puerta del cuarto y enciende la luz').sends, {4: 1, 14: 1});
    });

    test('la acción y la pieza se repiten', () {
      expect(cmd('abre la puerta principal y la del baño').sends, {1: 1, 3: 1});
      expect(cmd('enciende la luz de la cocina y la del baño').sends, {12: 1, 13: 1});
      expect(cmd('abre la puerta del cuarto y cierra la del baño').sends, {4: 1, 3: 0});
      expect(cmd('abre las persianas 1 y 2 de la cocina').sends, {7: 180, 8: 180});
    });

    test('tres órdenes, con comas y «luego»', () {
      final c = cmd('apaga las luces, cierra el portón y luego arma la alarma');
      expect(c.sends, {CasaPins.allLights: 0, CasaPins.garage: 0, CasaPins.armed: 1});
      expect(c.done, 'Todas las luces apagadas, portón del garaje cerrado y seguridad armada');
    });

    test('si una parte no se entiende, no se envía nada', () {
      final r = parseCasaCommand('abre la puerta principal y abre la persiana del baño');
      expect(r.command, isNull);
      expect(r.problem, 'En el baño no hay persiana.');
    });
  });

  group('Lo que no se entiende', () {
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

    test('un aviso de la placa que no es de esta orden no la hace fallar', () async {
      final d = SavedDevice(id: 'e', name: 'Casa', profile: Profile.casa, transport: Transport.ble);
      final link = _EchoLink(noise: 'ERR:sensor de la puerta 4 sin respuesta');
      final s = Session(d, linkFor: (_) => link);
      await s.connect();
      await Future<void>.delayed(Session.claveTimeout + const Duration(milliseconds: 100));
      expect(await runVoiceCommand(s, cmd('abre la puerta principal')), isNull, reason: 'el ERR no habla de V1');

      link.noise = 'ERR:V1 desactivado';
      expect(await runVoiceCommand(s, cmd('abre la puerta principal')), 'La casa respondió: V1 desactivado');
      await s.disconnect();
    });

    test('si no hay luces conectadas, «apaga todas las luces» lo dice en vez de fingir que lo hizo', () {
      final r = parseCasaCommand('apaga todas las luces', isEnabled: (c) => c.kind != ControlKind.light);
      expect(r.problem, 'No hay luces conectadas.');
    });

    test('sin conexión no envía nada', () async {
      final d = SavedDevice(id: 'o', name: 'Casa', profile: Profile.casa, transport: Transport.demo);
      expect(await runVoiceCommand(Session(d), cmd('abre la puerta principal')), 'La casa no está conectada.');
    });
  });
}

/// Una placa que primero manda un aviso ([noise]) y después confirma cada pin que recibe.
class _EchoLink extends DeviceLink {
  String noise;
  _EchoLink({required this.noise});

  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {
    if (line == 'PING') return emitLine('PONG');
    if (!line.startsWith('V')) return;
    emitLine(noise);
    if (!noise.contains(line.split(':').first)) emitLine(line); // confirma si el aviso no era sobre este pin
  }
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

// ignore_for_file: avoid_print
// Placa falsa para probar la conexión Wi‑Fi sin ESP32.
//
// Se hace pasar por la maqueta: escucha en el puerto 3333 de tu PC, responde igual
// que el programa del ESP32 y muestra en pantalla qué haría con cada mensaje.
//
// Uso (desde la carpeta del proyecto):
//   dart run tool/placa_falsa.dart
// Luego, en la app: Agregar dispositivo → Wi‑Fi → la IP que aparece aquí y el puerto 3333.
// El teléfono y la PC deben estar en la misma red Wi‑Fi.
// Pide la clave de la casa como la placa real: la primera conexión la crea y dura mientras corra el programa.
import 'dart:convert';
import 'dart:io';

import 'package:control_domotica/core/casa_sim.dart';
import 'package:control_domotica/core/protocol.dart';
import 'package:control_domotica/models/pins.dart';

const port = 3333;

/// Clave creada desde la app. Se comparte entre conexiones, como en la memoria del ESP32.
var clave = '';

const names = {
  0: 'Portón garaje', 1: 'Puerta principal', 2: 'Puerta salón', 3: 'Puerta baño', 4: 'Puerta cuarto',
  5: 'Persiana sala', 6: 'Persiana cuarto', 7: 'Persiana cocina 1', 8: 'Persiana cocina 2',
  10: 'Luz sala 1', 11: 'Luz sala 2', 12: 'Luz cocina', 13: 'Luz baño', 14: 'Luz cuarto', 15: 'Luz garaje',
};

Future<void> main() async {
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
  print('Placa falsa lista en el puerto $port.');
  for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in i.addresses) {
      print('  En la app usa la IP ${a.address}   (${i.name})');
    }
  }
  print('Esperando la app... (Ctrl+C para salir)\n');

  await for (final client in server) {
    print('App conectada desde ${client.remoteAddress.address}');
    _serve(client);
  }
}

void _serve(Socket client) {
  final sim = CasaSim((line) {
    print('  <- ${_describe(line)}');
    client.write('$line\n');
  }, usesClave: true)
    ..clave = clave;
  client.write('HELLO:Placa falsa\n');

  client.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen(
    (raw) {
      final line = raw.trim();
      if (line.isEmpty) return;
      // La clave no se muestra en pantalla.
      print('-> ${line.replaceAllMapped(RegExp(r'^(AUTH|CLAVE):.*'), (m) => '${m[1]}:••••')}');
      sim.handle(line);
      clave = sim.clave;
    },
    onDone: () {
      sim.dispose();
      print('App desconectada\n');
    },
    onError: (_) => sim.dispose(),
  );
}

/// Traduce una respuesta de la placa a algo legible, por ejemplo «V10:1  [Luz sala 1 ENCENDIDA]».
String _describe(String line) {
  final m = Msg.parse(line);
  final pin = m.pin;
  if (pin == null) return line;
  final name = names[pin];
  final what = switch (pin) {
    _ when CasaPins.doors.contains(pin) => '$name ${m.value == '1' ? 'ABIERTA' : 'cerrada'}',
    _ when CasaPins.blinds.contains(pin) => '$name a ${m.value} grados',
    _ when CasaPins.lights.contains(pin) => '$name ${m.value == '1' ? 'ENCENDIDA' : 'apagada'}',
    CasaPins.siren => m.value == '1' ? 'SIRENA SONANDO' : 'sirena apagada',
    CasaPins.armed => m.value == '1' ? 'seguridad armada' : 'seguridad desarmada',
    _ => null,
  };
  return what == null ? line : '$line  [$what]';
}

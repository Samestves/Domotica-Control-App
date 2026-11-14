// ignore_for_file: avoid_print
// Placa falsa para probar la conexión Wi‑Fi sin ESP32.
//
// Se hace pasar por la maqueta: escucha en el puerto 3333 de tu PC, responde como
// el ESP32 y muestra en pantalla qué haría con cada mensaje.
//
// Uso (desde la carpeta del proyecto):
//   dart run tool/placa_falsa.dart
// Luego, en la app: Agregar dispositivo → Wi‑Fi → la IP que aparece aquí y el puerto 3333.
// El teléfono y la PC deben estar en la misma red Wi‑Fi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const port = 3333;

final names = {
  1: 'Luz sala',
  2: 'Luz cocina',
  8: 'Luz cuarto',
  9: 'Ventilador',
  3: 'Puerta (servo)',
  4: 'Ventana (servo)',
  5: 'Timbre',
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
  final rnd = Random();
  var temp = 24.0;
  var armed = false;
  Timer? alarm;
  void send(String l) {
    print('  <- $l');
    client.write('$l\n');
  }

  send('HELLO:Placa falsa');
  final tick = Timer.periodic(const Duration(seconds: 4), (_) {
    temp += (rnd.nextDouble() - .5) * .4;
    send('V10:${temp.toStringAsFixed(1)}');
  });

  client.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((raw) {
    final line = raw.trim();
    if (line.isEmpty) return;
    print('-> $line');
    if (line == 'PING') return send('PONG');
    if (line == 'TEST') return send('OK:TEST terminado');
    if (line == 'SYNC') return send('V7:${armed ? 1 : 0}');
    if (line.startsWith('CFG:')) return send('OK:${line.substring(4)}');
    final m = RegExp(r'^V(\d+):(.*)$').firstMatch(line);
    if (m == null) return send('ERR:no entiendo $line');
    final pin = int.parse(m.group(1)!);
    final val = m.group(2)!;
    switch (pin) {
      case 6:
        print('  [LCD] "$val"');
        send('V6:OK');
      case 7:
        armed = val == '1';
        alarm?.cancel();
        print('  [Alarma] ${armed ? 'armada' : 'desarmada'}');
        if (armed) {
          alarm = Timer(const Duration(seconds: 6), () {
            send('V11:1');
            send('V7:DISPARO');
          });
        } else {
          send('V11:0');
        }
      default:
        final what = names[pin] ?? 'V$pin';
        final desc = switch (pin) {
          3 || 4 => 'a $val grados',
          5 => 'suena',
          _ => val == '1' ? 'ENCENDIDA' : 'apagada',
        };
        print('  [$what] $desc');
    }
  }, onDone: () {
    tick.cancel();
    alarm?.cancel();
    print('App desconectada\n');
  }, onError: (_) {
    tick.cancel();
    alarm?.cancel();
  });
}

/// Protocolo de texto entre la app y las placas.
///
/// Cada mensaje es una línea terminada en `\n`.
///
/// App → placa:
///   `V1:1`            pin virtual 1 con valor 1
///   `V20:-40,85`      joystick (x,y)
///   `CFG:V1:23:1:1`   el pin virtual 1 usa el GPIO 23, invertido y activado
///   `SYNC`            la placa responde con el estado actual de todo
///   `TEST`            la placa activa cada salida una por una
///   `PING`
///   `AUTH:123456`     entrega la clave de la casa (vacía si la app todavía no la conoce)
///   `CLAVE:123456`    crea la clave, o la cambia si ya se entregó la actual
///
/// Placa → app:
///   `V10:24.1`        lectura de un sensor
///   `V7:DISPARO`      alarma
///   `HELLO:<nombre>`  saludo al conectar
///   `AUTH:OK`         clave correcta (o recién creada)
///   `AUTH:MAL:2`      clave incorrecta; quedan 2 intentos
///   `AUTH:ESPERA:30`  demasiados intentos; esperar 30 s
///   `AUTH:NUEVA`      la casa no tiene clave todavía
///   `AUTH:PIDE`       hace falta la clave
///   `PONG`, `OK:<texto>`, `ERR:<texto>`
///
/// Una placa que no conoce `AUTH` (el carrito, o una versión anterior) responde `ERR` o nada:
/// la app entiende que esa placa no usa clave.
library;

class Msg {
  final String raw;
  final int? pin;
  final String value;
  final String? kind; // HELLO, PONG, OK, ERR, CFG, TEST...

  const Msg._(this.raw, {this.pin, this.value = '', this.kind});

  bool get isPin => pin != null;

  static Msg parse(String line) {
    final l = line.trim();
    final m = RegExp(r'^V(\d{1,3}):(.*)$').firstMatch(l);
    if (m != null) {
      return Msg._(l, pin: int.parse(m.group(1)!), value: m.group(2)!);
    }
    final i = l.indexOf(':');
    if (i > 0) return Msg._(l, kind: l.substring(0, i).toUpperCase(), value: l.substring(i + 1));
    return Msg._(l, kind: l.toUpperCase());
  }

  @override
  String toString() => raw;
}

String pinMsg(int pin, Object value) => 'V$pin:${clean(value.toString())}';

String cfgMsg(int pin, int gpio, {required bool inverted, bool enabled = true}) =>
    'CFG:V$pin:$gpio:${inverted ? 1 : 0}:${enabled ? 1 : 0}';

/// La clave de la casa: de 4 a 8 números, igual que en la placa.
bool validClave(String c) => RegExp(r'^\d{4,8}$').hasMatch(c);

/// Quita saltos de línea para que un texto no rompa el protocolo.
String clean(String s) => s.replaceAll(RegExp(r'[\r\n]'), ' ');

/// Junta trozos de texto y entrega líneas completas.
class LineBuffer {
  final StringBuffer _buf = StringBuffer();

  List<String> add(String chunk) {
    _buf.write(chunk);
    final text = _buf.toString();
    final parts = text.split('\n');
    _buf
      ..clear()
      ..write(parts.removeLast());
    return parts.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  }
}

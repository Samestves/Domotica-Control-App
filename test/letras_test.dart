import 'dart:convert';
import 'dart:io';

import 'package:control_domotica/models/letras.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la tabla de letras de la app es la misma que dibuja el robot (firmware/carro_esp32/letras.h)', () {
    final h = File('firmware/carro_esp32/letras.h').readAsStringSync();
    final placa = <String, String>{};
    for (final m in RegExp(r'\{"((?:[^"\\]|\\x[0-9A-Fa-f]{2})+)", "([^"]*)"\}').allMatches(h)) {
      // «\xC3\x91» en C es la Ñ en UTF-8.
      final bytes = <int>[];
      final raw = m.group(1)!;
      for (var i = 0; i < raw.length;) {
        if (raw.startsWith(r'\x', i)) {
          bytes.add(int.parse(raw.substring(i + 2, i + 4), radix: 16));
          i += 4;
        } else {
          bytes.add(raw.codeUnitAt(i++));
        }
      }
      placa[utf8.decode(bytes)] = m.group(2)!;
    }
    expect(placa, Letras.tabla);
    expect(h, contains('LETRA_ANCHO = ${Letras.ancho}, LETRA_ALTO = ${Letras.alto}, LETRA_ESPACIO = ${Letras.espacio}'));
    expect(File('firmware/carro_esp32/escritura.h').readAsStringSync(), contains('ESCRITURA_MAX = ${Letras.maxLetras};'));
  });

  test('el texto se deja como lo dibuja el robot', () {
    expect(Letras.normalizar('Hola, mundo!'), 'HOLA, MUNDO!');
    expect(Letras.normalizar('  ñandú  '), 'ÑANDU', reason: 'sin tildes, con Ñ y sin espacios en las puntas');
    expect(Letras.normalizar('A@#B'), 'AB', reason: 'lo que no tiene se salta, como en la placa');
    expect(Letras.normalizar('X' * 40).length, Letras.maxLetras);
    expect(Letras.contar('HOLA MUNDO'), 9, reason: 'el espacio no cuenta como letra');
  });

  test('cada trazo de cada letra se lee y queda dentro de su cuadrícula', () {
    for (final e in Letras.tabla.entries) {
      for (final trazo in Letras.trazos(e.key)) {
        expect(trazo, isNotEmpty, reason: e.key);
        for (final (x, y) in trazo) {
          expect(x, inInclusiveRange(0, Letras.ancho), reason: e.key);
          expect(y, inInclusiveRange(-1, Letras.alto + 1), reason: e.key);
        }
      }
    }
    expect(Letras.trazos('A'), [
      [(0.0, 0.0), (2.0, 6.0), (4.0, 0.0)],
      [(1.0, 3.0), (3.0, 3.0)],
    ]);
  });
}

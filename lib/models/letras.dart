/// Letras de un solo trazo: las que dibuja el robot con el marcador. Es la misma tabla de
/// firmware/carro_esp32/letras.h (test/letras_test.dart revisa que sean iguales), así la vista previa de la
/// app muestra exactamente lo que va a dibujar.
///
/// Cada letra vive en una cuadrícula de [ancho] × [alto] (la Ñ y la coma salen un poco), con y hacia arriba.
/// Un trazo es una lista de puntos «x,y» separados por espacios; los trazos se separan con «|».
class Letras {
  static const ancho = 4, alto = 6, espacio = 2;

  /// Letras por texto, contando los espacios (como ESCRITURA_MAX en la placa).
  static const maxLetras = 24;

  static const tabla = <String, String>{
    'A': '0,0 2,6 4,0|1,3 3,3',
    'B': '0,3 3,3 4,4 4,5 3,6 0,6 0,0 3,0 4,1 4,2 3,3',
    'C': '4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1',
    'D': '0,0 0,6 2,6 4,4 4,2 2,0 0,0',
    'E': '4,6 0,6 0,0 4,0|0,3 3,3',
    'F': '4,6 0,6 0,0|0,3 3,3',
    'G': '4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,3 2,3',
    'H': '0,6 0,0|0,3 4,3|4,6 4,0',
    'I': '1,6 3,6|2,6 2,0|1,0 3,0',
    'J': '4,6 4,1 3,0 1,0 0,1',
    'K': '0,6 0,0|4,6 0,2|1,3 4,0',
    'L': '0,6 0,0 4,0',
    'M': '0,0 0,6 2,3 4,6 4,0',
    'N': '0,0 0,6 4,0 4,6',
    'Ñ': '0,0 0,5 4,0 4,5|0,6 1,7 3,6 4,7',
    'O': '1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0',
    'P': '0,0 0,6 3,6 4,5 4,4 3,3 0,3',
    'Q': '1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0|2,2 4,0',
    'R': '0,0 0,6 3,6 4,5 4,4 3,3 0,3|2,3 4,0',
    'S': '4,5 3,6 1,6 0,5 0,4 1,3 3,3 4,2 4,1 3,0 1,0 0,1',
    'T': '0,6 4,6|2,6 2,0',
    'U': '0,6 0,1 1,0 3,0 4,1 4,6',
    'V': '0,6 2,0 4,6',
    'W': '0,6 1,0 2,4 3,0 4,6',
    'X': '0,0 4,6|0,6 4,0',
    'Y': '0,6 2,3 4,6|2,3 2,0',
    'Z': '0,6 4,6 0,0 4,0',
    '0': '1,0 0,1 0,5 1,6 3,6 4,5 4,1 3,0 1,0|0,1 4,5',
    '1': '1,5 2,6 2,0|1,0 3,0',
    '2': '0,5 1,6 3,6 4,5 4,4 0,0 4,0',
    '3': '0,5 1,6 3,6 4,5 4,4 3,3 1,3|3,3 4,2 4,1 3,0 1,0 0,1',
    '4': '3,0 3,6 0,2 4,2',
    '5': '4,6 0,6 0,3 3,3 4,2 4,1 3,0 0,0',
    '6': '4,5 3,6 1,6 0,5 0,1 1,0 3,0 4,1 4,2 3,3 0,3',
    '7': '0,6 4,6 1,0',
    '8': '1,3 0,4 0,5 1,6 3,6 4,5 4,4 3,3 1,3 0,2 0,1 1,0 3,0 4,1 4,2 3,3',
    '9': '4,3 1,3 0,4 0,5 1,6 3,6 4,5 4,1 3,0 1,0 0,1',
    '.': '2,0',
    ',': '2,0 1,-1',
    '!': '2,6 2,2|2,0',
    '?': '0,5 1,6 3,6 4,5 4,4 2,3 2,2|2,0',
    '-': '1,3 3,3',
    '+': '2,1 2,5|0,3 4,3',
    ':': '2,1|2,4',
    ' ': '',
  };

  static const _sinTilde = {'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U'};

  /// Lo que el robot va a dibujar de [texto]: mayúsculas sin tildes (la Ñ sí), solo los caracteres que tiene,
  /// sin espacios en las puntas y como mucho [maxLetras].
  static String normalizar(String texto) {
    final out = StringBuffer();
    for (final ch in texto.toUpperCase().split('')) {
      final c = _sinTilde[ch] ?? ch;
      if (tabla.containsKey(c)) out.write(c);
    }
    final s = out.toString().trim();
    return s.length > maxLetras ? s.substring(0, maxLetras).trimRight() : s;
  }

  /// Cuántas letras dibuja (los espacios no cuentan): la placa avisa «letra 3 de 5» con este total.
  static int contar(String texto) => normalizar(texto).split('').where((c) => tabla[c]!.isNotEmpty).length;

  /// Los trazos de una letra, en cuadros: cada trazo es una lista de puntos (x, y), con y hacia arriba.
  static List<List<(double, double)>> trazos(String letra) {
    final spec = tabla[letra] ?? '';
    if (spec.isEmpty) return const [];
    return [
      for (final trazo in spec.split('|'))
        [
          for (final punto in trazo.trim().split(' '))
            (double.parse(punto.split(',')[0]), double.parse(punto.split(',')[1])),
        ],
    ];
  }
}

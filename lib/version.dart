/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.10';
const appBuild = 30;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'Arreglo: en el robot, el teclado para escribir se cerraba al instante. Ahora se queda abierto y se puede escribir.',
  'El robot escribe: tecleas una palabra, ves cómo la va a dibujar y la escribe con el marcador (desde la 0.9.9).',
  'Tablero nuevo para el robot y sus ajustes: ruedas, lápiz y medidas, para que las letras salgan del tamaño justo.',
  'Actualizar una placa por Wi-Fi ya no se da por fallida si la placa tarda en volver.',
  'Invertir una puerta (con casa-1.1) cambia abrir por cerrar y no empuja contra la pared.',
];

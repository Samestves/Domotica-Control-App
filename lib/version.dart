/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.9';
const appBuild = 29;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'El robot escribe: tecleas una palabra, ves cómo la va a dibujar y la escribe con el marcador, letra por letra.',
  'Tablero nuevo para el robot: manejar, escribir, lápiz y parar, cada uno en su tarjeta.',
  'Los ajustes del robot: sus dos ruedas, el lápiz y sus medidas, para que las letras salgan del tamaño justo.',
  'Actualizar una placa por Wi-Fi ya no se da por fallida si la placa tarda en volver, y el aviso no se pierde sin internet.',
  'Invertir una puerta (con casa-1.1) cambia abrir por cerrar: dice lo que de verdad hace y no empuja contra la pared.',
];

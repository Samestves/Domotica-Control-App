/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.11';
const appBuild = 31;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'El robot con dos tableros: Manejar (joystick, acelerador, reversa, velocidad lenta, lápiz y parar) y Escribir.',
  'La hoja en vivo: pones el robot en la esquina, tocas 0,0 y ves dónde está y lo que dibuja. No sale del papel.',
  'Toca la hoja e «Ir aquí»: el robot va a ese punto y queda derecho para escribir. Avisa si el texto no cabe.',
  'La cara del robot en vivo, como en sus pantallas (con carro-0.7).',
  'En los créditos, Victoria Santodomingo y Karlibet Vega.',
];

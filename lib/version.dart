/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.5';
const appBuild = 25;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'Lista para la casa con el módulo PCA9685 (casa-0.8): en puertas y persianas, la hoja de pines pide el canal del módulo.',
  'Los ajustes viejos de los servos pasan solos a su canal, sin perder invertir ni activar.',
  'Los GPIO 21 y 22 quedan reservados para el módulo (SDA y SCL).',
];

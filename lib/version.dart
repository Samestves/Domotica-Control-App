/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.2';
const appBuild = 22;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'Al actualizar, esta hoja cuenta qué trae la versión nueva. También se puede ver en Ajustes, dentro de «Acerca de».',
  '«Cambiar la clave» ahora también aparece al mantener presionado un dispositivo en el inicio.',
  'Al cambiar la clave, la app espera a que la placa la confirme y avisa si no se pudo.',
];

/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.8';
const appBuild = 28;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'Diseño más limpio: el estado de cada placa va en una pastilla, sin puntitos ni textos repetidos.',
  'Las opciones de cada placa, a la vista en su botón «⋯»: ya no hace falta mantenerla presionada.',
  'Escenas en la casa: «Buenas noches», «Me voy» y «Ya llegué» en un toque.',
  'El carrito muestra en grande qué está haciendo, y la pantalla no se apaga mientras se usa un panel.',
  'Los créditos del equipo, a la vista: al final del inicio y en Ajustes.',
];

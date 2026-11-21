/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.4';
const appBuild = 24;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'Inicio más limpio: toca una tarjeta para entrar, mantenla presionada para ver sus opciones y agrega placas al final de la lista.',
  'Ahora se puede cambiar el nombre de un dispositivo desde sus opciones.',
  'En la casa, las luces y puertas se prenden tocando su tarjeta, y la seguridad avisa si una entrada quedó abierta antes de armar.',
  'En el carrito, la distancia al obstáculo es una barra que se llena y se pone roja al acercarse.',
  'Al agregar un dispositivo, el nombre es opcional. El registro de mensajes queda en el modo técnico.',
];

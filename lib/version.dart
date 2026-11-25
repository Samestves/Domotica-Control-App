/// Versión que se muestra en la app. Mantener igual a `version` en pubspec.yaml.
const appVersion = 'Alpha 0.9.7';
const appBuild = 27;

/// Qué trae esta versión. La app lo muestra una vez al abrirla después de actualizar (y en Ajustes → Acerca de),
/// y tool/publicar.ps1 lo usa como descripción de la Release en GitHub. Una frase corta por punto.
const appNews = [
  'Arreglo: la 0.9.6 se cerraba al abrirla. Esta trae todo lo de la 0.9.6, ya probada en un teléfono.',
  'Actualiza el programa de la casa y del carrito por Wi-Fi, desde la app. Funciona desde casa-0.9 y carro-0.5, que se instalan una vez por cable.',
  'Avisos: la app te avisa cuando hay una versión nueva de la app o de tus placas, aunque esté cerrada. Se apagan en Ajustes.',
  'En las opciones de cada placa (mantén presionada su tarjeta) se ve la versión de su programa.',
  'El carrito ya puede llevar su pantalla con cara: los GPIO 21 y 22 quedan para ella.',
];

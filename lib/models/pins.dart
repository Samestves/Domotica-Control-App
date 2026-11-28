/// Pines virtuales de la maqueta. Son los mismos números que usaba el grupo en Blynk,
/// así su documento «Conexiones GPIO» sigue valiendo.
class CasaPins {
  static const doors = [0, 1, 2, 3, 4]; // 1 = abrir, 0 = cerrar
  static const blinds = [5, 6, 7, 8]; // 0..180
  static const lights = [10, 11, 12, 13, 14, 15]; // 1 / 0
  static const garage = 0, mainDoor = 1;
  static const siren = 9; // 1 = sonar a mano, 0 = apagar y desarmar
  static const allLights = 16;
  static const armed = 17;
  static const notice = 18; // avisos de texto de la placa
  static const blindMax = 180;
}

/// Pines virtuales del carro.
class CarPins {
  static const joystick = 20, turret = 21, distance = 22, lights = 23, throttle = 24, reverse = 25, horn = 26;

  /// Invertidos, un 0/1 por pieza. El carrito 4x4 (carro-0.5): cuatro ruedas DI, TI, DD, TD («0100»).
  /// El robot (desde carro-0.6): rueda izquierda, rueda derecha y lápiz («010»). La placa lo guarda.
  static const invert = 27;

  /// Robot que escribe (desde carro-0.6). La placa dice V28 al conectarse: así la app sabe que es el robot.
  /// Lápiz: 1 = abajo (marca), 0 = arriba.
  static const pen = 28;

  /// Trabajo del robot: «3/5» = escribiendo, va en la letra 3 de 5; «ir» = yendo a un punto (carro-0.7);
  /// «0» = nada.
  static const writing = 29;

  /// Medidas «rueda,eje,letra,lapiz»: mm, mm, mm y ms (ej.: «65,120,30,1000»). La placa las guarda.
  static const measures = 30;

  /// Desde carro-0.7. Dónde está el robot: «x,y,a» en mm y grados desde el 0,0 (CERO); «-» = sin 0,0.
  static const pose = 31;

  /// La hoja: «ancho,alto» en mm; «0,0» = sin hoja. Con hoja y 0,0, el robot no sale del papel.
  static const paper = 32;

  /// La cara, para verla en la app (CARA:1): lo que muestran los ojos, y el mensaje de la franja de arriba.
  static const face = 33, faceLabel = 34;

  /// Mientras el carro anda, la app repite la orden con esta frecuencia.
  /// Si la placa deja de recibirla por 1 s (Bluetooth cortado, app cerrada), frena sola.
  static const keepAlive = Duration(milliseconds: 200);
}

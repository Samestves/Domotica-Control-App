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

  /// Ruedas invertidas: cuatro 0/1 en orden DI, TI, DD, TD (ej.: «0100»). La placa lo guarda.
  static const invert = 27;

  /// Mientras el carro anda, la app repite la orden con esta frecuencia.
  /// Si la placa deja de recibirla por 1 s (Bluetooth cortado, app cerrada), frena sola.
  static const keepAlive = Duration(milliseconds: 200);
}

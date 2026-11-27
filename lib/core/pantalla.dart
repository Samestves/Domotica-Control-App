import 'package:flutter/services.dart';

/// Pantalla siempre encendida mientras se usa un panel: si se apagara en plena demo, el carrito frenaría
/// (deja de recibir señal) y la casa dejaría de verse. Al salir del panel vuelve a apagarse sola, como siempre.
class Pantalla {
  static const _ch = MethodChannel('control_domotica/app');

  static Future<void> encendida(bool on) async {
    try {
      await _ch.invokeMethod('pantallaEncendida', {'encendida': on});
    } catch (_) {
      // en las pruebas no hay Android; en el teléfono, si no se puede, la app sigue igual
    }
  }
}

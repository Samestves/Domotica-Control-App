import 'package:flutter/services.dart';

/// Notificaciones del teléfono, todas locales: sin servidor ni cuentas (ver MainActivity.kt y RevisarVersiones.kt).
///
/// - Cada 12 horas, aunque la app esté cerrada, Android corre una revisión: si hay una versión nueva de la app o del
///   programa de una placa guardada, avisa una sola vez por versión.
/// - Al terminar de actualizar una placa con la app en segundo plano, avisa cómo salió.
class Avisos {
  static const _ch = MethodChannel('control_domotica/avisos');

  /// Programa la revisión cada 12 horas (con internet), o la quita. Repetirlo no reinicia la espera.
  static Future<void> schedule(bool on) => _call<void>('programar', {'activos': on});

  /// Desde Android 13 avisar necesita permiso: lo pide (una ventanita de Android). true si se puede avisar.
  static Future<bool> askPermission() async => await _call<bool>('pedirPermiso') ?? false;

  /// Muestra un aviso ahora mismo.
  static Future<void> show(String title, String text) => _call<void>('mostrar', {'titulo': title, 'texto': text});

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // en las pruebas no hay Android
    } on PlatformException {
      return null; // avisar es un extra: si el teléfono no deja, la app sigue igual
    }
  }
}

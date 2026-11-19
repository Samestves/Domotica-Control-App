import 'package:flutter/services.dart';

/// Una red Wi-Fi que el teléfono ve cerca.
class WifiNetwork {
  final String ssid;

  /// Señal en dBm: −40 es excelente, −85 es muy débil.
  final int level;
  final bool secure;
  final int ghz;
  const WifiNetwork(this.ssid, {required this.level, this.secure = true, this.ghz = 2});

  /// 1 a 3 rayitas.
  int get bars => level > -60 ? 3 : (level > -75 ? 2 : 1);

  /// Red propia de una placa con nuestro programa («Casa Domotica», «Carrito 4x4»...).
  bool get isBoard => WifiNet.isBoardSsid(ssid);
}

/// Problema al usar el Wi-Fi, con un mensaje listo para mostrar.
class WifiProblem implements Exception {
  final String code;
  final String message;
  const WifiProblem(this.code, this.message);

  bool get wifiOff => code == 'wifi_apagado';
  bool get locationOff => code == 'ubicacion_apagada';
  bool get noPermission => code == 'sin_permiso' || code == 'permiso';

  @override
  String toString() => message;
}

/// Wi-Fi del teléfono: buscar redes y unirse a la red propia de la placa (ver MainActivity.kt).
class WifiNet {
  static const _ch = MethodChannel('control_domotica/red');

  /// Nombre y contraseña de fábrica de la red que crea el ESP32 de la casa.
  static const boardSsid = 'Casa Domotica';
  static const boardPass = 'casadomotica';
  static const boardIp = '192.168.4.1';
  static const boardPort = 3333;

  /// Contraseña de fábrica de la red de cada placa (la casa y el carrito).
  static String defaultPass(String ssid) => ssid.toLowerCase().startsWith('carrito') ? 'carrito4x4' : boardPass;

  static bool isBoardSsid(String ssid) {
    final s = ssid.toLowerCase();
    return s == boardSsid.toLowerCase() || s.startsWith('casa domotica') || s.startsWith('carrito') || s.startsWith('esp32');
  }

  /// Pide el permiso para ver las redes cercanas (Android lo pregunta una vez).
  static Future<bool> permission() async {
    try {
      return await _ch.invokeMethod<bool>('permisoWifi') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Busca redes. Las de las placas van primero; después, de mejor a peor señal.
  static Future<List<WifiNetwork>> scan() async {
    if (!await permission()) {
      throw const WifiProblem(
          'permiso', 'Para mostrar las redes Wi-Fi, Android pide el permiso de ubicación. La app no usa ni guarda dónde estás.');
    }
    try {
      final raw = await _ch.invokeListMethod<Map<dynamic, dynamic>>('redesWifi') ?? [];
      final list = [
        for (final r in raw)
          WifiNetwork(r['ssid'] as String, level: r['nivel'] as int, secure: r['segura'] as bool? ?? true, ghz: r['ghz'] as int? ?? 2),
      ];
      list.sort((a, b) => a.isBoard == b.isBoard ? b.level.compareTo(a.level) : (a.isBoard ? -1 : 1));
      return list;
    } on PlatformException catch (e) {
      throw WifiProblem(e.code, e.message ?? 'No se pudo buscar redes Wi-Fi.');
    } on MissingPluginException {
      throw const WifiProblem('sin_wifi', 'Este teléfono no permite buscar redes Wi-Fi.');
    }
  }

  /// Une la app a la red de la placa. Android muestra una ventanita para confirmar.
  static Future<void> connect(String ssid, String password) async {
    try {
      await _ch.invokeMethod('conectarRed', {'ssid': ssid, 'clave': password});
    } on PlatformException catch (e) {
      throw WifiProblem(e.code, e.message ?? 'No se pudo unir a «$ssid».');
    } on MissingPluginException {
      throw const WifiProblem('sin_wifi', 'Este teléfono no permite unirse a redes desde la app.');
    }
  }

  /// La red de placa a la que la app está unida ahora, o null.
  static Future<String?> joined() async {
    try {
      return await _ch.invokeMethod<String>('redPlaca');
    } catch (_) {
      return null;
    }
  }

  /// Deja la red de la placa: el teléfono vuelve a su Wi-Fi o a los datos móviles.
  static Future<void> release() async {
    try {
      await _ch.invokeMethod('soltarRed');
    } catch (_) {}
  }

  static Future<void> openLocationSettings() async {
    try {
      await _ch.invokeMethod('ajustesUbicacion');
    } catch (_) {}
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('ajustesWifi');
    } catch (_) {}
  }
}

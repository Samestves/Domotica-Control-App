enum Transport { ble, wifi, demo }

enum Profile { casa, carro }

extension TransportLabel on Transport {
  String get label => switch (this) {
        Transport.ble => 'Bluetooth',
        Transport.wifi => 'Wi-Fi',
        Transport.demo => 'Demo',
      };
}

extension ProfileLabel on Profile {
  String get label => switch (this) {
        Profile.casa => 'Casa Domótica',
        Profile.carro => 'Auto Robot',
      };
}

/// Ajuste de un control: a qué pin va, si está invertido y si está conectado en la maqueta.
/// Luces y sirena: [gpio] es el GPIO del ESP32. Puertas y persianas ([pca]): es el canal del módulo PCA9685
/// (desde casa-0.8). Un ajuste de servo guardado antes de eso no tiene [pca] y su GPIO ya no sirve.
class PinConfig {
  final int gpio;
  final bool inverted;
  final bool enabled;
  final bool pca;
  const PinConfig(this.gpio, {required this.inverted, this.enabled = true, this.pca = false});

  /// Lo que viaja en CFG: el GPIO, o 100 + el canal del PCA9685.
  int get code => pca ? 100 + gpio : gpio;

  Map<String, dynamic> toJson() => {'g': gpio, 'i': inverted, 'e': enabled, if (pca) 'p': true};
  factory PinConfig.fromJson(Map<String, dynamic> j) => PinConfig(j['g'] as int,
      inverted: j['i'] as bool? ?? false, enabled: j['e'] as bool? ?? true, pca: j['p'] as bool? ?? false);
}

/// Una placa guardada en el teléfono.
class SavedDevice {
  final String id;
  String name;
  Profile profile;
  Transport transport;

  /// Bluetooth: identificador de la placa. Wi-Fi: IP. Demo: vacío.
  String address;
  int port;
  String board;
  Map<int, PinConfig> pins; // pin virtual → ajuste

  /// Clave de la casa que aceptó la placa, para entregarla sola al conectar. null = no se conoce.
  String? clave;

  /// Wi-Fi propio de la placa: la app se une sola a esta red antes de conectar. null = la red que tenga el teléfono.
  String? ssid;
  String? wifiPass;

  /// Versión del programa de la placa (`casa-0.9`), la última vez que lo dijo al conectarse. null = no se sabe:
  /// las versiones anteriores a casa-0.9 y carro-0.5 no la dicen (y tampoco se actualizan por Wi-Fi).
  String? firmware;

  SavedDevice({
    required this.id,
    required this.name,
    required this.profile,
    required this.transport,
    this.address = '',
    this.port = 3333,
    this.board = 'ESP32',
    Map<int, PinConfig>? pins,
    this.clave,
    this.ssid,
    this.wifiPass,
    this.firmware,
  }) : pins = pins ?? {};

  String get subtitle => switch (transport) {
        Transport.ble => '$board · Bluetooth',
        Transport.wifi => ssid == null ? '$board · $address' : '$board · red «$ssid»',
        Transport.demo => 'Placa simulada',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'profile': profile.name,
        'transport': transport.name,
        'address': address,
        'port': port,
        'board': board,
        'pins': pins.map((k, v) => MapEntry('$k', v.toJson())),
        if (clave != null) 'clave': clave,
        if (ssid != null) 'ssid': ssid,
        if (wifiPass != null) 'wifiPass': wifiPass,
        if (firmware != null) 'firmware': firmware,
      };

  factory SavedDevice.fromJson(Map<String, dynamic> j) => SavedDevice(
        id: j['id'] as String,
        name: j['name'] as String,
        profile: Profile.values.byName(j['profile'] as String),
        transport: Transport.values.byName(j['transport'] as String),
        address: j['address'] as String? ?? '',
        port: j['port'] as int? ?? 3333,
        board: j['board'] as String? ?? 'ESP32',
        pins: ((j['pins'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(int.parse(k), PinConfig.fromJson(v as Map<String, dynamic>))),
        clave: j['clave'] as String?,
        ssid: j['ssid'] as String?,
        wifiPass: j['wifiPass'] as String?,
        firmware: j['firmware'] as String?,
      );
}

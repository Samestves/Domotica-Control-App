enum Transport { ble, wifi, demo }

enum Profile { casa, carro }

extension TransportLabel on Transport {
  String get label => switch (this) {
        Transport.ble => 'Bluetooth',
        Transport.wifi => 'Wi‑Fi',
        Transport.demo => 'Demo',
      };
}

extension ProfileLabel on Profile {
  String get label => switch (this) {
        Profile.casa => 'Casa Domótica',
        Profile.carro => 'Auto Robot',
      };
}

/// Ajuste de un control: a qué GPIO va, si está invertido y si está conectado en la maqueta.
class PinConfig {
  final int gpio;
  final bool inverted;
  final bool enabled;
  const PinConfig(this.gpio, {required this.inverted, this.enabled = true});

  Map<String, dynamic> toJson() => {'g': gpio, 'i': inverted, 'e': enabled};
  factory PinConfig.fromJson(Map<String, dynamic> j) =>
      PinConfig(j['g'] as int, inverted: j['i'] as bool? ?? false, enabled: j['e'] as bool? ?? true);
}

/// Una placa guardada en el teléfono.
class SavedDevice {
  final String id;
  String name;
  Profile profile;
  Transport transport;

  /// Bluetooth: identificador de la placa. Wi‑Fi: IP. Demo: vacío.
  String address;
  int port;
  String board;
  Map<int, PinConfig> pins; // pin virtual → ajuste

  SavedDevice({
    required this.id,
    required this.name,
    required this.profile,
    required this.transport,
    this.address = '',
    this.port = 3333,
    this.board = 'ESP32',
    Map<int, PinConfig>? pins,
  }) : pins = pins ?? {};

  String get subtitle => switch (transport) {
        Transport.ble => '$board · Bluetooth',
        Transport.wifi => '$board · $address',
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
      );
}

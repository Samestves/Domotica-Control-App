import 'device.dart';
import 'pins.dart';

export 'pins.dart';

enum ControlKind { light, door, blind }

/// Un control del panel Casa. El número de pin virtual (V0, V10…) es lo que viaja en el mensaje
/// y es el mismo que usaba el grupo en Blynk. `gpio` es el pin de fábrica: en las luces, el GPIO del ESP32;
/// en puertas y persianas, el canal del módulo PCA9685 (desde casa-0.8), que es su mismo pin virtual.
class ControlSpec {
  final int vpin;
  final String label;
  final String room;
  final ControlKind kind;
  final int gpio;
  final bool inverted; // por defecto; los módulos de relé se activan con señal baja
  final bool enabled; // por defecto; false si la pieza puede no estar en la maqueta

  const ControlSpec({
    required this.vpin,
    required this.label,
    required this.room,
    required this.kind,
    required this.gpio,
    this.inverted = false,
    this.enabled = true,
  });

  bool get isGarage => vpin == CasaPins.garage;

  /// Puertas y persianas van en el módulo PCA9685, no en un GPIO.
  bool get onPca => kind == ControlKind.door || kind == ControlKind.blind;
}

/// Cableado de la maqueta del grupo. Luces: su documento «Conexiones GPIO». Puertas y persianas:
/// el canal del módulo PCA9685 con su mismo número de pin virtual (casa-0.8).
const casaControls = <ControlSpec>[
  ControlSpec(vpin: 1, label: 'Puerta principal', room: 'Entrada', kind: ControlKind.door, gpio: 1),
  ControlSpec(vpin: 10, label: 'Luz 1', room: 'Sala', kind: ControlKind.light, gpio: 2),
  ControlSpec(vpin: 11, label: 'Luz 2', room: 'Sala', kind: ControlKind.light, gpio: 4),
  ControlSpec(vpin: 2, label: 'Puerta', room: 'Sala', kind: ControlKind.door, gpio: 2),
  ControlSpec(vpin: 5, label: 'Persiana', room: 'Sala', kind: ControlKind.blind, gpio: 5),
  ControlSpec(vpin: 12, label: 'Luz', room: 'Cocina', kind: ControlKind.light, gpio: 5),
  ControlSpec(vpin: 7, label: 'Persiana 1', room: 'Cocina', kind: ControlKind.blind, gpio: 7),
  ControlSpec(vpin: 8, label: 'Persiana 2', room: 'Cocina', kind: ControlKind.blind, gpio: 8),
  ControlSpec(vpin: 13, label: 'Luz', room: 'Baño', kind: ControlKind.light, gpio: 12),
  ControlSpec(vpin: 3, label: 'Puerta', room: 'Baño', kind: ControlKind.door, gpio: 3),
  ControlSpec(vpin: 14, label: 'Luz', room: 'Cuarto', kind: ControlKind.light, gpio: 25),
  ControlSpec(vpin: 4, label: 'Puerta', room: 'Cuarto', kind: ControlKind.door, gpio: 4),
  ControlSpec(vpin: 6, label: 'Persiana', room: 'Cuarto', kind: ControlKind.blind, gpio: 6),
  ControlSpec(vpin: 15, label: 'Luz', room: 'Garaje', kind: ControlKind.light, gpio: 26),
  ControlSpec(vpin: 0, label: 'Portón', room: 'Garaje', kind: ControlKind.door, gpio: 0),
];

/// La sirena no tiene tarjeta propia (se maneja desde la seguridad), pero su pin se puede ajustar.
const casaSiren = ControlSpec(vpin: CasaPins.siren, label: 'Sirena', room: 'Seguridad', kind: ControlKind.light, gpio: 27);

/// El control de un pin virtual de la casa (incluida la sirena), o null.
ControlSpec? casaSpec(int vpin) => vpin == casaSiren.vpin ? casaSiren : casaControls.where((c) => c.vpin == vpin).firstOrNull;

/// Habitaciones en el orden en que aparecen en el panel.
List<String> get casaRooms => {for (final c in casaControls) c.room}.toList();

extension ControlPins on ControlSpec {
  /// El ajuste vigente de este control: el guardado para la placa o el de fábrica.
  /// Un servo guardado antes de casa-0.8 (un GPIO) pasa a su canal de fábrica, con su invertir y activar.
  PinConfig pinsFor(SavedDevice d) {
    final saved = d.pins[vpin];
    if (!onPca) return saved ?? PinConfig(gpio, inverted: inverted, enabled: enabled);
    if (saved == null) return PinConfig(gpio, inverted: inverted, enabled: enabled, pca: true);
    return saved.pca ? saved : PinConfig(gpio, inverted: saved.inverted, enabled: saved.enabled, pca: true);
  }

  bool isEnabledOn(SavedDevice d) => pinsFor(d).enabled;
}

/// Revisa si un GPIO del ESP32 sirve como salida. Devuelve el problema, o null si está bien.
/// El programa de la placa aplica las mismas reglas.
String? gpioProblem(int gpio, {bool output = true}) {
  if (gpio < 0 || gpio > 39) return 'El ESP32 tiene GPIO del 0 al 39.';
  if (gpio >= 6 && gpio <= 11) return 'Los GPIO 6 a 11 los usa la memoria de la placa.';
  if (gpio == 1 || gpio == 3) return 'Los GPIO 1 y 3 son el cable USB (Monitor Serie) de la placa.';
  if (const {20, 24, 28, 29, 30, 31}.contains(gpio)) return 'El GPIO $gpio no existe en el ESP32.';
  if (gpio == 21 || gpio == 22) {
    return 'Los GPIO 21 y 22 son SDA y SCL: los usa el módulo PCA9685 de la casa y la pantalla de la cara del carrito.';
  }
  if (output && gpio >= 34) return 'Los GPIO 34 a 39 solo sirven como entrada.';
  return null;
}

/// Revisa un canal del módulo PCA9685. Devuelve el problema, o null si está bien.
String? channelProblem(int channel) => channel < 0 || channel > 15 ? 'El módulo PCA9685 tiene canales del 0 al 15.' : null;


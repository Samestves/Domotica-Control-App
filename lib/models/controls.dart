import 'device.dart';
import 'pins.dart';

export 'pins.dart';

enum ControlKind { light, door, blind }

/// Un control del panel Casa. El número de pin virtual (V0, V10…) es lo que viaja en el mensaje
/// y es el mismo que usaba el grupo en Blynk. `gpio` es el pin físico por defecto en el ESP32.
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
}

/// Cableado de la maqueta del grupo, según su documento «Conexiones GPIO».
const casaControls = <ControlSpec>[
  ControlSpec(vpin: 1, label: 'Puerta principal', room: 'Entrada', kind: ControlKind.door, gpio: 14),
  ControlSpec(vpin: 10, label: 'Luz 1', room: 'Sala', kind: ControlKind.light, gpio: 2),
  ControlSpec(vpin: 11, label: 'Luz 2', room: 'Sala', kind: ControlKind.light, gpio: 4),
  ControlSpec(vpin: 2, label: 'Puerta', room: 'Sala', kind: ControlKind.door, gpio: 15),
  ControlSpec(vpin: 5, label: 'Persiana', room: 'Sala', kind: ControlKind.blind, gpio: 18),
  ControlSpec(vpin: 12, label: 'Luz', room: 'Cocina', kind: ControlKind.light, gpio: 5),
  ControlSpec(vpin: 7, label: 'Persiana 1', room: 'Cocina', kind: ControlKind.blind, gpio: 21),
  ControlSpec(vpin: 8, label: 'Persiana 2', room: 'Cocina', kind: ControlKind.blind, gpio: 22),
  ControlSpec(vpin: 13, label: 'Luz', room: 'Baño', kind: ControlKind.light, gpio: 12),
  ControlSpec(vpin: 3, label: 'Puerta', room: 'Baño', kind: ControlKind.door, gpio: 16),
  ControlSpec(vpin: 14, label: 'Luz', room: 'Cuarto', kind: ControlKind.light, gpio: 25),
  ControlSpec(vpin: 4, label: 'Puerta', room: 'Cuarto', kind: ControlKind.door, gpio: 17),
  ControlSpec(vpin: 6, label: 'Persiana', room: 'Cuarto', kind: ControlKind.blind, gpio: 19),
  ControlSpec(vpin: 15, label: 'Luz', room: 'Garaje', kind: ControlKind.light, gpio: 26),
  ControlSpec(vpin: 0, label: 'Portón', room: 'Garaje', kind: ControlKind.door, gpio: 13),
];

/// La sirena no tiene tarjeta propia (se maneja desde la seguridad), pero su pin se puede ajustar.
const casaSiren = ControlSpec(vpin: CasaPins.siren, label: 'Sirena', room: 'Seguridad', kind: ControlKind.light, gpio: 27);

/// Habitaciones en el orden en que aparecen en el panel.
List<String> get casaRooms => {for (final c in casaControls) c.room}.toList();

extension ControlPins on ControlSpec {
  /// El ajuste vigente de este control: el guardado para la placa o el de fábrica.
  PinConfig pinsFor(SavedDevice d) => d.pins[vpin] ?? PinConfig(gpio, inverted: inverted, enabled: enabled);

  bool isEnabledOn(SavedDevice d) => pinsFor(d).enabled;
}

/// Revisa si un GPIO del ESP32 sirve como salida. Devuelve el problema, o null si está bien.
/// El programa de la placa aplica las mismas reglas.
String? gpioProblem(int gpio, {bool output = true}) {
  if (gpio < 0 || gpio > 39) return 'El ESP32 tiene GPIO del 0 al 39.';
  if (gpio >= 6 && gpio <= 11) return 'Los GPIO 6 a 11 los usa la memoria de la placa.';
  if (const {20, 24, 28, 29, 30, 31}.contains(gpio)) return 'El GPIO $gpio no existe en el ESP32.';
  if (output && gpio >= 34) return 'Los GPIO 34 a 39 solo sirven como entrada.';
  return null;
}


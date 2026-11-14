import 'package:flutter/material.dart';

import 'device.dart';

enum ControlKind { toggle, servoToggle, slider, button, text, alarm, reading }

/// Un control del panel Casa. El número de pin virtual (V1, V2…) es lo que viaja en el mensaje.
/// `gpio` es el pin físico por defecto en el ESP32; se puede cambiar desde la app.
class ControlSpec {
  final int vpin;
  final String label;
  final ControlKind kind;
  final IconData icon;
  final int? gpio;
  final bool inverted; // por defecto; los módulos de relé se activan con señal baja
  final bool enabled; // por defecto; false si la pieza puede no estar en la maqueta
  final bool output; // false: no se controla, solo se muestra o se lee
  final String unit;
  final int min, max;
  final int openValue; // ángulo «abierto» de un servo

  const ControlSpec({
    required this.vpin,
    required this.label,
    required this.kind,
    required this.icon,
    this.gpio,
    this.inverted = false,
    this.enabled = true,
    this.output = true,
    this.unit = '',
    this.min = 0,
    this.max = 180,
    this.openValue = 90,
  });
}

/// Pines por defecto pensados para un ESP32 DevKit de 30 o 38 pines.
/// 21 y 22 quedan libres para una pantalla LCD por I2C.
const casaControls = <ControlSpec>[
  ControlSpec(vpin: 7, label: 'Alarma', kind: ControlKind.alarm, icon: Icons.shield_outlined, output: false),
  ControlSpec(vpin: 1, label: 'Luz sala', kind: ControlKind.toggle, icon: Icons.lightbulb_outline, gpio: 23, inverted: true),
  ControlSpec(vpin: 2, label: 'Luz cocina', kind: ControlKind.toggle, icon: Icons.lightbulb_outline, gpio: 19, inverted: true),
  ControlSpec(vpin: 8, label: 'Luz cuarto', kind: ControlKind.toggle, icon: Icons.lightbulb_outline, gpio: 18, inverted: true),
  ControlSpec(vpin: 9, label: 'Ventilador', kind: ControlKind.toggle, icon: Icons.mode_fan_off_outlined, gpio: 5, inverted: true),
  ControlSpec(vpin: 3, label: 'Puerta principal', kind: ControlKind.servoToggle, icon: Icons.door_front_door_outlined, gpio: 13),
  ControlSpec(vpin: 4, label: 'Ventana', kind: ControlKind.slider, icon: Icons.window_outlined, gpio: 14, unit: '°'),
  ControlSpec(vpin: 5, label: 'Timbre', kind: ControlKind.button, icon: Icons.notifications_none, gpio: 27),
  ControlSpec(vpin: 6, label: 'Pantalla LCD', kind: ControlKind.text, icon: Icons.tv_outlined, output: false),
  ControlSpec(vpin: 10, label: 'Temperatura', kind: ControlKind.reading, icon: Icons.thermostat_outlined, output: false, unit: ' °C'),
  ControlSpec(vpin: 11, label: 'Movimiento', kind: ControlKind.reading, icon: Icons.sensors, gpio: 34, enabled: false, output: false),
];

extension ControlPins on ControlSpec {
  /// El ajuste vigente de este control: el guardado para la placa o el de fábrica.
  PinConfig? pinsFor(SavedDevice d) =>
      d.pins[vpin] ?? (gpio == null ? null : PinConfig(gpio!, inverted: inverted, enabled: enabled));

  bool isEnabledOn(SavedDevice d) => pinsFor(d)?.enabled ?? true;
}

/// Revisa si un GPIO del ESP32 sirve para un control. Devuelve el problema, o null si está bien.
/// El programa de la placa aplica las mismas reglas.
String? gpioProblem(int gpio, {required bool output}) {
  if (gpio < 0 || gpio > 39) return 'El ESP32 tiene GPIO del 0 al 39.';
  if (gpio >= 6 && gpio <= 11) return 'Los GPIO 6 a 11 los usa la memoria de la placa.';
  if (const {20, 24, 28, 29, 30, 31}.contains(gpio)) return 'El GPIO $gpio no existe en el ESP32.';
  if (output && gpio >= 34) return 'Los GPIO 34 a 39 solo sirven como entrada.';
  return null;
}

/// Pines virtuales del carro.
class CarPins {
  static const joystick = 20, turret = 21, distance = 22, lights = 23, throttle = 24, reverse = 25, horn = 26;
}

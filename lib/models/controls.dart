import 'package:flutter/material.dart';

enum ControlKind { toggle, servoToggle, slider, button, text, alarm, reading }

/// Un control del panel Casa. El número de pin virtual (V1, V2…) es lo que viaja en el mensaje.
/// `gpio` es el pin físico por defecto en el ESP32; se puede cambiar desde la app.
class ControlSpec {
  final int vpin;
  final String label;
  final ControlKind kind;
  final IconData icon;
  final int? gpio;
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
  ControlSpec(vpin: 1, label: 'Luz sala', kind: ControlKind.toggle, icon: Icons.lightbulb_outline, gpio: 23),
  ControlSpec(vpin: 2, label: 'Luz cocina', kind: ControlKind.toggle, icon: Icons.lightbulb_outline, gpio: 19),
  ControlSpec(vpin: 8, label: 'Luz cuarto', kind: ControlKind.toggle, icon: Icons.lightbulb_outline, gpio: 18),
  ControlSpec(vpin: 9, label: 'Ventilador', kind: ControlKind.toggle, icon: Icons.mode_fan_off_outlined, gpio: 5),
  ControlSpec(vpin: 3, label: 'Puerta principal', kind: ControlKind.servoToggle, icon: Icons.door_front_door_outlined, gpio: 13),
  ControlSpec(vpin: 4, label: 'Ventana', kind: ControlKind.slider, icon: Icons.window_outlined, gpio: 14, unit: '°'),
  ControlSpec(vpin: 5, label: 'Timbre', kind: ControlKind.button, icon: Icons.notifications_none, gpio: 27),
  ControlSpec(vpin: 6, label: 'Pantalla LCD', kind: ControlKind.text, icon: Icons.tv_outlined, output: false),
  ControlSpec(vpin: 10, label: 'Temperatura', kind: ControlKind.reading, icon: Icons.thermostat_outlined, output: false, unit: ' °C'),
  ControlSpec(vpin: 11, label: 'Movimiento', kind: ControlKind.reading, icon: Icons.sensors, gpio: 34, output: false),
];

/// Pines virtuales del carro.
class CarPins {
  static const joystick = 20, turret = 21, distance = 22, lights = 23, throttle = 24, reverse = 25, horn = 26;
}

import 'package:flutter/material.dart';

import '../../core/link.dart';
import '../../models/device.dart';
import '../theme.dart';

Color stateColor(LinkState s) => switch (s) {
      LinkState.connected => C.ok,
      LinkState.connecting => C.warn,
      LinkState.error => C.danger,
      LinkState.disconnected => const Color(0xFFB8C0CA),
    };

String stateLabel(LinkState s) => switch (s) {
      LinkState.connected => 'Conectado',
      LinkState.connecting => 'Conectando…',
      LinkState.error => 'Sin conexión',
      LinkState.disconnected => 'Desconectado',
    };

class StatusDot extends StatelessWidget {
  final LinkState state;
  final double size;
  const StatusDot(this.state, {super.key, this.size = 8});

  @override
  Widget build(BuildContext context) {
    final c = stateColor(state);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: .25), spreadRadius: 3)],
      ),
    );
  }
}

class TransportChip extends StatelessWidget {
  final Transport t;
  const TransportChip(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (t) {
      Transport.ble => (const Color(0xFFE7F0FF), const Color(0xFF0A5FD1)),
      Transport.wifi => (const Color(0xFFE5F7EC), const Color(0xFF16893D)),
      Transport.demo => (C.fill, C.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(t.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

IconData profileIcon(Profile p) => switch (p) {
      Profile.casa => Icons.home_outlined,
      Profile.carro => Icons.directions_car_outlined,
    };

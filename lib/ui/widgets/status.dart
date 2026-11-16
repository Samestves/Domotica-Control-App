import 'package:flutter/material.dart';

import '../../core/link.dart';
import '../../models/device.dart';
import '../theme.dart';

Color stateColor(LinkState s) => switch (s) {
      LinkState.connected => C.green,
      LinkState.connecting => C.orange,
      LinkState.error => C.red,
      LinkState.disconnected => const Color(0xFFAEAEB2),
    };

String stateLabel(LinkState s) => switch (s) {
      LinkState.connected => 'Conectado',
      LinkState.connecting => 'Conectando…',
      LinkState.error => 'Sin conexión',
      LinkState.disconnected => 'Desconectado',
    };

/// Punto de color con un halo suave; late despacio mientras conecta.
class StatusDot extends StatefulWidget {
  final LinkState state;
  final double size;
  const StatusDot(this.state, {super.key, this.size = 8});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(StatusDot old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    if (widget.state == LinkState.connecting) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = stateColor(widget.state);
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: widget.size, spreadRadius: 1)],
        ),
      ),
    );
  }
}

IconData profileIcon(Profile p) => switch (p) {
      Profile.casa => Icons.home_rounded,
      Profile.carro => Icons.directions_car_filled_rounded,
    };

/// Degradado del icono de cada perfil.
List<Color> profileColors(Profile p) => switch (p) {
      Profile.casa => const [Color(0xFF4CD9A0), Color(0xFF16A37A)],
      Profile.carro => const [Color(0xFF5AB0FF), Color(0xFF1E6FF0)],
    };

IconData transportIcon(Transport t) => switch (t) {
      Transport.ble => Icons.bluetooth_rounded,
      Transport.wifi => Icons.wifi_rounded,
      Transport.demo => Icons.auto_awesome_rounded,
    };

/// Icono del perfil dentro de un cuadrado de esquinas continuas con degradado.
class ProfileBadge extends StatelessWidget {
  final Profile profile;
  final double size;
  const ProfileBadge(this.profile, {super.key, this.size = 52});

  @override
  Widget build(BuildContext context) {
    final colors = profileColors(profile);
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: squircle(size * 0.3),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        shadows: [BoxShadow(color: colors.last.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6))],
      ),
      child: Icon(profileIcon(profile), color: Colors.white, size: size * 0.52),
    );
  }
}

/// «● Conectado · Bluetooth»: estado de una placa en una sola línea.
class ConnectionLine extends StatelessWidget {
  final LinkState state;
  final Transport transport;
  final bool retrying;
  final Color? textColor;
  const ConnectionLine({super.key, required this.state, required this.transport, this.retrying = false, this.textColor});

  @override
  Widget build(BuildContext context) {
    final label = retrying ? 'Reconectando…' : stateLabel(state);
    final color = textColor ?? C.label2;
    // Un solo texto con el icono dentro: si no cabe, se corta con «…» en vez de desbordarse.
    return Row(mainAxisSize: MainAxisSize.min, children: [
      StatusDot(retrying ? LinkState.connecting : state, size: 7),
      const SizedBox(width: 7),
      Flexible(
        child: Text.rich(
          TextSpan(style: T.footnote.copyWith(color: color), children: [
            TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w500)),
            TextSpan(text: '  ·  ', style: TextStyle(color: color.withValues(alpha: 0.5))),
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(transportIcon(transport), size: 13, color: color)),
            TextSpan(text: ' ${transport.label}'),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ]);
  }
}

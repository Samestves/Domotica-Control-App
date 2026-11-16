import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/link.dart';
import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/drive_controls.dart';
import 'widgets/glass.dart';
import 'widgets/status.dart';

/// Panel de conducción en horizontal, como un control remoto. Va en modo oscuro, tipo cabina.
class CarroPanel extends StatefulWidget {
  final SavedDevice device;
  const CarroPanel({super.key, required this.device});

  @override
  State<CarroPanel> createState() => _CarroPanelState();
}

class _CarroPanelState extends State<CarroPanel> {
  int _jx = 0, _jy = 0, _throttle = 0, _turret = 0;
  bool _reverse = false, _lights = false;
  final _lastSent = <int, DateTime>{};
  Session? _session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _session = AppScope.read(context).session(widget.device);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Al salir: detener el carro y volver a la orientación normal.
    final s = _session;
    if (s != null && s.connected) {
      s.send(CarPins.joystick, '0,0', quiet: true);
      s.send(CarPins.throttle, 0, quiet: true);
    }
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Limita los mensajes continuos (joystick, dial, acelerador) a uno cada 90 ms por pin.
  void _sendThrottled(Session s, int pin, Object v, {bool force = false}) {
    final now = DateTime.now();
    final last = _lastSent[pin];
    if (!force && last != null && now.difference(last).inMilliseconds < 90) return;
    _lastSent[pin] = now;
    s.send(pin, v);
  }

  void _brake(Session s) {
    HapticFeedback.heavyImpact();
    setState(() => _throttle = 0);
    s.send(CarPins.throttle, 0);
    s.send(CarPins.joystick, '0,0');
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session(widget.device);
    final on = s.connected;
    final dist = int.tryParse(s.values[CarPins.distance] ?? '');
    final near = dist != null && dist < 20;
    final speed = [_jy.abs(), _throttle].reduce((a, b) => a > b ? a : b);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: C.night,
        body: Stack(children: [
          const Positioned.fill(child: Wallpaper(dark: true)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 18, 12),
              child: Row(children: [
                // Izquierda: volver, nombre y joystick
                SizedBox(
                  width: 200,
                  child: Column(children: [
                    Row(children: [
                      GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: 'Volver', dark: true, onTap: () => Navigator.pop(context)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(widget.device.name, style: T.headline.copyWith(color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                    Expanded(
                      child: Center(
                        child: Joystick(
                          enabled: on,
                          onChanged: (x, y) {
                            setState(() {
                              _jx = x;
                              _jy = y;
                            });
                            _sendThrottled(s, CarPins.joystick, '$x,$y', force: x == 0 && y == 0);
                          },
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                // Centro: estado, telemetría, dial y mensajes
                Expanded(
                  child: Column(children: [
                    _StatusBar(session: s),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _Telemetry(icon: Icons.speed_rounded, label: 'Velocidad', value: '${_reverse ? '−' : ''}$speed %')),
                      const SizedBox(width: 8),
                      Expanded(child: _Telemetry(icon: Icons.sensors_rounded, label: 'Obstáculo', value: dist == null ? '—' : '$dist cm', alert: near)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Telemetry(
                          icon: Icons.turn_right_rounded,
                          label: 'Dirección',
                          value: _jx == 0 ? 'Recto' : (_jx < 0 ? 'Izq. ${-_jx}' : 'Der. $_jx'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Row(children: [
                        Glass(
                          dark: true,
                          radius: R.tile,
                          shadow: false,
                          padding: const EdgeInsets.fromLTRB(8, 6, 14, 6),
                          child: Row(children: [
                            Dial360(
                              value: _turret,
                              enabled: on,
                              onChanged: (v) {
                                setState(() => _turret = v);
                                _sendThrottled(s, CarPins.turret, v);
                              },
                            ),
                            const SizedBox(width: 6),
                            Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Torreta', style: T.subhead.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                              Text('Giro 360°', style: T.footnote.copyWith(color: C.nightLabel2)),
                            ]),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _MiniLog(session: s)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                // Derecha: acelerador y botones
                SizedBox(
                  width: 200,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Throttle(
                      value: _throttle,
                      enabled: on,
                      onChanged: (v) {
                        setState(() => _throttle = v);
                        _sendThrottled(s, CarPins.throttle, v, force: v == 0);
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _DriveButton(
                          label: 'Reversa',
                          icon: Icons.u_turn_left_rounded,
                          active: _reverse,
                          activeColor: C.orange,
                          onTap: on
                              ? () {
                                  setState(() => _reverse = !_reverse);
                                  s.send(CarPins.reverse, _reverse ? 1 : 0);
                                }
                              : null,
                        ),
                        const SizedBox(height: 8),
                        _DriveButton(
                          label: 'Luces',
                          icon: Icons.highlight_rounded,
                          active: _lights,
                          activeColor: C.blue,
                          onTap: on
                              ? () {
                                  setState(() => _lights = !_lights);
                                  s.send(CarPins.lights, _lights ? 1 : 0);
                                }
                              : null,
                        ),
                        const SizedBox(height: 8),
                        _DriveButton(
                          label: 'Bocina',
                          icon: Icons.campaign_rounded,
                          onTap: on
                              ? () {
                                  HapticFeedback.mediumImpact();
                                  s.send(CarPins.horn, 1, remember: false);
                                }
                              : null,
                        ),
                        const SizedBox(height: 8),
                        _DriveButton(label: 'Freno', icon: Icons.front_hand_rounded, active: true, activeColor: C.red, onTap: on ? () => _brake(s) : null),
                      ]),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  final Session session;
  const _StatusBar({required this.session});

  @override
  Widget build(BuildContext context) {
    final st = session.state;
    return Glass(
      dark: true,
      radius: 18,
      shadow: false,
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      child: Row(children: [
        Expanded(
          child: ConnectionLine(state: st, transport: session.device.transport, retrying: session.retrying, textColor: C.nightLabel2),
        ),
        if (st != LinkState.connected && st != LinkState.connecting && !session.retrying)
          GestureDetector(
            onTap: session.connect,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text('Conectar', style: T.footnote.copyWith(color: const Color(0xFF4AA8FF), fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}

class _Telemetry extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final bool alert;
  const _Telemetry({required this.icon, required this.label, required this.value, this.alert = false});

  @override
  Widget build(BuildContext context) {
    return Glass(
      dark: true,
      radius: 18,
      shadow: false,
      color: alert ? const Color(0xCCFF3B30) : null,
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 13, color: alert ? Colors.white : C.nightLabel2),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: T.caption.copyWith(color: alert ? Colors.white : C.nightLabel2), maxLines: 1)),
        ]),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.title3.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ]),
    );
  }
}

class _DriveButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;
  const _DriveButton({required this.label, required this.icon, this.active = false, this.activeColor = C.blue, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: ShapeDecoration(
            shape: squircle(R.control, side: BorderSide(color: active ? Colors.transparent : C.nightEdge)),
            color: active ? activeColor : C.nightGlass,
            shadows: active ? [BoxShadow(color: activeColor.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 4))] : null,
          ),
          child: Row(children: [
            Icon(icon, size: 19, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: T.subhead.copyWith(color: Colors.white, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      ),
    );
  }
}

class _MiniLog extends StatelessWidget {
  final Session session;
  const _MiniLog({required this.session});

  @override
  Widget build(BuildContext context) {
    final items = session.log.take(4).toList();
    return Glass(
      dark: true,
      radius: R.tile,
      shadow: false,
      color: const Color(0x66000000),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final l in items)
          Text('${l.incoming ? '←' : '→'} ${l.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.mono.copyWith(fontSize: 11, color: l.incoming ? const Color(0xFFFFD60A) : const Color(0xFF7CE0A3))),
        if (items.isEmpty) Text('Sin mensajes', style: T.mono.copyWith(fontSize: 11, color: const Color(0x66EBEBF5))),
      ]),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/carro_ajustes.dart';
import 'widgets/drive_controls.dart';
import 'widgets/kit.dart';
import 'widgets/status.dart';

/// Panel de manejo en horizontal, como un control remoto.
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
  Timer? _keepAlive;

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
    _keepAlive = Timer.periodic(CarPins.keepAlive, (_) => _repeat());
  }

  /// Mientras el carro anda, repite la orden actual: la placa frena sola si deja de recibirla.
  /// También corrige el último movimiento del joystick si se lo saltó el límite de 90 ms.
  void _repeat() {
    final s = _session;
    if (s == null || !s.connected) return;
    if (_jx != 0 || _jy != 0) s.send(CarPins.joystick, '$_jx,$_jy', quiet: true);
    if (_throttle != 0) s.send(CarPins.throttle, _throttle, quiet: true);
  }

  @override
  void dispose() {
    _keepAlive?.cancel();
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
    final c = context.c;
    final s = AppScope.of(context).session(widget.device);
    final on = s.connected;
    final dist = int.tryParse(s.values[CarPins.distance] ?? '');
    final near = dist != null && dist < 20;
    final speed = [_jy.abs(), _throttle].reduce((a, b) => a > b ? a : b);
    final overlay = (c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 18, 12),
            child: Row(children: [
              // Izquierda: volver, nombre y joystick
              SizedBox(
                width: 206,
                child: Column(children: [
                  Row(children: [
                    RoundButton(icon: Ic.back, tooltip: 'Volver', size: 40, onTap: () => Navigator.pop(context)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Eyebrow('Auto Robot'),
                        const SizedBox(height: 2),
                        Text(widget.device.name, style: T.callout, maxLines: 2),
                      ]),
                    ),
                    RoundButton(icon: Ic.wheels, tooltip: 'Ruedas', size: 40, onTap: () => showCarroAjustes(context, s)),
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
              // Centro: estado, telemetría, torreta y mensajes
              Expanded(
                child: Column(children: [
                  Panel(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: ConnectionBar(session: s)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _Telemetry(icon: Ic.speed, label: 'Velocidad', value: '${_reverse ? '-' : ''}$speed %')),
                    const SizedBox(width: 8),
                    Expanded(child: _Telemetry(icon: Ic.distance, label: 'Obstáculo', value: dist == null ? '—' : '$dist cm', alert: near)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Telemetry(icon: Ic.steering, label: 'Dirección', value: _jx == 0 ? 'Recto' : (_jx < 0 ? 'Izq. ${-_jx}' : 'Der. $_jx')),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Row(children: [
                      // La torreta aparece solo si la placa dice que tiene una (envía V21 al conectar).
                      if (s.values.containsKey(CarPins.turret)) ...[
                        Panel(
                          padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                          child: Row(children: [
                            Dial360(
                              value: _turret,
                              enabled: on,
                              onChanged: (v) {
                                setState(() => _turret = v);
                                _sendThrottled(s, CarPins.turret, v);
                              },
                            ),
                            const SizedBox(width: 8),
                            const Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Eyebrow('Torreta'),
                              SizedBox(height: 4),
                              Text('Giro 360°', style: T.callout),
                            ]),
                          ]),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: _MiniLog(session: s)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              // Derecha: acelerador y botones
              SizedBox(
                width: 206,
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
                        icon: Ic.reverse,
                        active: _reverse,
                        activeColor: c.amber,
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
                        icon: Ic.headlights,
                        active: _lights,
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
                        icon: Ic.horn,
                        onTap: on
                            ? () {
                                HapticFeedback.mediumImpact();
                                s.send(CarPins.horn, 1, remember: false);
                              }
                            : null,
                      ),
                      const SizedBox(height: 8),
                      _DriveButton(label: 'Freno', icon: Ic.brake, active: true, activeColor: c.red, onTap: on ? () => _brake(s) : null),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
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
    final c = context.c;
    return Panel(
      color: alert ? c.red.withValues(alpha: 0.14) : null,
      border: alert ? c.red : null,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: alert ? c.red : c.text2),
          const SizedBox(width: 6),
          Flexible(child: Eyebrow(label, color: alert ? c.red : null)),
        ]),
        const SizedBox(height: 6),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, maxLines: 1, style: T.stat.copyWith(fontSize: 22))),
      ]),
    );
  }
}

class _DriveButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color? activeColor;
  final VoidCallback? onTap;
  const _DriveButton({required this.label, required this.icon, this.active = false, this.activeColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final accent = activeColor ?? c.text;
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      excludeSemantics: true,
      child: Tap(
        onTap: onTap,
        scale: 0.95,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: active ? accent.withValues(alpha: 0.14) : c.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: active ? accent : c.line2),
            ),
            child: Row(children: [
              Icon(icon, size: 19, color: active ? accent : c.text),
              const SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(label.toUpperCase(), style: T.button.copyWith(color: active ? accent : c.text), maxLines: 1),
                ),
              ),
            ]),
          ),
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
    final c = context.c;
    final items = session.log.take(4).toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final l in items)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: l.incoming ? '← ' : '→ ', style: TextStyle(color: l.incoming ? c.amber : c.green)),
              TextSpan(text: l.text, style: TextStyle(color: l.incoming ? c.text : c.text2)),
            ]),
            maxLines: 2,
            style: T.mono.copyWith(fontSize: 11),
          ),
        if (items.isEmpty) Text('Sin mensajes', style: T.mono.copyWith(fontSize: 11, color: c.text3)),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/drive_controls.dart';
import 'widgets/status.dart';

/// Panel de conducción en horizontal, como un control remoto.
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

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session(widget.device);
    final on = s.connected;
    final dist = int.tryParse(s.values[CarPins.distance] ?? '');
    final near = dist != null && dist < 20;
    final speed = [_jy.abs(), _throttle].reduce((a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: const Color(0xFFEDF0F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          child: Row(children: [
            // Izquierda: volver + joystick
            SizedBox(
              width: 196,
              child: Column(children: [
                Row(children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new, size: 20), tooltip: 'Volver'),
                  Expanded(child: Text(widget.device.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
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
                const PinTag('V20 · dirección x,y'),
              ]),
            ),
            const SizedBox(width: 12),
            // Centro: estado, telemetría, dial y mensajes
            Expanded(
              child: Column(children: [
                Panel(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  child: Row(children: [
                    StatusDot(s.state),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${stateLabel(s.state)} · ${widget.device.subtitle}', style: const TextStyle(fontSize: 12.5), overflow: TextOverflow.ellipsis)),
                    if (!on) TextButton(onPressed: s.connect, child: const Text('Conectar')),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _tele('Velocidad', '${_reverse ? '−' : ''}$speed %')),
                  const SizedBox(width: 8),
                  Expanded(child: _tele('Obstáculo', dist == null ? '—' : '$dist cm', alert: near)),
                  const SizedBox(width: 8),
                  Expanded(child: _tele('Dirección', _jx == 0 ? 'Recto' : (_jx < 0 ? 'Izq. ${-_jx}' : 'Der. $_jx'))),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(children: [
                    Dial360(
                      value: _turret,
                      enabled: on,
                      onChanged: (v) {
                        setState(() => _turret = v);
                        _sendThrottled(s, CarPins.turret, v);
                      },
                    ),
                    const SizedBox(width: 10),
                    const Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Giro 360°', style: TextStyle(fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      PinTag('V21 · servo'),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(child: _miniLog(s)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            // Derecha: acelerador y botones
            SizedBox(
              width: 170,
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
                    _btn('Reversa', _reverse, const Color(0xFFFF9F0A), on ? () {
                      setState(() => _reverse = !_reverse);
                      s.send(CarPins.reverse, _reverse ? 1 : 0);
                    } : null),
                    const SizedBox(height: 8),
                    _btn('Luces', _lights, C.accent, on ? () {
                      setState(() => _lights = !_lights);
                      s.send(CarPins.lights, _lights ? 1 : 0);
                    } : null),
                    const SizedBox(height: 8),
                    _btn('Bocina', false, C.accent, on ? () {
                      HapticFeedback.mediumImpact();
                      s.send(CarPins.horn, 1, remember: false);
                    } : null),
                    const SizedBox(height: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: C.danger, minimumSize: const Size(0, 48)),
                      onPressed: on
                          ? () {
                              HapticFeedback.heavyImpact();
                              setState(() => _throttle = 0);
                              s.send(CarPins.throttle, 0);
                              s.send(CarPins.joystick, '0,0');
                            }
                          : null,
                      child: const Text('Freno'),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tele(String label, String value, {bool alert = false}) => Panel(
        color: alert ? C.danger : C.card,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: alert ? Colors.white70 : C.ink2)),
          Text(value,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: alert ? Colors.white : C.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ]),
      );

  Widget _btn(String label, bool active, Color color, VoidCallback? onTap) => FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          backgroundColor: active ? color : Colors.white,
          foregroundColor: active ? Colors.white : C.ink,
        ),
        onPressed: onTap,
        child: Text(label),
      );

  Widget _miniLog(Session s) {
    final items = s.log.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final l in items)
          Text('${l.incoming ? '←' : '→'} ${l.text}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: l.incoming ? const Color(0xFFFFD07A) : const Color(0xFF9FE6B8))),
        if (items.isEmpty) const Text('Sin mensajes', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF6B7F95))),
      ]),
    );
  }
}

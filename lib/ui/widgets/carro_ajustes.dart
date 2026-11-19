import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pins.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// Ruedas en el orden del programa del carrito: DI, TI, DD, TD.
const _wheelNames = ['Delantera izq.', 'Trasera izq.', 'Delantera der.', 'Trasera der.'];

/// Hoja para probar las ruedas e invertir la que gire al revés (sin recablear).
Future<void> showCarroAjustes(BuildContext context, Session session) => showAppSheet<void>(context, (_) => _CarroAjustes(session: session));

/// «0100» → [false, true, false, false]. Si la placa todavía no lo envió, ninguna invertida.
List<bool> invertedWheels(Session s) {
  final v = s.values[CarPins.invert] ?? '';
  return List.generate(4, (i) => v.length == 4 && v[i] == '1');
}

class _CarroAjustes extends StatefulWidget {
  final Session session;
  const _CarroAjustes({required this.session});

  @override
  State<_CarroAjustes> createState() => _CarroAjustesState();
}

class _CarroAjustesState extends State<_CarroAjustes> {
  /// Mientras corre la prueba: qué rueda está girando («delantera izquierda»), o '' al empezar.
  String? _testing;
  StreamSubscription? _sub;
  Timer? _timeout;

  Session get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _sub = _s.messages.listen((m) {
      if (_testing == null || m.kind != 'OK' || !m.value.startsWith('PRUEBA')) return;
      if (m.value.contains('terminada')) return _endTest();
      if (m.value.startsWith('PRUEBA rueda ')) setState(() => _testing = m.value.substring('PRUEBA rueda '.length));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  void _toggle(int i) {
    HapticFeedback.selectionClick();
    final inv = invertedWheels(_s);
    inv[i] = !inv[i];
    _s.send(CarPins.invert, inv.map((b) => b ? '1' : '0').join());
  }

  /// Una sola prueba a la vez: el botón queda bloqueado hasta que la placa avisa que terminó.
  void _startTest() {
    HapticFeedback.mediumImpact();
    setState(() => _testing = '');
    _s.sendRaw('TEST');
    _timeout?.cancel();
    _timeout = Timer(const Duration(seconds: 12), _endTest); // por si la placa no avisa
  }

  void _endTest() {
    _timeout?.cancel();
    if (mounted) setState(() => _testing = null);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final c = context.c;
        final on = _s.connected;
        final inv = invertedWheels(_s);
        final testing = _testing != null;
        Widget wheel(int i) => Expanded(child: _WheelTile(label: _wheelNames[i], inverted: inv[i], enabled: on && !testing, onTap: () => _toggle(i)));
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: SheetHeader(
                eyebrow: 'Auto Robot',
                title: 'Ruedas del carrito',
                detail: 'Con el carrito en el aire, toca «Probar ruedas»: cada una gira hacia adelante, una por una. '
                    'Si alguna gira hacia atrás, actívala aquí para invertirla.',
              ),
            ),
            const SizedBox(height: 16),
            // Vista desde arriba: adelante arriba, izquierda a la izquierda.
            Row(children: [wheel(0), const SizedBox(width: 10), wheel(2)]),
            const SizedBox(height: 10),
            Row(children: [wheel(1), const SizedBox(width: 10), wheel(3)]),
            const SizedBox(height: 16),
            PillButton(
              testing ? (_testing!.isEmpty ? 'Probando…' : 'Girando: $_testing') : 'Probar ruedas',
              icon: testing ? null : Ic.play,
              leading: testing ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.onInverse)) : null,
              expand: true,
              onTap: on && !testing ? _startTest : null,
            ),
            if (!on)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Conecta el carrito para probar e invertir las ruedas.', style: T.small.copyWith(color: c.text2), textAlign: TextAlign.center),
              ),
          ]),
        );
      },
    );
  }
}

class _WheelTile extends StatelessWidget {
  final String label;
  final bool inverted, enabled;
  final VoidCallback onTap;
  const _WheelTile({required this.label, required this.inverted, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Panel(
        radius: R.tile,
        border: inverted ? c.amber : null,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: T.callout, maxLines: 2),
              const SizedBox(height: 4),
              Eyebrow(inverted ? 'Invertida' : 'Normal', color: inverted ? c.amber : c.text3),
            ]),
          ),
          Toggle(value: inverted, activeColor: c.amber, onChanged: enabled ? (_) => onTap() : null),
        ]),
      ),
    );
  }
}

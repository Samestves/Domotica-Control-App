import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pins.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'clave.dart';
import 'kit.dart';
import 'robot_tiles.dart';
import 'status.dart';

/// Ruedas en el orden del programa del carrito 4x4: DI, TI, DD, TD.
const _wheelNames = ['Delantera izq.', 'Trasera izq.', 'Delantera der.', 'Trasera der.'];

/// Piezas del robot en el orden de V27: rueda izquierda, rueda derecha y lápiz.
const _robotParts = ['Rueda izquierda', 'Rueda derecha', 'Lápiz'];

/// Hoja para probar las ruedas (y el lápiz del robot) e invertir lo que gire al revés, sin recablear.
/// En el robot también tiene sus medidas, para que las letras salgan del tamaño pedido.
Future<void> showCarroAjustes(BuildContext context, Session session) => showAppSheet<void>(context, (_) => _CarroAjustes(session: session));

/// «0100» → [false, true, false, false]: un 0/1 por pieza ([n] = 4 en el carrito, 3 en el robot).
/// Si la placa todavía no lo envió, ninguna invertida.
List<bool> invertFlags(Session s, int n) {
  final v = s.values[CarPins.invert] ?? '';
  return List.generate(n, (i) => v.length == n && v[i] == '1');
}

/// Las cuatro ruedas del carrito 4x4.
List<bool> invertedWheels(Session s) => invertFlags(s, 4);

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
      // La placa cancela la prueba si llega otra orden o se desconecta quien la pidió.
      if (_testing != null && m.kind == 'ERR' && m.value.startsWith('prueba cancelada')) return _endTest();
      if (_testing == null || m.kind != 'OK' || !m.value.startsWith('PRUEBA')) return;
      if (m.value.contains('terminada')) return _endTest();
      // «PRUEBA rueda izquierda», «PRUEBA lapiz abajo»: lo que se está moviendo. «PRUEBA cada rueda…» es el aviso de inicio.
      if (!m.value.startsWith('PRUEBA cada')) setState(() => _testing = _part(m.value.substring('PRUEBA '.length)));
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    super.dispose();
  }

  /// «rueda delantera izquierda» → «delantera izquierda»; «lapiz abajo» → «lápiz abajo».
  static String _part(String raw) => raw.replaceFirst('rueda ', '').replaceAll('lapiz', 'lápiz');

  void _toggle(int i, int n) {
    HapticFeedback.selectionClick();
    final inv = invertFlags(_s, n);
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
        final robot = isRobot(_s);
        final n = robot ? 3 : 4;
        final inv = invertFlags(_s, n);
        final testing = _testing != null;
        Widget part(int i) => Expanded(
              child: _WheelTile(label: robot ? _robotParts[i] : _wheelNames[i], inverted: inv[i], enabled: on && !testing, onTap: () => _toggle(i, n)),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: robot
                  ? const SheetHeader(
                      eyebrow: 'Auto Robot',
                      title: 'Ruedas y lápiz',
                      detail: 'Con el robot en el aire, toca «Probar»: cada rueda da un cuarto de vuelta hacia adelante y el '
                          'lápiz baja y sube. Si algo va al revés, actívalo aquí para invertirlo.',
                    )
                  : const SheetHeader(
                      eyebrow: 'Auto Robot',
                      title: 'Ruedas del carrito',
                      detail: 'Con el carrito en el aire, toca «Probar ruedas»: cada una gira hacia adelante, una por una. '
                          'Si alguna gira hacia atrás, actívala aquí para invertirla.',
                    ),
            ),
            const SizedBox(height: 16),
            // Vista desde arriba: adelante arriba, izquierda a la izquierda.
            if (robot) ...[
              Row(children: [part(0), const SizedBox(width: 10), part(1)]),
              const SizedBox(height: 10),
              Row(children: [part(2)]),
            ] else ...[
              Row(children: [part(0), const SizedBox(width: 10), part(2)]),
              const SizedBox(height: 10),
              Row(children: [part(1), const SizedBox(width: 10), part(3)]),
            ],
            const SizedBox(height: 16),
            PillButton(
              testing ? (_testing!.isEmpty ? 'Probando…' : 'Moviendo: $_testing') : (robot ? 'Probar' : 'Probar ruedas'),
              icon: testing ? null : Ic.play,
              leading: testing ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.onInverse)) : null,
              expand: true,
              onTap: on && !testing ? _startTest : null,
            ),
            if (!on)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(robot ? 'Conecta el robot para probarlo y ajustarlo.' : 'Conecta el carrito para probar e invertir las ruedas.',
                    style: T.small.copyWith(color: c.text2), textAlign: TextAlign.center),
              ),
            if (robot) ...[const SizedBox(height: 18), _MeasuresEditor(session: _s)],
            const SizedBox(height: 18),
            RowGroup(children: [
              if (on && _s.keyed)
                ListRow(
                  icon: Ic.lock,
                  title: 'Cambiar la clave',
                  detail: 'De 4 a 8 números. Los otros teléfonos tendrán que escribir la nueva.',
                  onTap: () {
                    Navigator.pop(context);
                    showChangeClaveSheet(context, _s);
                  },
                ),
              // Desconectar vive aquí y no en el panel: es lo que menos se usa al manejar.
              ListRow(
                icon: connectionMenuItem(_s).$1,
                title: connectionMenuItem(_s).$2,
                onTap: () {
                  Navigator.pop(context);
                  toggleConnection(_s);
                },
              ),
            ]),
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

/// Medidas del robot: con ellas las letras salen del alto pedido y los giros son exactos. Se miden una vez,
/// con una regla, y la placa las guarda.
class _MeasuresEditor extends StatefulWidget {
  final Session session;
  const _MeasuresEditor({required this.session});

  @override
  State<_MeasuresEditor> createState() => _MeasuresEditorState();
}

class _MeasuresEditorState extends State<_MeasuresEditor> {
  late final List<TextEditingController> _fields;

  static const _labels = ['Diámetro de la rueda', 'Entre las ruedas', 'Alto de las letras', 'El lápiz tarda'];
  static const _units = ['mm', 'mm', 'mm', 'ms'];
  static const _ranges = [RobotMeasures.wheelRange, RobotMeasures.trackRange, RobotMeasures.letterRange, RobotMeasures.penRange];

  List<int> _of(RobotMeasures m) => [m.wheelMm, m.trackMm, m.letterMm, m.penMs];

  @override
  void initState() {
    super.initState();
    _fields = [for (final v in _of(RobotMeasures.of(widget.session))) TextEditingController(text: '$v')];
    for (final f in _fields) {
      f.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  /// El primer valor fuera de lo que acepta la placa, para decirlo; null si todos están bien.
  String? _problem() {
    for (var i = 0; i < 4; i++) {
      final v = int.tryParse(_fields[i].text.trim());
      final (lo, hi) = _ranges[i];
      if (v == null || v < lo || v > hi) return '${_labels[i]}: de $lo a $hi ${_units[i]}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.session;
    final saved = _of(RobotMeasures.of(s));
    final typed = [for (final f in _fields) int.tryParse(f.text.trim())];
    final problem = _problem();
    final changed = [for (var i = 0; i < 4; i++) typed[i] != saved[i]].any((x) => x);
    final usable = s.connected && writingProgress(s) == null;

    Widget field(int i) => Expanded(
          child: Panel(
            radius: R.tile,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow(_labels[i], maxLines: 1),
              TextField(
                controller: _fields[i],
                enabled: usable,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                style: T.heading,
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.only(top: 6),
                  suffixText: _units[i],
                  suffixStyle: T.small.copyWith(color: c.text3),
                ),
              ),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: SheetHeader(
          eyebrow: 'Medidas',
          title: 'Del tamaño justo',
          detail: 'Mide con una regla el diámetro de una rueda y la distancia entre el centro de las dos. '
              'El marcador va justo en el medio.',
        ),
      ),
      const SizedBox(height: 12),
      Row(children: [field(0), const SizedBox(width: 10), field(1)]),
      const SizedBox(height: 10),
      Row(children: [field(2), const SizedBox(width: 10), field(3)]),
      const SizedBox(height: 12),
      PillButton(
        'Guardar medidas',
        icon: Ic.ruler,
        expand: true,
        kind: PillKind.secondary,
        onTap: usable && changed && problem == null
            ? () {
                HapticFeedback.selectionClick();
                FocusScope.of(context).unfocus();
                s.send(CarPins.measures, typed.join(','));
              }
            : null,
      ),
      if (problem != null) ...[
        const SizedBox(height: 8),
        Text(problem, style: T.small.copyWith(color: c.amber), textAlign: TextAlign.center),
      ],
    ]);
  }
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/letras.dart';
import '../../models/pins.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// El robot que escribe (desde carro-0.6) dice su lápiz al conectarse. El carrito 4x4 (carro-0.5) no lo dice.
bool isRobot(Session s) => s.values.containsKey(CarPins.pen);

/// Letra que está escribiendo y de cuántas («3/5» → (3, 5)), o null si no está escribiendo.
(int, int)? writingProgress(Session s) {
  final p = (s.values[CarPins.writing] ?? '0').split('/');
  if (p.length != 2) return null;
  final (i, n) = (int.tryParse(p[0]), int.tryParse(p[1]));
  return i == null || n == null || n <= 0 ? null : (i, n);
}

/// Medidas del robot (V30), con las de fábrica mientras la placa no las dice.
class RobotMeasures {
  final int wheelMm, trackMm, letterMm, penMs;
  const RobotMeasures(this.wheelMm, this.trackMm, this.letterMm, this.penMs);
  static const factory = RobotMeasures(65, 120, 30, 1000);

  /// Los mismos límites que acepta la placa.
  static const wheelRange = (20, 150), trackRange = (40, 400), letterRange = (10, 200), penRange = (100, 5000);

  static RobotMeasures of(Session s) {
    final v = (s.values[CarPins.measures] ?? '').split(',').map(int.tryParse).toList();
    if (v.length != 4 || v.any((x) => x == null)) return factory;
    return RobotMeasures(v[0]!, v[1]!, v[2]!, v[3]!);
  }

  String get wire => '$wheelMm,$trackMm,$letterMm,$penMs';

  /// «3 cm», «2,5 cm».
  String get letterText {
    final cm = letterMm / 10;
    return '${cm == cm.roundToDouble() ? cm.round() : cm.toStringAsFixed(1).replaceAll('.', ',')} cm';
  }
}

/// Último aviso de la placa, si es de hace menos de [within]: «ERR:otro telefono…» → «Otro telefono…».
String? recentNotice(Session s, {Duration within = const Duration(seconds: 6)}) {
  for (final l in s.log) {
    if (DateTime.now().difference(l.at) > within) return null;
    // Lo del saludo con la clave (una placa vieja responde «ERR:no entiendo AUTH») no le sirve al conductor.
    if (l.incoming && l.text.startsWith('ERR:') && l.text.length > 4 && !l.text.contains('AUTH')) {
      final t = l.text.substring(4);
      return t[0].toUpperCase() + t.substring(1);
    }
  }
  return null;
}

/// Tarjeta del bento: un ícono, qué es y cómo está. Encendida, toma su color de acento.
/// Con poco alto (o [row]) se acomoda en una fila.
class BentoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool active;
  final Color? accent;
  final VoidCallback? onTap;
  final bool row;
  const BentoTile({super.key, required this.icon, required this.label, this.value, this.active = false, this.accent, this.onTap, this.row = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tint = accent ?? c.text;
    final fg = active ? tint : c.text;
    return Semantics(
      button: true,
      toggled: active,
      enabled: onTap != null,
      label: value == null ? label : '$label: $value',
      excludeSemantics: true,
      child: Tap(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        scale: 0.96,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: onTap == null ? 0.4 : 1,
          child: Panel(
            radius: R.tile,
            color: active ? tint.withValues(alpha: 0.13) : c.surface,
            border: active ? tint : c.line,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: LayoutBuilder(builder: (context, box) {
              final words = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                if (value != null)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value!, style: T.heading.copyWith(color: fg), maxLines: 1),
                  ),
                if (value != null) const SizedBox(height: 3),
                Eyebrow(label, color: active ? tint : c.text2, maxLines: 1),
              ]);
              final glyph = AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(icon, key: ValueKey(icon), size: 24, color: fg),
              );
              if (row || box.maxHeight < 84) {
                return Row(children: [glyph, const SizedBox(width: 12), Expanded(child: words)]);
              }
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [glyph, const Spacer(), words]);
            }),
          ),
        ),
      ),
    );
  }
}

/// El lápiz: un toque lo baja o lo sube. Escribiendo, lo maneja el robot (se ve cómo sube y baja).
class PenTile extends StatelessWidget {
  final Session session;
  const PenTile({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    final down = s.values[CarPins.pen] == '1';
    final usable = s.connected && writingProgress(s) == null;
    return BentoTile(
      icon: down ? Ic.penFill : Ic.pen,
      label: 'Lápiz',
      value: down ? 'Abajo' : 'Arriba',
      active: down,
      accent: context.c.blue,
      onTap: usable ? () => s.send(CarPins.pen, down ? 0 : 1) : null,
    );
  }
}

/// Lo que va a dibujar el robot, con sus mismas letras. Escribiendo: hechas en color fuerte, la actual en
/// ámbar y las que faltan suaves. El punto verde es donde se pone el robot (mirando hacia la derecha).
class LetrasPreview extends StatelessWidget {
  final String text;
  final (int, int)? progress;
  const LetrasPreview({super.key, required this.text, this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: text.isEmpty ? 'Vista previa vacía' : 'Vista previa: $text',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(R.control)),
        child: text.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Aquí ves cómo lo va a dibujar', style: T.small.copyWith(color: c.text3), textAlign: TextAlign.center, maxLines: 2),
                ),
              )
            : CustomPaint(painter: _LetrasPainter(text, progress, c), size: Size.infinite),
      ),
    );
  }
}

class _LetrasPainter extends CustomPainter {
  final String text;
  final (int, int)? progress;
  final Palette c;
  _LetrasPainter(this.text, this.progress, this.c);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 14.0, unitsHigh = Letras.alto + 2.0; // de -1 a 7: la coma y la tilde de la Ñ
    final chars = text.split('');
    final unitsWide = chars.length * (Letras.ancho + Letras.espacio) - Letras.espacio.toDouble();
    final k = min((size.width - 2 * pad) / unitsWide, (size.height - 2 * pad) / unitsHigh);
    if (k <= 0) return;
    final ox = (size.width - unitsWide * k) / 2, base = (size.height + Letras.alto * k) / 2;
    Offset at(double x, double y) => Offset(ox + x * k, base - y * k);

    canvas.drawLine(at(-.5, -1.2), at(unitsWide + .5, -1.2), Paint()
      ..color = c.line2
      ..strokeWidth = 1);

    final (current, _) = progress ?? (0, 0);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = max(2.0, k * .32);
    var drawn = 0; // letras con trazos, como las cuenta la placa
    for (var i = 0; i < chars.length; i++) {
      final strokes = Letras.trazos(chars[i]);
      if (strokes.isEmpty) continue;
      drawn++;
      pen.color = progress == null || drawn < current ? c.text : (drawn == current ? c.amber : c.text3.withValues(alpha: .45));
      final dx = i * (Letras.ancho + Letras.espacio).toDouble();
      for (final s in strokes) {
        if (s.length == 1) {
          canvas.drawCircle(at(dx + s[0].$1, s[0].$2), pen.strokeWidth * .75, Paint()..color = pen.color);
          continue;
        }
        final path = Path()..moveTo(at(dx + s[0].$1, s[0].$2).dx, at(dx + s[0].$1, s[0].$2).dy);
        for (final p in s.skip(1)) {
          final o = at(dx + p.$1, p.$2);
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, pen);
      }
    }
    if (progress == null) canvas.drawCircle(at(0, 0), max(3.5, k * .35), Paint()..color = c.green); // donde va el robot
  }

  @override
  bool shouldRepaint(_LetrasPainter old) => old.text != text || old.progress != progress || old.c != c;
}

/// Escribir: el texto, cómo va a quedar y el botón. Mientras escribe, el avance letra por letra y «Parar».
/// [compact]: con el teclado abierto queda poco alto; la vista previa se achica o se esconde.
class WriteTile extends StatefulWidget {
  final Session session;
  final VoidCallback onOpenSettings;
  final VoidCallback onStop;
  const WriteTile({super.key, required this.session, required this.onOpenSettings, required this.onStop});

  @override
  State<WriteTile> createState() => _WriteTileState();
}

class _WriteTileState extends State<WriteTile> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  StreamSubscription? _sub;

  /// Lo que se mandó a escribir (se muestra mientras escribe, aunque el campo cambie).
  String _sent = '';

  /// Cómo terminó la última: «Listo» o por qué se canceló. Se borra al escribir otra cosa.
  String? _outcome;
  bool _outcomeOk = false;

  Session get _s => widget.session;

  @override
  void initState() {
    super.initState();
    // Solo un cambio del texto borra «Listo» (el campo también avisa cuando cambia el cursor o se habilita).
    var last = _field.text;
    _field.addListener(() {
      if (_field.text == last) return;
      last = _field.text;
      setState(() => _outcome = null);
    });
    _sub = _s.messages.listen((m) {
      const cancelled = 'escritura cancelada: ';
      if (m.kind == 'OK' && m.value == 'ESCRITO') {
        HapticFeedback.mediumImpact();
        _finish('Listo: escribió «$_sent»', ok: true);
      } else if (m.kind == 'OK' && m.value == 'escritura cancelada') {
        _finish('Se detuvo a mitad');
      } else if (m.kind == 'ERR' && m.value.startsWith(cancelled)) {
        _finish('Se detuvo: ${m.value.substring(cancelled.length)}');
      }
    });
  }

  void _finish(String outcome, {bool ok = false}) {
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      _outcomeOk = ok;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _write() {
    final text = Letras.normalizar(_field.text);
    if (text.isEmpty || !_s.connected) return;
    HapticFeedback.mediumImpact();
    _focus.unfocus();
    setState(() {
      _sent = text;
      _outcome = null;
    });
    _s.sendRaw('ESCRIBIR:$text');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = _s.connected;
    final progress = writingProgress(_s);
    final writing = progress != null;
    final typed = Letras.normalizar(_field.text);
    final shown = writing && _sent.isNotEmpty ? _sent : typed;
    final count = Letras.contar(shown);
    final m = RobotMeasures.of(_s);

    final status = switch (progress) {
      (final i, final n) => 'Letra $i de $n',
      null when _outcome != null => _outcome!,
      null when !on => 'Conecta el robot para escribir',
      null when typed.isEmpty => 'Pon el robot donde empieza la palabra, mirando hacia donde sigue',
      null => '$count ${count == 1 ? 'letra' : 'letras'} de ${m.letterText}',
    };
    final statusColor = writing ? c.amber : (_outcome == null ? c.text2 : (_outcomeOk ? c.green : c.amber));

    final button = writing
        ? PillButton('Parar', kind: PillKind.dangerFilled, icon: Ic.stop, onTap: widget.onStop)
        : PillButton('Escribir', icon: Ic.send, onTap: on && typed.isNotEmpty ? _write : null);

    final field = TextField(
      controller: _field,
      focusNode: _focus,
      enabled: on && !writing,
      maxLength: Letras.maxLetras,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) => _write(),
      style: T.heading.copyWith(letterSpacing: 2),
      decoration: InputDecoration(
        counterText: '',
        hintText: writing ? _sent : 'Escribe una palabra',
        hintStyle: T.heading.copyWith(color: c.text3, letterSpacing: .5),
        filled: true,
        fillColor: c.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.control), borderSide: BorderSide.none),
      ),
    );

    // Título y alto de las letras (un toque abre las medidas).
    final header = Row(children: [
      Icon(Ic.write, size: 18, color: c.text2),
      const SizedBox(width: 8),
      const Expanded(child: Eyebrow('Escribir', maxLines: 1)),
      const SizedBox(width: 12),
      Flexible(
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Tap(
            onTap: widget.onOpenSettings,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Ic.ruler, size: 15, color: c.text3),
              const SizedBox(width: 5),
              Flexible(
                child: Text('Letras de ${m.letterText}', style: T.small.copyWith(color: c.text3), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
      ),
    ]);

    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(builder: (context, box) {
        final roomy = box.maxHeight >= 210;
        // Con el teclado abierto puede quedar muy poco alto: solo el campo y su botón. El título y lo de abajo se
        // achican a nada en su lugar (no se quitan): así el campo no cambia de posición ni pierde el foco.
        final tiny = box.maxHeight < 130;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            child: tiny
                ? null
                : Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: header,
                  ),
          ),
          // El campo va siempre en el mismo lugar (una fila, primero): si cambiara de lugar al subir el teclado,
          // se rearmaría, perdería el foco y el teclado bajaría al instante. Con poco alto, el botón va a su lado.
          Row(children: [Expanded(child: field), if (!roomy) ...[const SizedBox(width: 10), button]]),
          if (!tiny) ...[
            if (box.maxHeight >= 150) ...[
              const SizedBox(height: 10),
              Expanded(child: LetrasPreview(text: shown, progress: progress)),
            ] else
              const Spacer(),
            const SizedBox(height: 10),
            if (writing) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (progress.$1 - .5) / progress.$2,
                  minHeight: 4,
                  color: c.amber,
                  backgroundColor: c.surface2,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  layoutBuilder: _alignStart,
                  child: Text(status, key: ValueKey(status), style: T.small.copyWith(color: statusColor), maxLines: 2),
                ),
              ),
              if (roomy) ...[const SizedBox(width: 10), button],
            ]),
          ],
        ]);
      }),
    );
  }
}

/// Manejar: el joystick en su tarjeta, y arriba qué está haciendo el robot.
class DriveTile extends StatelessWidget {
  final Session session;
  final String status;
  final Widget Function(double size) joystick;
  const DriveTile({super.key, required this.session, required this.status, required this.joystick});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Ic.steering, size: 18, color: c.text2),
          const SizedBox(width: 8),
          const Eyebrow('Manejar', maxLines: 1),
        ]),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          layoutBuilder: _alignStart,
          child: Text(status, key: ValueKey(status), style: T.callout, maxLines: 2),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Center(child: joystick(min(box.maxWidth, box.maxHeight).clamp(96.0, 184.0))),
          ),
        ),
      ]),
    );
  }
}

/// Un texto que cambia con AnimatedSwitcher queda alineado a la izquierda, como su título (por defecto va al centro).
Widget _alignStart(Widget? current, List<Widget> previous) =>
    Stack(alignment: AlignmentDirectional.centerStart, children: [...previous, ?current]);

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/protocol.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'glass.dart';

/// true mientras el panel debe mostrar la tarjeta de la clave en vez de dejar usar los controles.
bool showsClaveCard(Session s) => s.needsClave || (s.linked && s.keyed && s.clave == ClaveState.checking);

/// Tarjeta para escribir la clave de la casa, o crearla la primera vez.
class ClaveCard extends StatefulWidget {
  final Session session;
  const ClaveCard({super.key, required this.session});

  @override
  State<ClaveCard> createState() => _ClaveCardState();
}

class _ClaveCardState extends State<ClaveCard> {
  final _code = TextEditingController();

  Session get _s => widget.session;
  bool get _create => _s.clave == ClaveState.create;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final c = _code.text.trim();
    if (!validClave(c)) return;
    HapticFeedback.lightImpact();
    _create ? _s.createClave(c) : _s.enterClave(c);
    _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final checking = _s.clave == ClaveState.checking;
    final locked = _s.clave == ClaveState.locked;
    final accent = _create ? C.blue : C.orange;

    return Glass(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: ShapeDecoration(shape: squircle(16), color: accent.withValues(alpha: 0.14)),
            child: Icon(_create ? Icons.lock_open_rounded : Icons.lock_rounded, color: accent, size: 28),
          ),
        ),
        const SizedBox(height: 12),
        Text(_create ? 'Crea la clave de la casa' : 'Esta casa tiene clave', style: T.title2, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(
          _create
              ? 'Elige de 4 a 8 números. Cada teléfono nuevo la pedirá antes de poder controlar la casa. Anótala.'
              : 'Escríbela para controlar la casa. Este teléfono la recordará.',
          style: T.subhead.copyWith(color: C.label2),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ClaveField(controller: _code, visible: _create, enabled: !checking && !locked, onSubmitted: _submit, onChanged: () => setState(() {})),
        if (_s.claveMessage != null) ...[
          const SizedBox(height: 8),
          Text(_s.claveMessage!, style: T.footnote.copyWith(color: locked ? C.orange : C.red), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: checking || locked || !validClave(_code.text.trim()) ? null : _submit,
          child: checking
              ? const CupertinoActivityIndicator(color: Colors.white)
              : Text(_create ? 'Guardar clave' : 'Entrar'),
        ),
        const SizedBox(height: 12),
        const Text(
          '¿La olvidaron? Mantén presionado el botón BOOT del ESP32 por 5 segundos: las luces parpadean y la casa queda sin clave.',
          style: T.footnote,
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

/// Campo grande para la clave: solo números, de 4 a 8.
class ClaveField extends StatelessWidget {
  final TextEditingController controller;
  final bool visible;
  final bool enabled;
  final VoidCallback onSubmitted;
  final VoidCallback onChanged;
  const ClaveField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onChanged,
    this.visible = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: ShapeDecoration(shape: squircle(14), color: const Color(0x14787880)),
      child: TextField(
        controller: controller,
        enabled: enabled,
        autofocus: false,
        obscureText: !visible,
        obscuringCharacter: '•',
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 8,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: T.title2.copyWith(letterSpacing: 8, fontFeatures: const [FontFeature.tabularFigures()]),
        decoration: const InputDecoration(counterText: '', hintText: '••••••', border: InputBorder.none),
        onChanged: (_) => onChanged(),
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}

/// Hoja para cambiar la clave de la casa estando conectado.
Future<void> showChangeClaveSheet(BuildContext context, Session session) =>
    showGlassSheet<void>(context, (_) => _ChangeClaveSheet(session: session));

class _ChangeClaveSheet extends StatefulWidget {
  final Session session;
  const _ChangeClaveSheet({required this.session});

  @override
  State<_ChangeClaveSheet> createState() => _ChangeClaveSheetState();
}

class _ChangeClaveSheetState extends State<_ChangeClaveSheet> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _save() {
    final c = _code.text.trim();
    if (!validClave(c)) return;
    widget.session.changeClave(c);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Cambiar la clave', style: T.title2),
            SizedBox(height: 2),
            Text('De 4 a 8 números. Los otros teléfonos tendrán que escribir la nueva.', style: T.footnote),
          ]),
        ),
        const SizedBox(height: 18),
        ClaveField(controller: _code, visible: true, onSubmitted: _save, onChanged: () => setState(() {})),
        const SizedBox(height: 18),
        FilledButton(onPressed: validClave(_code.text.trim()) ? _save : null, child: const Text('Guardar clave nueva')),
      ]),
    );
  }
}

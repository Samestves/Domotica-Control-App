import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/protocol.dart';
import '../../models/device.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import 'kit.dart';

/// true mientras el panel debe mostrar la tarjeta de la clave en vez de dejar usar los controles.
bool showsClaveCard(Session s) => s.needsClave || (s.linked && s.keyed && s.clave == ClaveState.checking);

/// Tarjeta para escribir la clave de la placa (casa o carrito), o crearla la primera vez.
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
    final c = context.c;
    final checking = _s.clave == ClaveState.checking;
    final locked = _s.clave == ClaveState.locked;
    final car = _s.device.profile == Profile.carro;
    final what = car ? 'el carrito' : 'la casa';
    final of = car ? 'del carrito' : 'de la casa';
    final thisOne = car ? 'Este carrito' : 'Esta casa';

    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Icon(_create ? Ic.lockOpen : Ic.lock, size: 40, color: c.text),
        const SizedBox(height: 16),
        Eyebrow(_create ? 'Primera vez' : 'Clave $of'),
        const SizedBox(height: 6),
        Text(_create ? 'Crea la clave $of' : '$thisOne tiene clave', style: T.title),
        const SizedBox(height: 8),
        Text(
          _create
              ? 'Elige de 4 a 8 números. Cada teléfono nuevo la pedirá antes de poder controlar $what. Anótala.'
              : 'Escríbela para controlar $what. Este teléfono la recordará.',
          style: T.small.copyWith(color: c.text2),
        ),
        const SizedBox(height: 20),
        ClaveField(controller: _code, visible: _create, enabled: !checking && !locked, onSubmitted: _submit, onChanged: () => setState(() {})),
        if (_s.claveMessage != null) ...[
          const SizedBox(height: 10),
          Text(_s.claveMessage!, style: T.small.copyWith(color: locked ? c.amber : c.red)),
        ],
        const SizedBox(height: 16),
        PillButton(
          checking ? 'Comprobando…' : (_create ? 'Guardar clave' : 'Entrar'),
          expand: true,
          onTap: checking || locked || !validClave(_code.text.trim()) ? null : _submit,
        ),
        const SizedBox(height: 16),
        Text(
          car
              ? '¿La olvidaron? Mantén presionado el botón BOOT del ESP32 del carrito por 5 segundos: queda sin clave.'
              : '¿La olvidaron? Mantén presionado el botón BOOT del ESP32 por 5 segundos: las luces parpadean y la casa queda sin clave.',
          style: T.small.copyWith(color: c.text3),
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
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(R.control), border: Border.all(color: c.line2)),
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: !visible,
        obscuringCharacter: '•',
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 8,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: T.title.copyWith(letterSpacing: 10, fontFeatures: const [FontFeature.tabularFigures()]),
        decoration: const InputDecoration(counterText: '', hintText: '••••••', border: InputBorder.none),
        onChanged: (_) => onChanged(),
        onSubmitted: (_) => onSubmitted(),
      ),
    );
  }
}

/// Hoja para cambiar la clave de la casa o del carrito estando conectado. Espera a que la placa la confirme.
Future<void> showChangeClaveSheet(BuildContext context, Session session) => showAppSheet<void>(context, (_) => _ChangeClaveSheet(session: session));

class _ChangeClaveSheet extends StatefulWidget {
  final Session session;
  const _ChangeClaveSheet({required this.session});

  @override
  State<_ChangeClaveSheet> createState() => _ChangeClaveSheetState();
}

class _ChangeClaveSheetState extends State<_ChangeClaveSheet> {
  final _code = TextEditingController();

  /// true desde que esta hoja envió la clave: solo entonces muestra cómo va (no un cambio viejo).
  bool _sent = false;

  Session get _s => widget.session;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _save() {
    final c = _code.text.trim();
    if (!validClave(c) || !_s.connected) return;
    HapticFeedback.lightImpact();
    _sent = true;
    _s.changeClave(c);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        final c = context.c;
        final step = _sent ? _s.claveChange : null;
        final what = _s.device.profile == Profile.carro ? 'el carrito' : 'la casa';

        if (step == ClaveChange.done) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Ic.checkCircle, size: 40, color: c.green),
                  const SizedBox(height: 14),
                  const SheetHeader(eyebrow: 'Seguridad', title: 'Clave cambiada'),
                  const SizedBox(height: 6),
                  Text(
                    'Este teléfono ya la recuerda. Los otros tendrán que escribir la nueva la próxima vez que se conecten a $what. Anótala.',
                    style: T.small.copyWith(color: c.text2),
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              PillButton('Listo', expand: true, onTap: () => Navigator.pop(context)),
            ]),
          );
        }

        final saving = step == ClaveChange.saving;
        final offline = !_s.connected && !saving;
        final problem = step == ClaveChange.failed ? _s.claveChangeError : (offline ? 'Se desconectó. Conéctate otra vez para cambiarla.' : null);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: SheetHeader(eyebrow: 'Seguridad', title: 'Cambiar la clave', detail: 'De 4 a 8 números. Los otros teléfonos tendrán que escribir la nueva.'),
            ),
            const SizedBox(height: 20),
            ClaveField(controller: _code, visible: true, enabled: !saving && !offline, onSubmitted: _save, onChanged: () => setState(() {})),
            if (problem != null) ...[
              const SizedBox(height: 10),
              Text(problem, style: T.small.copyWith(color: offline ? c.amber : c.red)),
            ],
            const SizedBox(height: 20),
            PillButton(
              saving ? 'Guardando…' : (step == ClaveChange.failed ? 'Intentar otra vez' : 'Guardar clave nueva'),
              leading: saving ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.onInverse)) : null,
              expand: true,
              onTap: !saving && !offline && validClave(_code.text.trim()) ? _save : null,
            ),
          ]),
        );
      },
    );
  }
}

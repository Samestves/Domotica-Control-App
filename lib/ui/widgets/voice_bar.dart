import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import '../../voice/voice_controller.dart';
import '../theme.dart';
import 'kit.dart';

/// Barra inferior para dar órdenes por voz: el micrófono y el resultado.
/// Verde = la placa confirmó · rojo = no respondió · ámbar = no se entendió la frase.
class VoiceBar extends StatelessWidget {
  final Session session;
  final VoiceController voice;
  const VoiceBar({super.key, required this.session, required this.voice});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) => Row(children: [
        Expanded(child: _Status(voice: voice, connected: session.connected)),
        const SizedBox(width: 14),
        _MicButton(
          listening: voice.listening,
          // Mientras dice «Enviando», el micrófono espera a que la placa confirme.
          enabled: (session.connected || voice.listening) && voice.status != VoiceStatus.working,
          onTap: () {
            HapticFeedback.mediumImpact();
            voice.toggle(session);
          },
        ),
      ]),
    );
  }
}

class _Status extends StatelessWidget {
  final VoiceController voice;
  final bool connected;
  const _Status({required this.voice, required this.connected});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final heard = voice.heard.isEmpty ? null : '«${voice.heard}»';
    final (IconData? icon, Color color, String label, String? detail) = switch (voice.status) {
      VoiceStatus.idle => (null, c.text2, connected ? 'Toca y habla' : 'Conecta la casa para usar la voz', connected ? '«Enciende la luz de la cocina»' : null),
      VoiceStatus.starting => (null, c.text2, 'Abriendo el micrófono', 'Un momento…'),
      VoiceStatus.listening => (null, c.red, 'Escuchando', heard ?? 'Habla ahora'),
      VoiceStatus.working => (null, c.text, 'Enviando', heard),
      VoiceStatus.done => (Ic.checkCircle, c.green, voice.message, heard),
      VoiceStatus.failed => (Ic.warning, c.red, voice.message, heard),
      VoiceStatus.unclear => (Ic.warning, c.amber, voice.message, heard == null ? null : 'Escuché: $heard'),
    };
    final result = const [VoiceStatus.done, VoiceStatus.failed, VoiceStatus.unclear].contains(voice.status);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Row(key: ValueKey('${voice.status}${voice.message}'), children: [
        if (voice.status == VoiceStatus.listening) ...[_Wave(level: voice.level), const SizedBox(width: 12)],
        if (voice.status == VoiceStatus.working)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.6, color: c.text)),
          ),
        if (icon != null) ...[Icon(icon, color: color, size: 24), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            result
                ? Text(label, style: T.callout.copyWith(color: color), maxLines: 3)
                : Eyebrow(label, color: color),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(detail, style: T.small.copyWith(color: c.text2), maxLines: 2),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Barras que suben y bajan con el volumen de la voz mientras escucha.
class _Wave extends StatefulWidget {
  final double level;
  const _Wave({required this.level});

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.c.red;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 4; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            width: 3,
            height: 5 + 17 * (0.15 + 0.85 * widget.level) * (0.55 + 0.45 * sin(_a.value * 2 * pi + i * 1.3)).abs(),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
      ]),
    );
  }
}

/// Botón redondo del micrófono. Rojo y con un anillo que late mientras escucha.
class _MicButton extends StatefulWidget {
  final bool listening;
  final bool enabled;
  final VoidCallback onTap;
  const _MicButton({required this.listening, required this.enabled, required this.onTap});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(_MicButton old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_pulse.isAnimating) _pulse.repeat();
    if (!widget.listening) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bg = widget.listening ? c.red : c.inverse;
    final fg = widget.listening ? Colors.white : c.onInverse;
    return Semantics(
      button: true,
      label: widget.listening ? 'Dejar de escuchar' : 'Dar una orden por voz',
      child: Tap(
        onTap: widget.enabled ? widget.onTap : null,
        scale: 0.92,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: widget.listening ? Border.all(color: c.red.withValues(alpha: 1 - _pulse.value), width: 1 + 6 * _pulse.value) : null,
              ),
              padding: const EdgeInsets.all(3),
              child: child,
            ),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
              child: Icon(widget.listening ? Ic.stop : Ic.micFill, color: fg, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

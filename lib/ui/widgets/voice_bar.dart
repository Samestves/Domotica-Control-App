import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/app_state.dart';
import '../../voice/voice_controller.dart';
import '../theme.dart';

/// Barra inferior para dar órdenes por voz: el micrófono y el resultado.
/// Verde = la placa confirmó · rojo = no respondió · naranja = no se entendió la frase.
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
        const SizedBox(width: 12),
        _MicButton(
          listening: voice.listening,
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
    final (IconData? icon, Color color, String title, String? detail) = switch (voice.status) {
      VoiceStatus.idle => (null, C.label2, connected ? 'Toca el micrófono y habla' : 'Conecta la casa para usar la voz', connected ? '«Abre la puerta principal»' : null),
      VoiceStatus.listening => (null, C.red, 'Escuchando…', voice.heard.isEmpty ? null : '«${voice.heard}»'),
      VoiceStatus.working => (null, C.blue, 'Enviando…', '«${voice.heard}»'),
      VoiceStatus.done => (Icons.check_circle_rounded, C.green, voice.message, '«${voice.heard}»'),
      VoiceStatus.failed => (Icons.error_rounded, C.red, voice.message, voice.heard.isEmpty ? null : '«${voice.heard}»'),
      VoiceStatus.unclear => (Icons.help_rounded, C.orange, voice.message, voice.heard.isEmpty ? null : 'Escuché: «${voice.heard}»'),
    };
    final tinted = voice.status != VoiceStatus.idle && voice.status != VoiceStatus.listening;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: ShapeDecoration(shape: squircle(16), color: tinted ? color.withValues(alpha: 0.12) : Colors.transparent),
      child: Row(children: [
        if (voice.status == VoiceStatus.working)
          const Padding(padding: EdgeInsets.only(right: 10), child: CupertinoActivityIndicator(radius: 9))
        else if (icon != null)
          Padding(padding: const EdgeInsets.only(right: 10), child: Icon(icon, color: color, size: 24)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: T.subhead.copyWith(color: tinted ? color : C.label, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (detail != null) Text(detail, style: T.footnote, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

/// Botón redondo del micrófono. Rojo y latiendo mientras escucha.
class _MicButton extends StatefulWidget {
  final bool listening;
  final VoidCallback onTap;
  const _MicButton({required this.listening, required this.onTap});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void didUpdateWidget(_MicButton old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!widget.listening) _pulse.stop();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.listening ? C.red : C.blue;
    return Semantics(
      button: true,
      label: widget.listening ? 'Dejar de escuchar' : 'Dar una orden por voz',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 12 + (widget.listening ? _pulse.value * 14 : 0),
                  spreadRadius: widget.listening ? _pulse.value * 4 : 0,
                ),
              ],
            ),
            child: child,
          ),
          child: Icon(widget.listening ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

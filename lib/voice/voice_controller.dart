import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/controls.dart';
import '../state/app_state.dart';
import 'voice_commands.dart';
import 'voice_run.dart';

enum VoiceStatus {
  idle,
  listening,

  /// Orden enviada; esperando que la placa la confirme.
  working,

  /// La placa confirmó.
  done,

  /// No se entendió la frase.
  unclear,

  /// La placa no respondió, o respondió con un error.
  failed,
}

/// Escucha una frase con el reconocimiento de voz del teléfono (el mismo de Google),
/// la convierte en una orden para la casa, espera la confirmación de la placa y la dice en voz alta.
class VoiceController extends ChangeNotifier {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _ready = false;
  String? _locale;

  VoiceStatus status = VoiceStatus.idle;

  /// Lo que va entendiendo mientras hablas.
  String heard = '';

  /// Resultado para mostrar: «Puerta principal abierta», «La casa no respondió»...
  String message = '';

  Session? _session;
  bool _handled = false;
  Timer? _clear;

  bool get listening => status == VoiceStatus.listening;

  Future<bool> _init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(onStatus: _onStatus, onError: (_) => _finishListening());
    if (!_ready) return false;
    final locales = await _stt.locales();
    final spanish = locales.where((l) => l.localeId.toLowerCase().startsWith('es')).map((l) => l.localeId).toList();
    final system = await _stt.systemLocale();
    _locale = (system != null && system.localeId.toLowerCase().startsWith('es')) ? system.localeId : (spanish.isEmpty ? null : spanish.first);
    await _tts.setLanguage('es-ES');
    await _tts.setSpeechRate(0.5);
    return true;
  }

  /// Toca el micrófono: empieza a escuchar. Si ya escuchaba, termina y procesa lo que oyó.
  Future<void> toggle(Session s) async {
    if (listening) return _stop();
    _session = s;
    _clear?.cancel();
    if (!await _init()) {
      _show(VoiceStatus.failed, 'No puedo usar el micrófono. Revisa el permiso en Ajustes.');
      return;
    }
    heard = '';
    message = '';
    _handled = false;
    status = VoiceStatus.listening;
    notifyListeners();
    await _stt.listen(
      onResult: (r) {
        heard = r.recognizedWords;
        notifyListeners();
        if (r.finalResult) _finishListening();
      },
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
  }

  Future<void> _stop() async {
    await _stt.stop();
    // Si el reconocedor no manda el resultado final, se usa lo último que entendió.
    Timer(const Duration(milliseconds: 800), _finishListening);
  }

  void _onStatus(String s) {
    if (s == 'done' || s == 'notListening') Timer(const Duration(milliseconds: 400), _finishListening);
  }

  /// Termina de escuchar una sola vez y procesa la frase.
  void _finishListening() {
    if (_handled || status != VoiceStatus.listening) return;
    _handled = true;
    final s = _session;
    if (s != null) handle(s, heard);
  }

  /// Interpreta una frase y la ejecuta. Público para poder escribir la orden en vez de decirla.
  Future<void> handle(Session s, String phrase) async {
    heard = phrase;
    final parsed = parseCasaCommand(phrase, isEnabled: (c) => c.isEnabledOn(s.device));
    final cmd = parsed.command;
    if (cmd == null) {
      _show(VoiceStatus.unclear, parsed.problem!);
      return;
    }
    status = VoiceStatus.working;
    message = cmd.done;
    notifyListeners();
    final problem = await runVoiceCommand(s, cmd);
    problem == null ? _show(VoiceStatus.done, cmd.done) : _show(VoiceStatus.failed, problem);
  }

  void _show(VoiceStatus st, String text) {
    status = st;
    message = text;
    notifyListeners();
    if (st == VoiceStatus.done || st == VoiceStatus.failed || st == VoiceStatus.unclear) {
      _tts.speak(st == VoiceStatus.unclear ? 'No entendí' : text).ignore();
    }
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 6), () {
      status = VoiceStatus.idle;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _clear?.cancel();
    _stt.cancel();
    _tts.stop();
    super.dispose();
  }
}

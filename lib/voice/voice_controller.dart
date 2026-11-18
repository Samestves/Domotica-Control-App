import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/controls.dart';
import '../state/app_state.dart';
import 'voice_commands.dart';
import 'voice_run.dart';

enum VoiceStatus {
  idle,

  /// Abriendo el micrófono: todavía no conviene hablar.
  starting,
  listening,

  /// Orden enviada; esperando que la placa la confirme.
  working,

  /// La placa confirmó.
  done,

  /// No se escuchó nada, o no se entendió la frase.
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
  Timer? _clear;

  /// Cada toque del micrófono es un turno. Los avisos del reconocedor de un turno anterior se ignoran.
  int _turn = 0;
  bool _handled = false;
  bool _retried = false;

  /// Cuánto esperar el resultado final después de que el reconocedor deja de escuchar.
  static const _finalWait = Duration(milliseconds: 1500);

  bool get listening => status == VoiceStatus.listening || status == VoiceStatus.starting;

  Future<bool> _init() async {
    if (_ready) return true;
    _ready = await _stt.initialize(onStatus: _onStatus, onError: _onError);
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
    await _tts.stop(); // que el micrófono no escuche a la propia app
    if (!await _init()) {
      _show(VoiceStatus.failed, 'No puedo usar el micrófono. Revisa el permiso en Ajustes.');
      return;
    }
    _turn++;
    _retried = false;
    heard = '';
    message = '';
    _handled = false;
    status = VoiceStatus.starting;
    notifyListeners();
    // Por si el teléfono no avisa que abrió el micrófono.
    final turn = _turn;
    Timer(const Duration(seconds: 2), () {
      if (turn != _turn || status != VoiceStatus.starting) return;
      status = VoiceStatus.listening;
      notifyListeners();
    });
    await _listen();
  }

  Future<void> _listen() async {
    final turn = _turn;
    await _stt.listen(
      onResult: (r) {
        if (turn != _turn) return;
        if (status == VoiceStatus.starting) status = VoiceStatus.listening;
        if (r.recognizedWords.isNotEmpty) heard = r.recognizedWords;
        notifyListeners();
        if (r.finalResult) _finish(turn);
      },
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation, // frases largas con varias órdenes
      ),
    );
  }

  Future<void> _stop() async {
    final turn = _turn;
    await _stt.stop();
    Timer(_finalWait, () => _finish(turn));
  }

  void _onStatus(String s) {
    final turn = _turn;
    if (s == 'listening' && status == VoiceStatus.starting) {
      // Ahora sí: el micrófono está abierto.
      status = VoiceStatus.listening;
      HapticFeedback.lightImpact();
      notifyListeners();
    }
    // Dejó de escuchar: se espera un poco el resultado final antes de decidir.
    if ((s == 'done' || s == 'notListening') && status == VoiceStatus.listening) {
      Timer(_finalWait, () => _finish(turn));
    }
  }

  void _onError(SpeechRecognitionError e) {
    final turn = _turn;
    // El reconocedor seguía ocupado con el turno anterior: se reintenta una vez.
    if ((e.errorMsg == 'error_busy' || e.errorMsg == 'error_client') && !_retried && heard.isEmpty) {
      _retried = true;
      Timer(const Duration(milliseconds: 400), () {
        if (turn == _turn && listening) _listen();
      });
      return;
    }
    if (e.errorMsg == 'error_network' || e.errorMsg == 'error_network_timeout' || e.errorMsg == 'error_server') {
      _turn++;
      _show(VoiceStatus.failed, 'El reconocimiento de voz necesita internet, o el paquete de voz en español descargado.', speak: false);
      return;
    }
    // Silencio o algo que no se reconoció: se usa lo que haya escuchado.
    Timer(const Duration(milliseconds: 300), () => _finish(turn));
  }

  /// Termina el turno una sola vez y procesa la frase.
  void _finish(int turn) {
    if (turn != _turn || _handled || !listening) return;
    _handled = true;
    final s = _session;
    if (heard.trim().isEmpty) {
      _show(VoiceStatus.unclear, 'No te escuché. Toca el micrófono y habla cuando diga «Escuchando».', speak: false);
    } else if (s != null) {
      handle(s, heard);
    }
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

  void _show(VoiceStatus st, String text, {bool speak = true}) {
    status = st;
    message = text;
    notifyListeners();
    if (speak) _tts.speak(text).ignore();
    _clear?.cancel();
    _clear = Timer(const Duration(seconds: 8), () {
      if (listening || status == VoiceStatus.working) return;
      status = VoiceStatus.idle;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _turn++;
    _clear?.cancel();
    _stt.cancel();
    _tts.stop();
    super.dispose();
  }
}

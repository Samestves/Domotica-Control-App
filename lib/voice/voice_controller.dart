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

  /// Volumen del micrófono de 0 a 1, para que las barritas se muevan con la voz.
  double level = 0;

  /// Resultado para mostrar: «Puerta principal abierta», «La casa no respondió»...
  String message = '';

  Session? _session;
  Timer? _clear;

  /// Cada toque del micrófono es un turno. Los avisos del reconocedor de un turno anterior se ignoran.
  int _turn = 0;
  bool _handled = false;
  bool _retried = false;

  /// Cuánto esperar el resultado final después de que el reconocedor deja de escuchar.
  static const _finalWait = Duration(milliseconds: 700);

  // El fin de la frase lo decide Android (deja de escuchar ~1 s después de que te callas).
  // No se usa «pauseFor»: el plugin lo cuenta desde que se abre el micrófono, y si tardabas
  // en empezar a hablar, cerraba el micrófono sin haberte escuchado.

  /// Si lo escuchado ya es una orden completa y no cambia en este tiempo, se ejecuta sin esperar el silencio.
  static const _stableFor = Duration(milliseconds: 850);
  Timer? _stable;

  /// Último error del reconocedor en este turno (para explicar bien por qué no entendió).
  String? _lastError;

  /// Cronómetro de cada orden, para medir dónde se va el tiempo (sale en el registro del teléfono).
  final _clock = Stopwatch();
  void _mark(String what) => debugPrint('[voz] +${_clock.elapsedMilliseconds} ms  $what');

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
    await _tts.setSpeechRate(0.56);
    await _tts.awaitSpeakCompletion(false);
    return true;
  }

  /// Prepara el reconocimiento y la voz antes del primer toque, para que la primera orden no espere.
  Future<void> warmUp() async {
    try {
      await _init();
    } catch (_) {
      // Si falla aquí, se vuelve a intentar al tocar el micrófono y ahí se explica el problema.
    }
  }

  /// Toca el micrófono: empieza a escuchar. Si ya escuchaba, termina y procesa lo que oyó.
  Future<void> toggle(Session s) async {
    if (listening) return _stop();
    _session = s;
    _clear?.cancel();
    _stable?.cancel();
    _clock
      ..reset()
      ..start();
    await _tts.stop(); // que el micrófono no escuche a la propia app
    if (!await _init()) {
      _show(VoiceStatus.failed, 'No puedo usar el micrófono. Revisa el permiso en Ajustes.');
      return;
    }
    _turn++;
    _retried = false;
    heard = '';
    message = '';
    level = 0;
    _lastError = null;
    _handled = false;
    status = VoiceStatus.starting;
    notifyListeners();
    // «Escuchando» aparece cuando llega sonido del micrófono (ahí sí está listo).
    // Por si el teléfono no informa el volumen, se pasa igual a «Escuchando» a los 1,2 s.
    final turn = _turn;
    Timer(const Duration(milliseconds: 1200), () {
      if (turn != _turn || status != VoiceStatus.starting) return;
      _mark('sin datos de volumen: paso a «Escuchando»');
      status = VoiceStatus.listening;
      notifyListeners();
    });
    await _listen();
  }

  /// Volumen del micrófono (dB que da Android, más o menos de −2 a 10).
  void _onLevel(int turn, double db) {
    if (turn != _turn) return;
    if (status == VoiceStatus.starting) {
      _mark('micrófono listo (llegó sonido)');
      status = VoiceStatus.listening;
      HapticFeedback.lightImpact();
    }
    final v = ((db + 2) / 12).clamp(0.0, 1.0);
    if ((v - level).abs() < 0.04 && status == VoiceStatus.listening) return;
    level = v;
    notifyListeners();
  }

  Future<void> _listen() async {
    final turn = _turn;
    await _stt.listen(
      onResult: (r) {
        if (turn != _turn) return;
        if (status == VoiceStatus.starting) status = VoiceStatus.listening;
        if (r.recognizedWords.isNotEmpty) {
          if (heard.isEmpty) _mark('primeras palabras');
          heard = r.recognizedWords;
        }
        notifyListeners();
        if (r.finalResult) {
          _mark('resultado final: «$heard»');
          _finish(turn);
        } else {
          _maybeRunEarly(turn);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        listenFor: const Duration(seconds: 15),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation, // frases largas con varias órdenes
      ),
      onSoundLevelChange: (db) => _onLevel(turn, db),
    );
    _mark('listen() pedido');
  }

  Future<void> _stop() async {
    final turn = _turn;
    _stable?.cancel();
    await _stt.stop();
    Timer(_finalWait, () => _finish(turn));
  }

  /// Palabras con las que una frase todavía no puede haber terminado («enciende la luz de…»).
  static const _dangling = {
    'de', 'del', 'la', 'el', 'los', 'las', 'y', 'e', 'al', 'a', 'en', 'con', 'por', 'para', 'que', 'un', 'una', 'mi',
    'luego', 'después', 'despues', 'también', 'tambien', 'además', 'ademas', 'todas', 'todos',
  };

  /// Si lo que va escuchando ya es una orden completa y deja de cambiar, la ejecuta sin esperar el silencio final.
  void _maybeRunEarly(int turn) {
    _stable?.cancel();
    final s = _session;
    final text = heard.trim();
    if (s == null || text.isEmpty) return;
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    if (_dangling.contains(words.last)) return;
    if (parseCasaCommand(text, isEnabled: (c) => c.isEnabledOn(s.device)).command == null) return;
    _stable = Timer(_stableFor, () {
      if (turn != _turn || heard.trim() != text || _handled || !listening) return;
      _mark('frase completa: no espero el silencio');
      _stt.stop();
      _finish(turn);
    });
  }

  void _onStatus(String s) {
    final turn = _turn;
    _mark('estado: $s');
    // Ojo: Android dice «listening» apenas se pide, antes de estar listo. Por eso no se usa aquí.
    // Dejó de escuchar: se espera un poco el resultado final antes de decidir.
    if ((s == 'done' || s == 'notListening') && status == VoiceStatus.listening) {
      Timer(_finalWait, () => _finish(turn));
    }
  }

  void _onError(SpeechRecognitionError e) {
    final turn = _turn;
    _mark('error: ${e.errorMsg}');
    _lastError = e.errorMsg;
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
    _stable?.cancel();
    final s = _session;
    if (heard.trim().isEmpty) {
      final noMatch = _lastError == 'error_no_match';
      _show(
        VoiceStatus.unclear,
        noMatch ? 'Te escuché, pero no entendí las palabras. Habla un poco más cerca del teléfono.' : 'No te escuché. Toca el micrófono y habla cuando diga «Escuchando».',
        speak: false,
      );
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
    _mark('orden enviada');
    final problem = await runVoiceCommand(s, cmd);
    _mark(problem == null ? 'la placa confirmó' : 'sin confirmar: $problem');
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
    _stable?.cancel();
    _stt.cancel();
    _tts.stop();
    super.dispose();
  }
}

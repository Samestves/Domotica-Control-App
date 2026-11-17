import '../models/controls.dart';

/// Lo que la app debe enviar a la placa por una frase, y lo que la placa debe responder para confirmarlo.
class VoiceCommand {
  /// Mensajes a enviar: pin virtual → valor.
  final Map<int, int> sends;

  /// Respuestas que confirman que la placa lo hizo: pin virtual → valor esperado.
  final Map<int, int> expects;

  /// Frase para mostrar y decir en voz alta cuando la placa lo confirma, por ejemplo «Puerta principal abierta».
  final String done;

  const VoiceCommand({required this.sends, required this.expects, required this.done});
}

/// Resultado de interpretar una frase: una orden, o el motivo por el que no se entendió.
class VoiceParse {
  final VoiceCommand? command;
  final String? problem;
  const VoiceParse.ok(VoiceCommand this.command) : problem = null;
  const VoiceParse.fail(String this.problem) : command = null;
}

enum _Action { on, off, open, close, half, set }

/// Entiende frases en español para la casa del grupo:
/// «abre la puerta principal», «enciende la luz de la cocina», «apaga todas las luces»,
/// «baja la persiana de la sala a la mitad», «sube la persiana del cuarto al 30 por ciento», «arma la alarma».
///
/// [isEnabled] dice si un control está conectado en la maqueta; los que no, se avisan en vez de enviarse.
VoiceParse parseCasaCommand(String heard, {bool Function(ControlSpec)? isEnabled}) {
  final text = normalize(heard);
  if (text.isEmpty) return const VoiceParse.fail('No escuché nada.');
  final words = text.split(' ');
  bool has(Iterable<String> options) => options.any((o) => o.contains(' ') ? ' $text '.contains(' $o ') : words.contains(o));

  // Seguridad
  final aboutAlarm = has(const ['alarma', 'seguridad', 'sirena']);
  if (aboutAlarm) {
    if (has(const ['desarma', 'desarmar', 'desactiva', 'desactivar', 'apaga', 'apagar', 'quita', 'quitar', 'deten', 'para'])) {
      return const VoiceParse.ok(VoiceCommand(sends: {CasaPins.armed: 0}, expects: {CasaPins.armed: 0}, done: 'Seguridad desarmada'));
    }
    if (has(const ['arma', 'armar', 'activa', 'activar', 'pon', 'enciende', 'prende', 'conecta'])) {
      return const VoiceParse.ok(VoiceCommand(sends: {CasaPins.armed: 1}, expects: {CasaPins.armed: 1}, done: 'Seguridad armada'));
    }
    return const VoiceParse.fail('¿Armo o desarmo la seguridad?');
  }

  final action = _actionOf(has);
  if (action == null) return VoiceParse.fail('No sé qué hacer con «$heard».');

  final room = _roomOf(has);

  // Todas las luces: «apaga todo», «enciende las luces» (sin decir dónde)
  final allWords = has(const ['todo', 'toda', 'todas']) || (has(const ['luces']) && room == null);
  if (allWords && (action == _Action.on || action == _Action.off)) {
    final on = action == _Action.on ? 1 : 0;
    final lights = casaControls.where((c) => c.kind == ControlKind.light && (isEnabled?.call(c) ?? true));
    return VoiceParse.ok(VoiceCommand(
      sends: {CasaPins.allLights: on},
      expects: {for (final c in lights) c.vpin: on},
      done: on == 1 ? 'Todas las luces encendidas' : 'Todas las luces apagadas',
    ));
  }

  final kind = _kindOf(has, action);
  if (kind == null) return const VoiceParse.fail('¿Qué quieres mover: una luz, una puerta o una persiana?');

  var targets = casaControls.where((c) => c.kind == kind).toList();
  if (room != null) {
    targets = targets.where((c) => c.room == room).toList();
  } else if (targets.length > 1) {
    return VoiceParse.fail('¿${_noun(kind)} de qué parte de la casa?');
  }
  // «persiana 1», «luz dos»
  final number = _numberOf(words);
  if (number != null && targets.length > 1) {
    final pick = targets.where((c) => c.label.endsWith(' $number')).toList();
    if (pick.isNotEmpty) targets = pick;
  }
  if (targets.isEmpty) return VoiceParse.fail('No hay ${_noun(kind).toLowerCase()} en ${room ?? 'esa parte'}.');

  final off = targets.where((c) => !(isEnabled?.call(c) ?? true)).toList();
  if (off.length == targets.length) return VoiceParse.fail('${_name(off.first)} está marcada como no conectada.');
  targets = targets.where((c) => isEnabled?.call(c) ?? true).toList();

  final value = _valueFor(kind, action, words);
  if (value == null) return VoiceParse.fail('Esa acción no sirve para ${_noun(kind).toLowerCase()}.');
  return VoiceParse.ok(VoiceCommand(
    sends: {for (final c in targets) c.vpin: value},
    expects: {for (final c in targets) c.vpin: value},
    done: _doneText(targets, kind, value),
  ));
}

/// Minúsculas, sin tildes ni signos: «¡Abre la PUERTA!» → «abre la puerta».
String normalize(String s) {
  const from = 'áéíóúüñ', to = 'aeiouun';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9% ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

_Action? _actionOf(bool Function(Iterable<String>) has) {
  if (has(const ['mitad', 'medio', 'media'])) return _Action.half;
  if (has(const ['por ciento', '%', 'porciento'])) return _Action.set;
  if (has(const ['apaga', 'apagar', 'apague', 'apaguen'])) return _Action.off;
  if (has(const ['enciende', 'encender', 'encienda', 'prende', 'prender', 'prenda', 'ilumina'])) return _Action.on;
  if (has(const ['cierra', 'cerrar', 'cierre', 'cierren', 'baja', 'bajar', 'baje'])) return _Action.close;
  if (has(const ['abre', 'abrir', 'abra', 'abran', 'sube', 'subir', 'suba', 'levanta'])) return _Action.open;
  return null;
}

ControlKind? _kindOf(bool Function(Iterable<String>) has, _Action action) {
  if (has(const ['persiana', 'persianas', 'cortina', 'cortinas', 'ventana', 'ventanas'])) return ControlKind.blind;
  if (has(const ['puerta', 'puertas', 'porton', 'portones', 'entrada'])) return ControlKind.door;
  if (has(const ['luz', 'luces', 'lampara', 'foco', 'bombillo', 'bombilla'])) return ControlKind.light;
  // «enciende la cocina» → la luz de la cocina
  if (action == _Action.on || action == _Action.off) return ControlKind.light;
  return null;
}

String? _roomOf(bool Function(Iterable<String>) has) {
  if (has(const ['principal', 'entrada', 'frente', 'calle'])) return 'Entrada';
  if (has(const ['porton', 'garaje', 'garage', 'cochera'])) return 'Garaje';
  if (has(const ['cocina'])) return 'Cocina';
  if (has(const ['bano', 'banos'])) return 'Baño';
  if (has(const ['cuarto', 'habitacion', 'dormitorio', 'recamara', 'pieza'])) return 'Cuarto';
  if (has(const ['sala', 'salon', 'living'])) return 'Sala';
  return null;
}

int? _numberOf(List<String> words) {
  for (final w in words) {
    if (w == '1' || w == 'uno' || w == 'una') return 1;
    if (w == '2' || w == 'dos') return 2;
  }
  return null;
}

/// Valor a enviar. Persianas: 0 cerrada … 180 abierta.
int? _valueFor(ControlKind kind, _Action action, List<String> words) {
  switch (kind) {
    case ControlKind.light:
      return switch (action) { _Action.on => 1, _Action.off => 0, _ => null };
    case ControlKind.door:
      return switch (action) { _Action.open || _Action.on => 1, _Action.close || _Action.off => 0, _ => null };
    case ControlKind.blind:
      return switch (action) {
        _Action.open => CasaPins.blindMax,
        _Action.close => 0,
        _Action.half => CasaPins.blindMax ~/ 2,
        _Action.set => _percent(words),
        _ => null,
      };
  }
}

int? _percent(List<String> words) {
  for (final w in words) {
    final n = int.tryParse(w.replaceAll('%', ''));
    if (n != null && n >= 0 && n <= 100) return (n * CasaPins.blindMax / 100).round();
  }
  return null;
}

String _noun(ControlKind k) => switch (k) {
      ControlKind.light => 'La luz',
      ControlKind.door => 'La puerta',
      ControlKind.blind => 'La persiana',
    };

/// «de la cocina», «del baño»… La entrada no lleva: «Puerta principal».
String _roomPhrase(String room) => switch (room) {
      'Entrada' => '',
      'Baño' => ' del baño',
      'Cuarto' => ' del cuarto',
      'Garaje' => ' del garaje',
      _ => ' de la ${room.toLowerCase()}',
    };

/// «Luz de la cocina», «Puerta principal», «Portón del garaje», «Persiana 1 de la cocina».
String _name(ControlSpec c) => '${c.label}${_roomPhrase(c.room)}';

/// «Puerta principal abierta», «Luces de la sala encendidas», «Persiana del cuarto al 50 %».
String _doneText(List<ControlSpec> targets, ControlKind kind, int value) {
  final first = targets.first;
  final plural = targets.length > 1;
  final who = plural ? '${kind == ControlKind.light ? 'Luces' : 'Persianas'}${_roomPhrase(first.room)}' : _name(first);
  final masculine = !plural && first.label == 'Portón';
  String end(String fem) => plural ? '${fem}s' : (masculine ? '${fem.substring(0, fem.length - 1)}o' : fem);
  return switch (kind) {
    ControlKind.light => '$who ${end(value == 1 ? 'encendida' : 'apagada')}',
    ControlKind.door => '$who ${end(value == 1 ? 'abierta' : 'cerrada')}',
    ControlKind.blind => value == 0 ? '$who ${end('cerrada')}' : '$who al ${(value / CasaPins.blindMax * 100).round()} %',
  };
}

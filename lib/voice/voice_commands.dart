import '../models/controls.dart';

/// Lo que la app debe enviar a la placa por una frase, y lo que la placa debe responder para confirmarlo.
class VoiceCommand {
  /// Mensajes a enviar, en orden: pin virtual → valor.
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

/// Entiende frases en español para la casa del grupo. Una frase puede traer varias órdenes:
/// «enciende la luz y abre la puerta del cuarto», «abre la persiana del cuarto al 30%»,
/// «suena la alarma», «cierra todas las puertas», «buenas noches»...
///
/// Lo que una orden no dice se completa con las otras: en «enciende la luz y abre la puerta del cuarto»
/// la luz es la del cuarto; en «abre la puerta principal y la del baño» las dos se abren.
/// Si alguna parte no se entiende, no se envía nada.
///
/// [isEnabled] dice si un control está conectado en la maqueta; los que no, se avisan o se saltan.
VoiceParse parseCasaCommand(String heard, {bool Function(ControlSpec)? isEnabled}) {
  final enabled = isEnabled ?? (_) => true;
  final text = normalize(heard);
  if (text.isEmpty) return const VoiceParse.fail('No escuché nada.');

  final clauses = splitClauses(text).map(_Clause.read).toList();
  _fillFromNeighbors(clauses);

  final parts = <VoiceCommand>[];
  for (final c in clauses) {
    final r = _build(c, enabled);
    if (r.command == null) return r;
    parts.add(r.command!);
  }
  return VoiceParse.ok(_merge(parts));
}

/// Minúsculas, sin tildes ni signos. «30%» → «30 por ciento»; las comas y puntos separan órdenes.
/// «¡Abre la PUERTA, por favor!» → «abre la puerta y».
String normalize(String s) {
  const from = 'áéíóúüñ', to = 'aeiouun';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b
      .toString()
      .replaceAll('%', ' por ciento ')
      .replaceAll(RegExp(r'[,;.]'), ' y ')
      .replaceAll(RegExp(r'\bpor favor\b|\bporfa\b|\bporfis\b'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// Parte una frase en órdenes: «enciende la luz y abre la puerta» → [«enciende la luz», «abre la puerta»].
List<String> splitClauses(String normalized) => ' $normalized '
    .split(RegExp(r' (?:y luego|y despues|y tambien|y ademas|y|e|luego|despues|tambien|ademas) '))
    .map((p) => p.trim())
    .where((p) => p.isNotEmpty)
    .toList();

// ---------------------------------------------------------------------------

enum _Act { on, off, open, close, half, set }

/// Órdenes completas que no dependen de una pieza.
enum _Special { arm, disarm, sound, alarmUnclear, night, home }

/// Una orden dentro de la frase, con lo que se pudo leer de ella.
class _Clause {
  final String text;
  final List<String> words;
  _Special? special;
  _Act? act;
  ControlKind? kind;
  String? room;
  int? number; // «persiana 1», «luz dos»
  int? percent; // 0 a 100
  bool all = false; // «todas», «todo»
  bool plural = false; // «las luces», «las puertas»

  _Clause(this.text) : words = text.split(' ');

  bool has(Iterable<String> options) =>
      options.any((o) => o.contains(' ') ? ' $text '.contains(' $o ') : words.contains(o));

  static _Clause read(String text) {
    final c = _Clause(text);
    c.special = c._readSpecial();
    if (c.special != null) return c;
    c.percent = c._readPercent();
    c.act = c._readAct();
    c.kind = c._readKind();
    c.room = c._readRoom();
    c.number = c._readNumber();
    c.all = c.has(const ['todo', 'toda', 'todas', 'todos']);
    c.plural = c.has(const ['luces', 'puertas', 'persianas', 'cortinas', 'ventanas', 'portones']);
    return c;
  }

  _Special? _readSpecial() {
    if (has(const ['modo noche', 'buenas noches', 'a dormir', 'me voy', 'nos vamos', 'salgo', 'salimos', 'modo fuera'])) {
      return _Special.night;
    }
    if (has(const ['ya llegue', 'llegue', 'llegamos', 'estoy en casa', 'modo casa', 'ya estoy aqui'])) return _Special.home;
    if (!has(const ['alarma', 'seguridad', 'sirena'])) return null;
    if (has(const ['desarma', 'desarmar', 'desactiva', 'desactivar', 'apaga', 'apagar', 'quita', 'quitar', 'deten', 'detener', 'para', 'parar', 'calla', 'silencia', 'silenciar'])) {
      return _Special.disarm;
    }
    if (has(const ['suena', 'sonar', 'suene', 'dispara', 'disparar', 'pita', 'timbra']) ||
        (has(const ['sirena']) && has(const ['activa', 'activar', 'enciende', 'prende', 'pon', 'toca']))) {
      return _Special.sound;
    }
    if (has(const ['arma', 'armar', 'activa', 'activar', 'pon', 'enciende', 'prende', 'conecta'])) return _Special.arm;
    return _Special.alarmUnclear;
  }

  _Act? _readAct() {
    if (has(const ['mitad', 'medio', 'media'])) return _Act.half;
    if (percent != null) return _Act.set;
    if (has(const ['apaga', 'apagar', 'apague', 'apaguen', 'apago', 'apagas'])) return _Act.off;
    if (has(const ['enciende', 'encender', 'encienda', 'enciendan', 'enciendo', 'enciendes', 'prende', 'prender', 'prenda', 'prendan', 'prendo', 'prendes', 'ilumina'])) return _Act.on;
    if (has(const ['cierra', 'cerrar', 'cierre', 'cierren', 'cierro', 'cierras', 'baja', 'bajar', 'baje', 'bajen', 'bajo'])) return _Act.close;
    if (has(const ['abre', 'abrir', 'abra', 'abran', 'abro', 'abres', 'sube', 'subir', 'suba', 'suban', 'subo', 'levanta'])) return _Act.open;
    return null;
  }

  ControlKind? _readKind() {
    if (has(const ['persiana', 'persianas', 'cortina', 'cortinas', 'ventana', 'ventanas'])) return ControlKind.blind;
    if (has(const ['puerta', 'puertas', 'porton', 'portones', 'entrada'])) return ControlKind.door;
    if (has(const ['luz', 'luces', 'lampara', 'lamparas', 'foco', 'focos', 'bombillo', 'bombilla'])) return ControlKind.light;
    return null;
  }

  String? _readRoom() {
    if (has(const ['principal', 'entrada', 'frente', 'calle'])) return 'Entrada';
    if (has(const ['porton', 'garaje', 'garage', 'cochera'])) return 'Garaje';
    if (has(const ['cocina'])) return 'Cocina';
    if (has(const ['bano', 'banos'])) return 'Baño';
    if (has(const ['cuarto', 'habitacion', 'dormitorio', 'recamara', 'pieza'])) return 'Cuarto';
    if (has(const ['sala', 'salon', 'living'])) return 'Sala';
    return null;
  }

  int? _readNumber() {
    for (final w in words) {
      if (w == '1' || w == 'uno') return 1;
      if (w == '2' || w == 'dos') return 2;
    }
    return null;
  }

  /// «al 30 por ciento», «a 40», «un poco» (30), «todo» en persianas se resuelve después.
  int? _readPercent() {
    const named = {
      'cero': 0, 'diez': 10, 'quince': 15, 'veinte': 20, 'veinticinco': 25, 'treinta': 30, 'cuarenta': 40,
      'cincuenta': 50, 'sesenta': 60, 'setenta': 70, 'ochenta': 80, 'noventa': 90, 'cien': 100, 'ciento': 100,
    };
    int? value(String w) => int.tryParse(w) ?? named[w];
    for (var i = 0; i < words.length; i++) {
      final n = value(words[i]);
      if (n == null || n > 100) continue;
      final porCiento = i + 2 < words.length && words[i + 1] == 'por' && words[i + 2] == 'ciento';
      final afterAl = i > 0 && (words[i - 1] == 'al' || words[i - 1] == 'a') && n > 2;
      if (porCiento || afterAl) return n;
    }
    if (has(const ['un poco', 'poquito', 'un poquito'])) {
      return has(const ['cierra', 'cerrar', 'baja', 'bajar']) ? 70 : 30;
    }
    return null;
  }
}

/// Completa cada orden con lo que dicen las otras.
void _fillFromNeighbors(List<_Clause> clauses) {
  for (var i = 0; i < clauses.length; i++) {
    final c = clauses[i];
    if (c.special != null) continue;
    final prev = i > 0 && clauses[i - 1].special == null ? clauses[i - 1] : null;

    if (c.act == null && prev != null) {
      // «… y la del baño»: misma acción y misma pieza
      c.act = prev.act;
      c.kind ??= prev.kind;
      c.percent ??= prev.percent;
    } else if (c.kind == null && c.act != _Act.on && c.act != _Act.off && prev != null) {
      // «abre la puerta del cuarto y cierra la del baño»
      c.kind = prev.kind;
    }
    // «enciende la cocina» → la luz de la cocina
    if (c.kind == null && (c.act == _Act.on || c.act == _Act.off) && !c.all) c.kind = ControlKind.light;
  }

  // Dónde: «enciende la luz y abre la puerta del cuarto» → la luz del cuarto.
  for (var i = 0; i < clauses.length; i++) {
    final c = clauses[i];
    // «apaga las luces» sin decir dónde son todas; «las persianas 1 y 2 de la cocina» sí toma el lugar.
    if (c.special != null || c.room != null || c.kind == null || c.all || (c.plural && c.number == null)) continue;
    for (final n in [if (i + 1 < clauses.length) clauses[i + 1], if (i > 0) clauses[i - 1]]) {
      final room = n.room;
      if (room != null && casaControls.any((x) => x.kind == c.kind && x.room == room)) {
        c.room = room;
        break;
      }
    }
  }
}

VoiceParse _build(_Clause c, bool Function(ControlSpec) enabled) {
  switch (c.special) {
    case _Special.arm:
      return _ok({CasaPins.armed: 1}, 'Seguridad armada');
    case _Special.disarm:
      return _ok({CasaPins.armed: 0}, 'Seguridad desarmada');
    case _Special.sound:
      return _ok({CasaPins.siren: 1}, 'Alarma sonando');
    case _Special.alarmUnclear:
      return const VoiceParse.fail('¿Armo, desarmo o hago sonar la alarma?');
    case _Special.night:
      return _night(enabled);
    case _Special.home:
      final lights = casaControls.where((x) => x.room == 'Sala' && x.kind == ControlKind.light && enabled(x));
      return _ok({CasaPins.armed: 0, for (final l in lights) l.vpin: 1}, 'Bienvenido: seguridad desarmada y luces de la sala encendidas');
    case null:
      break;
  }

  final act = c.act;
  if (act == null) return VoiceParse.fail('No sé qué hacer con «${c.text}».');
  final kind = c.kind;

  // «cierra todo», «abre todo»: puertas y persianas
  if (kind == null) {
    if (c.all && (act == _Act.open || act == _Act.close)) {
      final targets = casaControls.where((x) => x.kind != ControlKind.light && enabled(x));
      final open = act == _Act.open;
      return _ok({for (final t in targets) t.vpin: open ? _open(t) : 0}, open ? 'Puertas y persianas abiertas' : 'Puertas y persianas cerradas');
    }
    if (c.all && (act == _Act.on || act == _Act.off)) return _allLights(act == _Act.on, enabled);
    return const VoiceParse.fail('¿Qué quieres mover: una luz, una puerta o una persiana?');
  }

  final value = _valueFor(kind, act, c.percent);
  if (value == null) return VoiceParse.fail('Eso no se puede hacer con una ${_bare(kind)}.');

  // Todas las de un tipo: «apaga las luces», «cierra todas las puertas»
  if (c.room == null && (c.all || (c.plural && c.number == null))) {
    if (kind == ControlKind.light) return _allLights(value == 1, enabled);
    final targets = casaControls.where((x) => x.kind == kind && enabled(x)).toList();
    if (targets.isEmpty) return VoiceParse.fail('No hay ${_noun(kind, plural: true)} conectadas.');
    return _ok({for (final t in targets) t.vpin: value}, 'Todas las ${_noun(kind, plural: true)} ${_state(kind, value, plural: true)}');
  }

  var targets = casaControls.where((x) => x.kind == kind).toList();
  final room = c.room;
  if (room != null) {
    targets = targets.where((x) => x.room == room).toList();
  } else if (targets.length > 1) {
    return VoiceParse.fail('¿${_capital(_noun(kind, plural: false))} de qué parte de la casa?');
  }
  final number = c.number;
  if (number != null && targets.length > 1) {
    final pick = targets.where((x) => x.label.endsWith(' $number')).toList();
    if (pick.isNotEmpty) targets = pick;
  }
  if (targets.isEmpty) return VoiceParse.fail('En ${_place(room!)} no hay ${_bare(kind)}.');

  final connected = targets.where(enabled).toList();
  if (connected.isEmpty) return VoiceParse.fail('${_name(targets.first)} está marcada como no conectada.');
  return _ok({for (final t in connected) t.vpin: value}, _doneText(connected, kind, value));
}

/// La placa responde cada pin con el mismo valor que recibió.
VoiceParse _ok(Map<int, int> sends, String done) => VoiceParse.ok(VoiceCommand(sends: sends, expects: Map.of(sends), done: done));

VoiceParse _allLights(bool on, bool Function(ControlSpec) enabled) {
  final v = on ? 1 : 0;
  final lights = casaControls.where((x) => x.kind == ControlKind.light && enabled(x));
  return VoiceParse.ok(VoiceCommand(
    sends: {CasaPins.allLights: v},
    expects: {for (final l in lights) l.vpin: v},
    done: on ? 'Todas las luces encendidas' : 'Todas las luces apagadas',
  ));
}

/// «Buenas noches», «me voy»: cierra puertas y persianas, apaga las luces y arma la seguridad (al final).
VoiceParse _night(bool Function(ControlSpec) enabled) {
  final closable = casaControls.where((x) => x.kind != ControlKind.light && enabled(x));
  final lights = casaControls.where((x) => x.kind == ControlKind.light && enabled(x));
  return VoiceParse.ok(VoiceCommand(
    sends: {for (final x in closable) x.vpin: 0, CasaPins.allLights: 0, CasaPins.armed: 1},
    expects: {for (final x in closable) x.vpin: 0, for (final l in lights) l.vpin: 0, CasaPins.armed: 1},
    done: 'Casa cerrada, luces apagadas y seguridad armada',
  ));
}

/// Junta varias órdenes en una: «Luz del cuarto encendida y puerta del cuarto abierta».
VoiceCommand _merge(List<VoiceCommand> parts) {
  if (parts.length == 1) return parts.single;
  final texts = [parts.first.done, for (final p in parts.skip(1)) _lower(p.done)];
  final done = '${texts.sublist(0, texts.length - 1).join(', ')} y ${texts.last}';
  return VoiceCommand(
    sends: {for (final p in parts) ...p.sends},
    expects: {for (final p in parts) ...p.expects},
    done: done,
  );
}

/// Valor a enviar. Persianas: 0 cerrada … 180 abierta.
int? _valueFor(ControlKind kind, _Act act, int? percent) {
  switch (kind) {
    case ControlKind.light:
      return switch (act) { _Act.on => 1, _Act.off => 0, _ => null };
    case ControlKind.door:
      return switch (act) { _Act.open || _Act.on => 1, _Act.close || _Act.off => 0, _ => null };
    case ControlKind.blind:
      return switch (act) {
        _Act.open => CasaPins.blindMax,
        _Act.close => 0,
        _Act.half => CasaPins.blindMax ~/ 2,
        _Act.set => percent == null ? null : (percent * CasaPins.blindMax / 100).round(),
        _ => null,
      };
  }
}

int _open(ControlSpec c) => c.kind == ControlKind.blind ? CasaPins.blindMax : 1;

String _noun(ControlKind k, {required bool plural}) => switch (k) {
      ControlKind.light => plural ? 'luces' : 'la luz',
      ControlKind.door => plural ? 'puertas' : 'la puerta',
      ControlKind.blind => plural ? 'persianas' : 'la persiana',
    };

String _bare(ControlKind k) => switch (k) { ControlKind.light => 'luz', ControlKind.door => 'puerta', ControlKind.blind => 'persiana' };

/// «el baño», «la cocina»…
String _place(String room) => switch (room) {
      'Baño' || 'Cuarto' || 'Garaje' => 'el ${room.toLowerCase()}',
      _ => 'la ${room.toLowerCase()}',
    };

String _state(ControlKind k, int value, {required bool plural}) {
  final s = switch (k) {
    ControlKind.light => value == 1 ? 'encendida' : 'apagada',
    ControlKind.door => value == 1 ? 'abierta' : 'cerrada',
    ControlKind.blind => value == 0 ? 'cerrada' : 'abierta',
  };
  return plural ? '${s}s' : s;
}

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
  final who = plural ? '${_capital(_noun(kind, plural: true))}${_roomPhrase(first.room)}' : _name(first);
  final masculine = !plural && first.label == 'Portón';
  String end(String fem) => plural ? '${fem}s' : (masculine ? '${fem.substring(0, fem.length - 1)}o' : fem);
  if (kind == ControlKind.blind && value != 0) return '$who al ${(value / CasaPins.blindMax * 100).round()} %';
  return '$who ${end(_state(kind, value, plural: false))}';
}

String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

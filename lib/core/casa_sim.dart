import 'dart:async';

import '../models/pins.dart';
import 'protocol.dart';

/// Simula el programa del ESP32 de la casa (firmware/casa_esp32): mismos mensajes,
/// mismas respuestas y la misma lógica de seguridad. La usan el modo demo y la placa falsa.
class CasaSim {
  final void Function(String line) emit;

  /// Tiempo para desarmar antes de que suene la sirena (en la placa real son 20 s).
  final Duration grace;

  final Map<int, int> values = {for (final p in [...CasaPins.doors, ...CasaPins.blinds, ...CasaPins.lights]) p: 0};
  bool armed = false, sounding = false;
  Timer? _graceTimer;

  /// Pide la clave de la casa como la placa real. Apagado (la demo), responde como una placa sin clave.
  final bool usesClave;
  String clave = '';
  bool _authed = false;
  int _fails = 0;
  DateTime? _lockedUntil;
  static const _maxFails = 3, _lockSeconds = 30;

  CasaSim(this.emit, {this.grace = const Duration(seconds: 20), this.usesClave = false});

  void dispose() => _graceTimer?.cancel();

  void handle(String line) {
    final m = Msg.parse(line);
    if (m.kind == 'PING') return emit('PONG');
    if (usesClave) {
      if (m.kind == 'AUTH') return _auth(m.value);
      if (m.kind == 'CLAVE') return _newClave(m.value);
      if (!_authed) return emit(clave.isEmpty ? 'AUTH:NUEVA' : 'AUTH:PIDE');
    }
    switch (m.kind) {
      case 'SYNC':
        return _sendState();
      case 'TEST':
        return emit('OK:TEST terminado');
      case 'CFG':
        return emit('OK:${m.value}');
    }
    if (!m.isPin) return emit('ERR:no entiendo ${m.raw}');

    final pin = m.pin!;
    final value = int.tryParse(m.value) ?? 0;
    if (pin == CasaPins.armed) return _setArmed(value == 1);
    if (pin == CasaPins.siren) return value == 1 ? _startAlarm('Alarma activada a mano') : _setArmed(false);
    if (pin == CasaPins.allLights) {
      for (final l in CasaPins.lights) {
        _setValue(l, value);
      }
      return;
    }
    if (!values.containsKey(pin)) return emit('ERR:V$pin no existe');
    _setValue(pin, value);
    _checkEntrance();
  }

  /// Nueva conexión: hay que entregar la clave otra vez.
  void reconnect() => _authed = false;

  void _auth(String given) {
    if (clave.isEmpty) return emit('AUTH:NUEVA');
    final left = _lockedUntil?.difference(DateTime.now()).inSeconds ?? 0;
    if (left > 0) return emit('AUTH:ESPERA:$left');
    if (given == clave) {
      _fails = 0;
      _authed = true;
      return emit('AUTH:OK');
    }
    _authed = false;
    if (given.isEmpty) return emit('AUTH:PIDE');
    if (++_fails >= _maxFails) {
      _fails = 0;
      _lockedUntil = DateTime.now().add(const Duration(seconds: _lockSeconds));
      return emit('AUTH:ESPERA:$_lockSeconds');
    }
    emit('AUTH:MAL:${_maxFails - _fails}');
  }

  void _newClave(String c) {
    if (clave.isNotEmpty && !_authed) return emit('AUTH:PIDE');
    if (!validClave(c)) return emit('ERR:la clave debe tener de 4 a 8 numeros');
    clave = c;
    _authed = true;
    emit('AUTH:OK');
    _notice('Clave de la casa guardada');
  }

  void _setValue(int pin, int value) {
    values[pin] = CasaPins.blinds.contains(pin)
        ? value.clamp(0, CasaPins.blindMax)
        : (CasaPins.doors.contains(pin) ? (value > 0 ? 1 : 0) : (value == 1 ? 1 : 0));
    emit('V$pin:${values[pin]}');
  }

  void _sendState() {
    values.forEach((pin, v) => emit('V$pin:$v'));
    emit('V${CasaPins.armed}:${armed ? 1 : 0}');
  }

  void _notice(String text) => emit('V${CasaPins.notice}:$text');

  void _setArmed(bool on) {
    armed = on;
    _cancelGrace();
    if (!on && sounding) {
      sounding = false;
      emit('V${CasaPins.siren}:0');
    }
    emit('V${CasaPins.armed}:${on ? 1 : 0}');
    _notice(on ? 'Seguridad armada' : 'Seguridad desarmada');
    _checkEntrance();
  }

  void _startAlarm(String reason) {
    _cancelGrace();
    sounding = true;
    armed = true;
    emit('V${CasaPins.siren}:1');
    emit('V${CasaPins.armed}:1');
    _notice(reason);
  }

  /// Con la seguridad armada, si el garaje o la puerta principal quedan abiertos, cuenta el tiempo de gracia.
  void _checkEntrance() {
    if (!armed || sounding) return;
    final open = values[CasaPins.garage] == 1 || values[CasaPins.mainDoor] == 1;
    if (open && _graceTimer == null) {
      _notice('Acceso detectado: ${grace.inSeconds} s para desarmar');
      _graceTimer = Timer(grace, () {
        _graceTimer = null;
        _startAlarm('Alarma sonando: entrada abierta');
      });
    } else if (!open && _graceTimer != null) {
      _cancelGrace();
      _notice('Entradas cerradas');
    }
  }

  void _cancelGrace() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }
}

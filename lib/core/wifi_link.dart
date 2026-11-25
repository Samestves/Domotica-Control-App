import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'link.dart';
import 'protocol.dart';
import 'wifi_net.dart';

/// Conexión Wi-Fi por TCP. El ESP32 escucha en un puerto (3333 por defecto), en su propia red o en la de la casa.
class WifiLink extends DeviceLink {
  final String host;
  final int port;
  Socket? _socket;
  StreamSubscription? _sub;
  final _buf = LineBuffer();

  bool _closing = false;
  ConnectionTask<Socket>? _pending;

  /// true mientras esta conexión cuenta como usuaria del Wi-Fi (ver [WifiNet.claim]).
  bool _claimed = false;

  /// Último aviso de error de la placa: si cierra la conexión justo después, ese es el motivo
  /// (por ejemplo, «ya hay otro teléfono conectado por Wi-Fi»).
  String? _lastErr;
  DateTime _lastErrAt = DateTime(0);

  /// El motivo de cierre, si la placa avisó un error justo antes de cerrar.
  String _closedWhy() => DateTime.now().difference(_lastErrAt) < const Duration(seconds: 2) && _lastErr != null
      ? 'La placa cerró la conexión: $_lastErr'
      : 'La placa cerró la conexión.';

  /// Red propia de la placa: si se conoce, la app se une a ella antes de conectar.
  final String? ssid;
  final String? password;

  WifiLink(this.host, this.port, {this.ssid, this.password});

  @override
  Future<void> connect() async {
    if (state == LinkState.connected || state == LinkState.connecting) return;
    _closing = false;
    setState(LinkState.connecting);
    final net = ssid;
    final other = WifiNet.busyWith(net);
    if (other != null) {
      return setState(LinkState.error,
          'El teléfono ya está unido a «$other» por otra placa. Desconecta esa placa primero: Android deja unirse a una sola red de placa a la vez.');
    }
    if (net != null && await WifiNet.joined() != net) {
      try {
        await WifiNet.connect(net, password ?? '');
      } on WifiProblem catch (e) {
        if (_closing) return setState(LinkState.disconnected);
        return setState(LinkState.error, e.message);
      }
    }
    // Después de cada espera: si el usuario canceló mientras tanto, no se sigue.
    if (_closing) return setState(LinkState.disconnected);
    final onWifi = await _useWifi();
    if (_closing) return setState(LinkState.disconnected);
    try {
      final task = await Socket.startConnect(host, port);
      _pending = task;
      final s = await task.socket.timeout(const Duration(seconds: 6), onTimeout: () {
        task.cancel();
        throw TimeoutException('sin respuesta');
      });
      _pending = null;
      if (_closing) {
        s.destroy(); // se abrió justo después de cancelar: se cierra sin usarla
        return setState(LinkState.disconnected);
      }
      s.setOption(SocketOption.tcpNoDelay, true);
      _socket = s;
      _sub = s.listen(
        (bytes) {
          for (final l in _buf.addBytes(bytes)) {
            if (l.startsWith('ERR:')) {
              _lastErr = l.substring(4);
              _lastErrAt = DateTime.now();
            }
            emitLine(l);
          }
        },
        onError: (e) => _drop('Se perdió la conexión: $e'),
        onDone: () => _drop(_closing ? null : _closedWhy()),
        cancelOnError: true,
      );
      // Errores al escribir (por ejemplo, si la placa se apaga a mitad): se tratan como una caída.
      s.done.catchError((Object e) => _drop(_closing ? null : 'Se perdió la conexión.'));
      WifiNet.claim(net);
      _claimed = true;
      setState(LinkState.connected);
      await sendLine('PING');
    } catch (e) {
      _pending = null;
      if (_closing) return setState(LinkState.disconnected); // el usuario canceló
      setState(
        LinkState.error,
        onWifi == false
            ? 'El teléfono no está conectado a ningún Wi-Fi. Conéctate a la red «Casa Domotica» en Ajustes.'
            : 'No se pudo conectar a $host:$port. Revisa que el teléfono esté en la red Wi-Fi de la placa.',
      );
    }
  }

  static const _red = MethodChannel('control_domotica/red');

  /// Pide a Android que la app salga por el Wi-Fi aunque esa red no tenga internet (la red propia del ESP32).
  /// true/false: si hay Wi-Fi. null: no se pudo preguntar (por ejemplo, en las pruebas).
  static Future<bool?> _useWifi() async {
    try {
      return await _red.invokeMethod<bool>('usarWifi');
    } catch (_) {
      return null;
    }
  }

  void _drop([String? error]) {
    _sub?.cancel();
    _sub = null;
    _socket?.destroy();
    _socket = null;
    if (_claimed) {
      _claimed = false;
      WifiNet.unclaim(ssid);
    }
    setState(error == null ? LinkState.disconnected : LinkState.error, error);
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
    _pending?.cancel();
    _pending = null;
    _drop();
  }

  @override
  Future<void> sendLine(String line) async {
    final s = _socket;
    if (s == null) return;
    try {
      s.add(utf8.encode('${clean(line)}\n'));
    } catch (e) {
      _drop('No se pudo enviar: $e');
    }
  }

  /// Envía y espera a que el teléfono lo entregue a la red: quien llama manda de a trozos, y cada trozo sale
  /// recién cuando el anterior salió (así se nota si la placa deja de recibir).
  @override
  Future<void> sendBytes(List<int> data) async {
    final s = _socket;
    if (s == null) throw const SocketException('sin conexión');
    s.add(data);
    await s.flush();
  }
}

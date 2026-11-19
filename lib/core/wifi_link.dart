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
    if (net != null && await WifiNet.joined() != net) {
      try {
        await WifiNet.connect(net, password ?? '');
      } on WifiProblem catch (e) {
        if (_closing) return setState(LinkState.disconnected);
        return setState(LinkState.error, e.message);
      }
    }
    final onWifi = await _useWifi();
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 6));
      s.setOption(SocketOption.tcpNoDelay, true);
      _socket = s;
      _sub = s.cast<List<int>>().transform(utf8.decoder).listen(
        (chunk) {
          for (final l in _buf.add(chunk)) {
            emitLine(l);
          }
        },
        onError: (e) => _drop('Se perdió la conexión: $e'),
        onDone: () => _drop(_closing ? null : 'La placa cerró la conexión.'),
        cancelOnError: true,
      );
      setState(LinkState.connected);
      await sendLine('PING');
    } catch (e) {
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
    setState(error == null ? LinkState.disconnected : LinkState.error, error);
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
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
}

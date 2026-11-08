import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'link.dart';
import 'protocol.dart';

/// Conexión Wi‑Fi por TCP en la red local. El ESP32 escucha en un puerto (3333 por defecto).
class WifiLink extends DeviceLink {
  final String host;
  final int port;
  Socket? _socket;
  StreamSubscription? _sub;
  final _buf = LineBuffer();

  WifiLink(this.host, this.port);

  @override
  Future<void> connect() async {
    if (state == LinkState.connected || state == LinkState.connecting) return;
    setState(LinkState.connecting);
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
        onDone: () => _drop(),
        cancelOnError: true,
      );
      setState(LinkState.connected);
      await sendLine('PING');
    } catch (e) {
      setState(LinkState.error, 'No se pudo conectar a $host:$port. Revisa que el teléfono y la placa estén en la misma red Wi‑Fi.');
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
  Future<void> disconnect() async => _drop();

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

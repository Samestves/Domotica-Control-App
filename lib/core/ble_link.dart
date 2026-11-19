import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'link.dart';
import 'protocol.dart';

/// Servicios BLE tipo «puerto serie» que entendemos.
class BleUuids {
  // Nordic UART Service: el que usa nuestro programa del ESP32.
  static const nus = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const nusRx = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // la app escribe aquí
  static const nusTx = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // la placa notifica aquí
  // Módulos HM-10 (para Arduino Uno): un solo canal para leer y escribir.
  static const hm10 = '0000ffe0-0000-1000-8000-00805f9b34fb';
  static const hm10Char = '0000ffe1-0000-1000-8000-00805f9b34fb';
}

class BleLink extends DeviceLink {
  final String remoteId;
  BluetoothDevice? _dev;
  BluetoothCharacteristic? _rx;
  StreamSubscription? _notifySub;
  StreamSubscription? _connSub;
  final _buf = LineBuffer();
  bool _closing = false;

  BleLink(this.remoteId);

  @override
  Future<void> connect() async {
    if (state == LinkState.connected || state == LinkState.connecting) return;
    _closing = false;
    setState(LinkState.connecting);
    try {
      if (await FlutterBluePlus.isSupported == false) {
        throw 'Este teléfono no tiene Bluetooth LE.';
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {
          throw 'Activa el Bluetooth del teléfono.';
        }
      }
      final dev = BluetoothDevice.fromId(remoteId);
      _dev = dev;
      // Proyecto educativo: licencia sin fines de lucro. Para venderla haría falta la licencia comercial.
      await dev.connect(license: License.nonprofit, timeout: const Duration(seconds: 10));

      final services = await dev.discoverServices();
      BluetoothCharacteristic? rx;
      BluetoothCharacteristic? tx;
      for (final s in services) {
        final su = s.serviceUuid.str128.toLowerCase();
        for (final c in s.characteristics) {
          final cu = c.characteristicUuid.str128.toLowerCase();
          if (su == BleUuids.nus && cu == BleUuids.nusRx) rx = c;
          if (su == BleUuids.nus && cu == BleUuids.nusTx) tx = c;
          if (su == BleUuids.hm10 && cu == BleUuids.hm10Char) {
            rx ??= c;
            tx ??= c;
          }
        }
      }
      if (rx == null || tx == null) {
        throw 'La placa no tiene el servicio de mensajes. ¿Tiene cargado nuestro programa?';
      }
      _rx = rx;
      await tx.setNotifyValue(true);
      _notifySub = tx.onValueReceived.listen((bytes) {
        for (final l in _buf.add(utf8.decode(bytes, allowMalformed: true))) {
          emitLine(l);
        }
      });
      dev.cancelWhenDisconnected(_notifySub!);

      _connSub = dev.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected && !_closing && state == LinkState.connected) {
          setState(LinkState.error, 'La placa se desconectó. ¿Está encendida y cerca?');
        }
      });
      setState(LinkState.connected);
      await sendLine('PING');
    } catch (e) {
      await _cleanup();
      if (_closing) return setState(LinkState.disconnected); // el usuario canceló
      setState(LinkState.error, e is String ? e : 'No se pudo conectar por Bluetooth: $e');
    }
  }

  Future<void> _cleanup() async {
    await _notifySub?.cancel();
    await _connSub?.cancel();
    _notifySub = null;
    _connSub = null;
    _rx = null;
    try {
      await _dev?.disconnect();
    } catch (_) {}
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
    await _cleanup();
    setState(LinkState.disconnected);
  }

  @override
  Future<void> sendLine(String line) async {
    final rx = _rx;
    final dev = _dev;
    if (rx == null || dev == null) return;
    final data = utf8.encode('${clean(line)}\n');
    final noResp = rx.properties.writeWithoutResponse;
    final chunk = (dev.mtuNow - 3).clamp(20, 500);
    try {
      for (var i = 0; i < data.length; i += chunk) {
        final end = (i + chunk < data.length) ? i + chunk : data.length;
        await rx.write(data.sublist(i, end), withoutResponse: noResp);
      }
    } catch (e) {
      setState(LinkState.error, 'No se pudo enviar por Bluetooth.');
    }
  }
}

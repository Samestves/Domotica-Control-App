import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../main.dart';
import '../models/device.dart';
import 'theme.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _name = TextEditingController();
  final _ip = TextEditingController(text: '192.168.1.');
  final _port = TextEditingController(text: '3333');
  Profile _profile = Profile.casa;
  Transport _transport = Transport.ble;
  String _board = 'ESP32';

  // Bluetooth
  List<ScanResult> _results = [];
  ScanResult? _picked;
  bool _scanning = false;
  String? _scanError;
  StreamSubscription? _resSub, _scanSub;

  @override
  void dispose() {
    _resSub?.cancel();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    _name.dispose();
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanError = null;
      _results = [];
      _picked = null;
    });
    try {
      if (await FlutterBluePlus.isSupported == false) {
        setState(() => _scanError = 'Este teléfono no tiene Bluetooth LE.');
        return;
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
      _resSub ??= FlutterBluePlus.scanResults.listen((r) {
        if (!mounted) return;
        final named = r.where((x) => _nameOf(x).isNotEmpty).toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
        setState(() => _results = named);
      });
      _scanSub ??= FlutterBluePlus.isScanning.listen((v) {
        if (mounted) setState(() => _scanning = v);
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
    } catch (e) {
      setState(() => _scanError = 'No se pudo buscar. Activa el Bluetooth y acepta los permisos.');
    }
  }

  String _nameOf(ScanResult r) =>
      r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;

  bool get _valid {
    if (_name.text.trim().isEmpty) return false;
    return switch (_transport) {
      Transport.ble => _picked != null,
      Transport.wifi => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(_ip.text.trim()) && int.tryParse(_port.text) != null,
      Transport.demo => true,
    };
  }

  Future<void> _save() async {
    final d = SavedDevice(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      profile: _profile,
      transport: _transport,
      board: _transport == Transport.demo ? 'Demo' : _board,
      address: switch (_transport) {
        Transport.ble => _picked!.device.remoteId.str,
        Transport.wifi => _ip.text.trim(),
        Transport.demo => '',
      },
      port: int.tryParse(_port.text) ?? 3333,
    );
    await AppScope.read(context).add(d);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agregar dispositivo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _label('Nombre'),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'Ej.: Casa de la feria'),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
          ),
          _label('Perfil del panel'),
          _segmented<Profile>(
            value: _profile,
            items: const {Profile.casa: 'Casa Domótica', Profile.carro: 'Auto Robot'},
            onChanged: (v) => setState(() => _profile = v),
          ),
          _label('Placa'),
          _segmented<String>(
            value: _board,
            items: const {'ESP32': 'ESP32', 'Arduino + HM‑10': 'Arduino + HM‑10'},
            onChanged: (v) => setState(() {
              _board = v;
              if (v != 'ESP32' && _transport == Transport.wifi) _transport = Transport.ble;
            }),
          ),
          _label('Conexión'),
          _segmented<Transport>(
            value: _transport,
            items: {
              Transport.ble: 'Bluetooth',
              if (_board == 'ESP32') Transport.wifi: 'Wi‑Fi',
              Transport.demo: 'Demo',
            },
            onChanged: (v) => setState(() => _transport = v),
          ),
          const SizedBox(height: 16),
          ...switch (_transport) {
            Transport.ble => _bleSection(),
            Transport.wifi => _wifiSection(),
            Transport.demo => [
                const Panel(child: Text('Una placa simulada dentro del teléfono. Sirve para probar los paneles sin hardware.', style: TextStyle(color: C.ink2))),
              ],
          },
          const SizedBox(height: 24),
          FilledButton(onPressed: _valid ? _save : null, child: const Text('Guardar dispositivo')),
        ],
      ),
    );
  }

  List<Widget> _bleSection() => [
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Column(children: [
            Row(children: [
              const Expanded(child: Text('Placas cercanas', style: TextStyle(fontWeight: FontWeight.w600))),
              if (_scanning) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              TextButton(onPressed: _scanning ? FlutterBluePlus.stopScan : _scan, child: Text(_scanning ? 'Detener' : 'Buscar')),
            ]),
            if (_scanError != null) Padding(padding: const EdgeInsets.all(8), child: Text(_scanError!, style: const TextStyle(color: C.danger))),
            if (_results.isEmpty && !_scanning && _scanError == null)
              const Padding(
                padding: EdgeInsets.fromLTRB(0, 4, 8, 10),
                child: Text('Toca «Buscar» con la placa encendida y cerca del teléfono.', style: TextStyle(color: C.ink2)),
              ),
            for (final r in _results)
              ListTile(
                contentPadding: const EdgeInsets.only(left: 0, right: 8),
                leading: Icon(Icons.bluetooth, color: _picked == r ? C.accent : C.ink2),
                title: Text(_nameOf(r)),
                subtitle: Text('${r.device.remoteId.str} · ${r.rssi} dBm', style: const TextStyle(fontSize: 12)),
                trailing: _picked == r ? const Icon(Icons.check_circle, color: C.accent) : null,
                onTap: () => setState(() {
                  _picked = r;
                  if (_name.text.trim().isEmpty) _name.text = _nameOf(r);
                }),
              ),
          ]),
        ),
      ];

  List<Widget> _wifiSection() => [
        Row(children: [
          Expanded(
            flex: 3,
            child: TextField(
              controller: _ip,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'IP de la placa'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Puerto'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text('El ESP32 muestra su IP en el monitor serie al conectarse al Wi‑Fi. El teléfono debe estar en la misma red.',
              style: TextStyle(color: C.ink2, fontSize: 13)),
        ),
      ];

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: .6, color: C.ink2, fontWeight: FontWeight.w600)),
      );

  Widget _segmented<T>({required T value, required Map<T, String> items, required ValueChanged<T> onChanged}) {
    return SegmentedButton<T>(
      segments: [for (final e in items.entries) ButtonSegment(value: e.key, label: Text(e.value))],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
      style: SegmentedButton.styleFrom(
        backgroundColor: C.card,
        selectedBackgroundColor: C.accent,
        selectedForegroundColor: Colors.white,
        side: const BorderSide(color: C.line),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../main.dart';
import '../models/device.dart';
import 'theme.dart';
import 'widgets/glass.dart';
import 'widgets/large_title_scaffold.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  static const _esp32 = 'ESP32', _hm10 = 'Arduino + HM‑10';

  final _name = TextEditingController();
  final _ip = TextEditingController(text: '192.168.1.');
  final _port = TextEditingController(text: '3333');
  Profile _profile = Profile.casa;
  Transport _transport = Transport.ble;
  String _board = _esp32;

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
    return LargeTitleScaffold(
      title: 'Nuevo dispositivo',
      bottomBar: FilledButton(onPressed: _valid ? _save : null, child: const Text('Guardar dispositivo')),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(children: [
            const SectionTitle('Nombre', small: true),
            GlassGroup(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _name,
                  style: T.body,
                  decoration: const InputDecoration(hintText: 'Ej.: Casa de la feria'),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            const SectionTitle('Panel', small: true),
            _segmented<Profile>(
              value: _profile,
              items: const {Profile.casa: 'Casa domótica', Profile.carro: 'Auto Robot'},
              onChanged: (v) => _profile = v,
            ),
            const SectionTitle('Placa', small: true),
            _segmented<String>(
              value: _board,
              items: const {_esp32: _esp32, _hm10: _hm10},
              onChanged: (v) {
                _board = v;
                if (v != _esp32 && _transport == Transport.wifi) _transport = Transport.ble;
              },
            ),
            const SectionTitle('Conexión', small: true),
            _segmented<Transport>(
              value: _transport,
              items: {
                Transport.ble: 'Bluetooth',
                if (_board == _esp32) Transport.wifi: 'Wi‑Fi',
                Transport.demo: 'Demo',
              },
              onChanged: (v) => _transport = v,
            ),
            ...switch (_transport) {
              Transport.ble => _bleSection(),
              Transport.wifi => _wifiSection(),
              Transport.demo => const [
                  SizedBox(height: 10),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Una placa simulada dentro del teléfono. Sirve para probar y mostrar los paneles sin hardware.', style: T.footnote),
                  ),
                ],
            },
          ]),
        ),
      ],
    );
  }

  /// Selector segmentado de iOS sobre vidrio.
  Widget _segmented<V extends Object>({required V value, required Map<V, String> items, required ValueChanged<V> onChanged}) {
    return CupertinoSlidingSegmentedControl<V>(
      groupValue: value,
      backgroundColor: const Color(0x24787880),
      thumbColor: Colors.white,
      padding: const EdgeInsets.all(3),
      children: {
        for (final e in items.entries)
          e.key: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text(e.value, style: T.subhead.copyWith(fontWeight: FontWeight.w600)),
          ),
      },
      onValueChanged: (v) {
        if (v != null) setState(() => onChanged(v));
      },
    );
  }

  List<Widget> _bleSection() => [
        SectionTitle(
          'Placas cercanas',
          small: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_scanning) const Padding(padding: EdgeInsets.only(right: 8), child: CupertinoActivityIndicator(radius: 8)),
            GestureDetector(
              onTap: _scanning ? FlutterBluePlus.stopScan : _scan,
              child: Text(_scanning ? 'Detener' : 'Buscar', style: T.subhead.copyWith(color: C.blue, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        GlassGroup(
          footer: _scanError ?? (_results.isEmpty ? 'Toca «Buscar» con la placa encendida y cerca del teléfono.' : null),
          children: [
            if (_results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(children: [
                  Icon(_scanning ? Icons.bluetooth_searching_rounded : Icons.bluetooth_rounded, color: C.label3, size: 30),
                  const SizedBox(height: 6),
                  Text(_scanning ? 'Buscando…' : 'Sin resultados todavía', style: T.subhead.copyWith(color: C.label2)),
                ]),
              ),
            for (final r in _results) _BoardRow(
              name: _nameOf(r),
              id: r.device.remoteId.str,
              rssi: r.rssi,
              selected: _picked == r,
              onTap: () => setState(() {
                _picked = r;
                if (_name.text.trim().isEmpty) _name.text = _nameOf(r);
              }),
            ),
          ],
        ),
      ];

  List<Widget> _wifiSection() => [
        const SectionTitle('Dirección en la red', small: true),
        GlassGroup(
          footer: 'El ESP32 muestra su IP en el monitor serie al conectarse al Wi‑Fi. El teléfono debe estar en la misma red.',
          children: [
            _FieldRow(label: 'IP', controller: _ip, onChanged: () => setState(() {})),
            _FieldRow(label: 'Puerto', controller: _port, onChanged: () => setState(() {})),
          ],
        ),
      ];
}

/// Una placa encontrada por Bluetooth, con su señal.
class _BoardRow extends StatelessWidget {
  final String name, id;
  final int rssi;
  final bool selected;
  final VoidCallback onTap;
  const _BoardRow({required this.name, required this.id, required this.rssi, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bars = rssi > -60 ? 3 : (rssi > -75 ? 2 : 1);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: ShapeDecoration(shape: squircle(10), color: selected ? C.blue : const Color(0x1A007AFF)),
            child: Icon(Icons.bluetooth_rounded, size: 19, color: selected ? Colors.white : C.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: T.body.copyWith(fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(id, style: T.caption),
            ]),
          ),
          _SignalBars(bars),
          const SizedBox(width: 12),
          SizedBox(width: 22, child: selected ? const Icon(Icons.check_rounded, color: C.blue) : null),
        ]),
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int level; // 1 a 3
  const _SignalBars(this.level);

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 1; i <= 3; i++)
        Container(
          margin: const EdgeInsets.only(left: 2),
          width: 4,
          height: 5.0 + i * 4,
          decoration: ShapeDecoration(shape: const StadiumBorder(), color: i <= level ? C.label : C.label3),
        ),
    ]);
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _FieldRow({required this.label, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        SizedBox(width: 80, child: Text(label, style: T.body)),
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.right,
            style: T.body.copyWith(color: C.label2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged(),
          ),
        ),
      ]),
    );
  }
}

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/ble_link.dart';
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

  /// IP del ESP32 cuando crea su propia red Wi‑Fi.
  static const _ownIp = '192.168.4.1';

  final _name = TextEditingController();
  final _ip = TextEditingController(text: _ownIp);
  final _port = TextEditingController(text: '3333');
  Profile _profile = Profile.casa;
  Transport _transport = Transport.ble;
  String _board = _esp32;

  // Bluetooth: arriba las placas que hablan nuestro idioma; el resto (teléfonos, relojes...) queda escondido.
  List<ScanResult> _boards = [], _others = [];
  bool _showOthers = false;
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
      _boards = [];
      _others = [];
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
        setState(() {
          _boards = named.where(_isBoard).toList();
          _others = named.where((x) => !_isBoard(x)).toList();
        });
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

  /// Anuncia el servicio de mensajes de nuestro programa (ESP32) o el de un módulo HM‑10.
  static bool _isBoard(ScanResult r) => r.advertisementData.serviceUuids
      .map((u) => u.str128.toLowerCase())
      .any((u) => u == BleUuids.nus || u == BleUuids.hm10);

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
          footer: _scanError ?? _bleHint,
          children: [
            if (_boards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Column(children: [
                  Icon(_scanning ? Icons.bluetooth_searching_rounded : Icons.bluetooth_rounded, color: C.label3, size: 30),
                  const SizedBox(height: 6),
                  Text(_scanning ? 'Buscando…' : 'Ninguna placa todavía', style: T.subhead.copyWith(color: C.label2)),
                ]),
              ),
            for (final r in _boards) _row(r, board: true),
          ],
        ),
        if (_others.isNotEmpty) ...[
          const SizedBox(height: 14),
          GlassGroup(children: [
            InkWell(
              onTap: () => setState(() => _showOthers = !_showOthers),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
                child: Row(children: [
                  Expanded(child: Text('Otros dispositivos (${_others.length})', style: T.body)),
                  AnimatedRotation(
                    turns: _showOthers ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.chevron_right_rounded, color: C.label3),
                  ),
                ]),
              ),
            ),
            if (_showOthers) for (final r in _others) _row(r, board: false),
          ]),
        ],
      ];

  String? get _bleHint {
    if (_boards.isNotEmpty) return null;
    if (_scanning) return 'Buscando placas con nuestro programa…';
    if (_others.isNotEmpty) return 'No apareció ninguna placa. ¿Está encendida, cerca y con nuestro programa cargado?';
    return 'Toca «Buscar» con la placa encendida y cerca del teléfono.';
  }

  Widget _row(ScanResult r, {required bool board}) => _BoardRow(
        name: _nameOf(r),
        id: r.device.remoteId.str,
        rssi: r.rssi,
        board: board,
        selected: _picked?.device.remoteId == r.device.remoteId,
        onTap: () => setState(() {
          _picked = r;
          if (_name.text.trim().isEmpty) _name.text = _niceName(_nameOf(r));
        }),
      );

  /// «Casa Domotica» → «Casa Domótica»: la placa no lleva tildes en su nombre Bluetooth.
  static String _niceName(String n) => n == 'Casa Domotica' ? 'Casa Domótica' : n;

  List<Widget> _wifiSection() => [
        const SectionTitle('Red propia de la casa', small: true),
        GlassGroup(
          footer: 'Antes, en Ajustes → Wi‑Fi del teléfono, conéctate a la red «Casa Domotica» (contraseña: casadomotica). '
              'No necesita internet ni datos móviles.',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: ShapeDecoration(shape: squircle(10), color: const Color(0x1A007AFF)),
                  child: const Icon(Icons.wifi_rounded, size: 19, color: C.blue),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Casa Domotica', style: T.body),
                    Text('IP 192.168.4.1 · puerto 3333', style: T.caption),
                  ]),
                ),
                if (_ip.text.trim() == _ownIp && _port.text.trim() == '3333')
                  const Icon(Icons.check_rounded, color: C.blue)
                else
                  GestureDetector(
                    onTap: () => setState(() {
                      _ip.text = _ownIp;
                      _port.text = '3333';
                    }),
                    child: Text('Usar', style: T.subhead.copyWith(color: C.blue, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ],
        ),
        const SectionTitle('Dirección', small: true),
        GlassGroup(
          footer: 'Si el ESP32 se une a otra red (la de la casa o del colegio), escribe la IP que muestra en el Monitor Serie. '
              'El teléfono debe estar en esa misma red.',
          children: [
            _FieldRow(label: 'IP', controller: _ip, onChanged: () => setState(() {})),
            _FieldRow(label: 'Puerto', controller: _port, onChanged: () => setState(() {})),
          ],
        ),
      ];
}

/// Un dispositivo encontrado por Bluetooth, con su señal. [board]: tiene nuestro programa.
class _BoardRow extends StatelessWidget {
  final String name, id;
  final int rssi;
  final bool board;
  final bool selected;
  final VoidCallback onTap;
  const _BoardRow({required this.name, required this.id, required this.rssi, required this.board, required this.selected, required this.onTap});

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
            decoration: ShapeDecoration(
              shape: squircle(10),
              color: selected ? C.blue : (board ? const Color(0x1A007AFF) : const Color(0x14787880)),
            ),
            child: Icon(
              board ? Icons.developer_board_rounded : Icons.bluetooth_rounded,
              size: 19,
              color: selected ? Colors.white : (board ? C.blue : C.label2),
            ),
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

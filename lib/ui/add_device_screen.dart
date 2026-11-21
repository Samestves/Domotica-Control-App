import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/ble_link.dart';
import '../core/link.dart';
import '../core/wifi_link.dart';
import '../core/wifi_net.dart';
import '../main.dart';
import '../models/device.dart';
import 'theme.dart';
import 'widgets/app_scaffold.dart';
import 'widgets/kit.dart';

class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  static const _esp32 = 'ESP32', _hm10 = 'Arduino + HM-10';

  /// IP del ESP32 cuando crea su propia red Wi-Fi.
  static const _ownIp = WifiNet.boardIp;

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

  /// Qué botón ofrecer cuando la búsqueda por Bluetooth falla (activar ubicación, ir a permisos).
  _BleFix? _bleFix;

  /// Ya se guardó (evita guardar dos veces con un doble toque).
  bool _saving = false, _saved = false;
  StreamSubscription? _resSub, _scanSub;

  // Wi-Fi: redes cercanas de verdad y la red de la placa a la que se unió la app.
  List<WifiNetwork> _nets = [];
  bool _netScanning = false, _showOtherNets = false, _showManual = false;
  WifiProblem? _netProblem;
  String? _joined, _joinedPass, _joining;
  PillState _test = PillState.idle;
  String? _testMsg;

  @override
  void dispose() {
    _resSub?.cancel();
    _scanSub?.cancel();
    FlutterBluePlus.stopScan();
    _name.dispose();
    _ip.dispose();
    _port.dispose();
    // Se unió a la red de una placa y salió sin guardar: el teléfono vuelve a su Wi-Fi de siempre.
    if (_joined != null && !_saved) WifiNet.releaseIfUnused();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanError = null;
      _bleFix = null;
      _boards = [];
      _others = [];
      _picked = null;
    });
    try {
      if (await FlutterBluePlus.isSupported == false) {
        if (mounted) setState(() => _scanError = 'Este teléfono no tiene Bluetooth LE.');
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
      if (!mounted) return;
      final why = e.toString().toLowerCase();
      setState(() {
        if (why.contains('location')) {
          // Android 11 o más viejo: sin la ubicación encendida no deja buscar por Bluetooth.
          _scanError = 'Activa la ubicación del teléfono: Android la pide para buscar por Bluetooth.';
          _bleFix = _BleFix.location;
        } else if (why.contains('permission')) {
          _scanError = 'Falta el permiso de Bluetooth (dispositivos cercanos). Dalo en los ajustes de la app.';
          _bleFix = _BleFix.permission;
        } else {
          _scanError = 'No se pudo buscar. Activa el Bluetooth y acepta los permisos.';
        }
      });
    }
  }

  String _nameOf(ScanResult r) => r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;

  /// Anuncia el servicio de mensajes de nuestro programa (ESP32) o el de un módulo HM-10.
  static bool _isBoard(ScanResult r) =>
      r.advertisementData.serviceUuids.map((u) => u.str128.toLowerCase()).any((u) => u == BleUuids.nus || u == BleUuids.hm10);

  /// Nombre si lo dejan vacío: el del tipo de panel.
  String get _defaultName => _profile == Profile.casa ? 'Casa domótica' : 'Auto Robot';

  /// El nombre es opcional: lo único que hace falta es saber cómo llegar a la placa.
  bool get _valid {
    return switch (_transport) {
      Transport.ble => _picked != null,
      Transport.wifi => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(_ip.text.trim()) && int.tryParse(_port.text) != null,
      Transport.demo => true,
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final d = SavedDevice(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim().isEmpty ? _defaultName : _name.text.trim(),
      profile: _profile,
      transport: _transport,
      board: _transport == Transport.demo ? 'Demo' : _board,
      address: switch (_transport) {
        Transport.ble => _picked!.device.remoteId.str,
        Transport.wifi => _ip.text.trim(),
        Transport.demo => '',
      },
      port: int.tryParse(_port.text) ?? 3333,
      ssid: _transport == Transport.wifi && _ip.text.trim() == _ownIp ? _joined : null,
      wifiPass: _transport == Transport.wifi && _ip.text.trim() == _ownIp ? _joinedPass : null,
    );
    await AppScope.read(context).add(d);
    _saved = true;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppScaffold(
      title: 'Nuevo dispositivo',
      bottomBar: PillButton('Guardar dispositivo', expand: true, onTap: _valid ? _save : null),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.list(children: [
            const SectionHeader('Panel'),
            Segmented<Profile>(
              value: _profile,
              items: const {Profile.casa: 'Casa', Profile.carro: 'Auto Robot'},
              icons: const {Profile.casa: Ic.house, Profile.carro: Ic.car},
              onChanged: (v) => setState(() => _profile = v),
            ),
            const SectionHeader('Placa'),
            Segmented<String>(
              value: _board,
              items: const {_esp32: _esp32, _hm10: _hm10},
              onChanged: (v) => setState(() {
                _board = v;
                if (v != _esp32 && _transport == Transport.wifi) _transport = Transport.ble;
              }),
            ),
            const SectionHeader('Conexión'),
            Segmented<Transport>(
              value: _transport,
              items: {
                Transport.ble: 'Bluetooth',
                if (_board == _esp32) Transport.wifi: 'Wi-Fi',
                Transport.demo: 'Demo',
              },
              icons: const {Transport.ble: Ic.bluetooth, Transport.wifi: Ic.wifi, Transport.demo: Ic.demo},
              onChanged: (v) {
                setState(() => _transport = v);
                if (v == Transport.wifi && _nets.isEmpty && !_netScanning) _scanWifi();
              },
            ),
            ...switch (_transport) {
              Transport.ble => _bleSection(c),
              Transport.wifi => _wifiSection(c),
              Transport.demo => [
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('Una placa simulada dentro del teléfono. Sirve para probar y mostrar los paneles sin hardware.',
                        style: T.small.copyWith(color: c.text2)),
                  ),
                ],
            },
            // Al final: casi siempre ya viene escrito con el nombre de la placa elegida.
            const SectionHeader('Nombre'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _name,
                style: T.body,
                decoration: InputDecoration(hintText: _defaultName),
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text('Opcional. Si lo dejas vacío, se llama «$_defaultName».', style: T.small.copyWith(color: c.text2)),
            ),
          ]),
        ),
      ],
    );
  }

  List<Widget> _bleSection(Palette c) => [
        SectionHeader(
          'Placas cercanas',
          trailing: Tap(
            onTap: _scanning ? FlutterBluePlus.stopScan : _scan,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_scanning)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.4, color: c.text)),
                ),
              Eyebrow(_scanning ? 'Detener' : 'Buscar', color: c.text),
            ]),
          ),
        ),
        if (_bleFix != null) ...[
          PillButton(
            _bleFix == _BleFix.location ? 'Activar ubicación' : 'Abrir ajustes de la app',
            small: true,
            kind: PillKind.secondary,
            onTap: _bleFix == _BleFix.location ? WifiNet.openLocationSettings : WifiNet.openAppSettings,
          ),
          const SizedBox(height: 12),
        ],
        RowGroup(
          footer: _scanError ?? _bleHint,
          children: [
            if (_boards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Column(children: [
                  Icon(Ic.bluetooth, color: c.text3, size: 30),
                  const SizedBox(height: 8),
                  Eyebrow(_scanning ? 'Buscando…' : 'Ninguna placa todavía', color: c.text3),
                ]),
              ),
            for (final r in _boards) _row(r, board: true),
          ],
        ),
        if (_others.isNotEmpty) ...[
          const SizedBox(height: 14),
          RowGroup(children: [
            ListRow(
              title: 'Otros dispositivos (${_others.length})',
              onTap: () => setState(() => _showOthers = !_showOthers),
              trailing: AnimatedRotation(
                turns: _showOthers ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Ic.chevronDown, size: 18, color: c.text3),
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
          // El programa del carrito se anuncia como «Carrito 4x4»: se abre con el panel de manejo.
          if (_nameOf(r).toLowerCase().contains('carrito')) _profile = Profile.carro;
        }),
      );

  /// «Casa Domotica» → «Casa Domótica»: la placa no lleva tildes en su nombre Bluetooth.
  static String _niceName(String n) => n == 'Casa Domotica' ? 'Casa Domótica' : n;

  // ---------- Wi-Fi ----------

  Future<void> _scanWifi() async {
    setState(() {
      _netScanning = true;
      _netProblem = null;
    });
    try {
      final nets = await WifiNet.scan();
      final joined = await WifiNet.joined();
      if (!mounted) return;
      setState(() {
        _nets = nets;
        _joined = joined ?? _joined;
      });
    } on WifiProblem catch (e) {
      if (mounted) setState(() => _netProblem = e);
    } finally {
      if (mounted) setState(() => _netScanning = false);
    }
  }

  /// Une el teléfono a la red de la placa, con su contraseña.
  Future<void> _join(WifiNetwork n) async {
    final pass = n.secure ? await _askPassword(n.ssid) : '';
    if (pass == null || !mounted) return;
    setState(() {
      _joining = n.ssid;
      _netProblem = null;
      _test = PillState.idle;
      _testMsg = null;
    });
    try {
      await WifiNet.connect(n.ssid, pass);
      if (!mounted) return;
      setState(() {
        _joined = n.ssid;
        _joinedPass = pass;
        _ip.text = _ownIp;
        _port.text = '${WifiNet.boardPort}';
        if (_name.text.trim().isEmpty) _name.text = _niceName(n.ssid);
        if (n.ssid.toLowerCase().contains('carrito')) _profile = Profile.carro;
      });
      _testBoard();
    } on WifiProblem catch (e) {
      if (mounted) setState(() => _netProblem = e);
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  Future<void> _leave() async {
    await WifiNet.release();
    if (!mounted) return;
    setState(() {
      _joined = null;
      _test = PillState.idle;
      _testMsg = null;
    });
  }

  Future<String?> _askPassword(String ssid) => showAppSheet<String>(context, (_) => _PasswordSheet(ssid: ssid));

  /// Prueba que la placa conteste en la IP y el puerto escritos.
  Future<void> _testBoard() async {
    setState(() {
      _test = PillState.busy;
      _testMsg = null;
    });
    final link = WifiLink(_ip.text.trim(), int.tryParse(_port.text) ?? WifiNet.boardPort, ssid: _joined, password: _joinedPass);
    final heard = Completer<bool>();
    final sub = link.lines.listen((_) {
      if (!heard.isCompleted) heard.complete(true);
    });
    await link.connect();
    var ok = false;
    String? why = link.lastError;
    if (link.state == LinkState.connected) {
      ok = await heard.future.timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!ok) why = 'Se abrió la conexión, pero la placa no contestó. ¿Tiene cargado nuestro programa?';
    }
    await sub.cancel();
    await link.dispose();
    if (!mounted) return;
    setState(() {
      _test = ok ? PillState.done : PillState.failed;
      _testMsg = ok ? 'La placa respondió. Ya puedes guardarla.' : (why ?? 'La placa no respondió.');
    });
  }

  List<Widget> _wifiSection(Palette c) {
    final boards = _nets.where((n) => n.isBoard).toList();
    final others = _nets.where((n) => !n.isBoard).toList();
    final p = _netProblem;
    return [
      SectionHeader(
        'Redes cercanas',
        trailing: Tap(
          onTap: _netScanning ? null : _scanWifi,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (_netScanning)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.4, color: c.text)),
              ),
            Eyebrow(_netScanning ? 'Buscando' : 'Buscar', color: c.text),
          ]),
        ),
      ),
      if (p != null) ...[
        Panel(
          border: c.amber.withValues(alpha: 0.6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Ic.warning, color: c.amber, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(p.message, style: T.small)),
            ]),
            if (p.wifiOff || p.noPermission || p.locationOff || p.blocked) ...[
              const SizedBox(height: 12),
              PillButton(
                p.wifiOff
                    ? 'Activar el Wi-Fi'
                    : p.locationOff
                        ? 'Activar ubicación'
                        : p.blocked
                            ? 'Abrir ajustes de la app'
                            : 'Dar permiso',
                small: true,
                kind: PillKind.secondary,
                onTap: p.wifiOff
                    ? WifiNet.openSettings
                    : p.locationOff
                        ? WifiNet.openLocationSettings
                        : p.blocked
                            ? WifiNet.openAppSettings
                            : _scanWifi,
              ),
            ],
          ]),
        ),
        const SizedBox(height: 12),
      ],
      RowGroup(
        footer: boards.isEmpty && !_netScanning && p == null
            ? 'No aparece la red de la placa. Enciende el ESP32: su red se llama «${WifiNet.boardSsid}».'
            : null,
        children: [
          if (boards.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(children: [
                Icon(Ic.wifi, color: c.text3, size: 30),
                const SizedBox(height: 8),
                Eyebrow(_netScanning ? 'Buscando redes…' : 'Ninguna placa a la vista', color: c.text3),
              ]),
            ),
          for (final n in boards) _netRow(c, n, board: true),
        ],
      ),
      if (_joined != null) ...[
        const SizedBox(height: 12),
        Panel(
          border: _test == PillState.failed ? c.red.withValues(alpha: 0.6) : c.green.withValues(alpha: 0.6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(Ic.checkCircle, color: c.green, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text('Unido a «$_joined». La app habla con la placa por esta red.', style: T.small)),
            ]),
            if (_testMsg != null) ...[
              const SizedBox(height: 10),
              Text(_testMsg!, style: T.small.copyWith(color: _test == PillState.done ? c.green : c.red)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: PillButton(
                  _test == PillState.busy ? 'Probando' : 'Probar conexión',
                  small: true,
                  kind: PillKind.secondary,
                  expand: true,
                  state: _test,
                  onTap: _test == PillState.busy ? null : _testBoard,
                ),
              ),
              const SizedBox(width: 8),
              PillButton('Salir de la red', small: true, kind: PillKind.secondary, onTap: _leave),
            ]),
          ]),
        ),
      ],
      if (others.isNotEmpty) ...[
        const SizedBox(height: 14),
        RowGroup(children: [
          ListRow(
            title: 'Otras redes (${others.length})',
            onTap: () => setState(() => _showOtherNets = !_showOtherNets),
            trailing: AnimatedRotation(
              turns: _showOtherNets ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Ic.chevronDown, size: 18, color: c.text3),
            ),
          ),
          if (_showOtherNets) for (final n in others) _netRow(c, n, board: false),
        ]),
      ],
      const SizedBox(height: 14),
      RowGroup(
        footer: _showManual
            ? 'Si el ESP32 se unió a otra red (la de la casa o del colegio), escribe la IP que muestra en el Monitor Serie. '
                'El teléfono debe estar en esa misma red.'
            : null,
        children: [
          ListRow(
            title: 'Dirección manual',
            detail: _showManual ? null : 'IP ${_ip.text} · puerto ${_port.text}',
            onTap: () => setState(() => _showManual = !_showManual),
            trailing: AnimatedRotation(
              turns: _showManual ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Ic.chevronDown, size: 18, color: c.text3),
            ),
          ),
          if (_showManual) ...[
            _FieldRow(label: 'IP', controller: _ip, onChanged: () => setState(() {})),
            _FieldRow(label: 'Puerto', controller: _port, onChanged: () => setState(() {})),
          ],
        ],
      ),
    ];
  }

  Widget _netRow(Palette c, WifiNetwork n, {required bool board}) {
    final joined = _joined == n.ssid;
    final joining = _joining == n.ssid;
    return ListRow(
      icon: Ic.wifi,
      iconColor: board ? c.text : c.text3,
      title: n.ssid,
      detail: board ? 'Red de la placa' : [n.secure ? 'Con contraseña' : 'Abierta', '${n.ghz} GHz'].join(' · '),
      onTap: board && !joined && _joining == null ? () => _join(n) : null,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _SignalBars(n.bars),
        if (board) ...[
          const SizedBox(width: 12),
          joined
              ? Icon(Ic.checkCircle, color: c.green, size: 22)
              : PillButton(joining ? 'Uniendo' : 'Unirse',
                  small: true, state: joining ? PillState.busy : PillState.idle, onTap: _joining == null ? () => _join(n) : null),
        ],
      ]),
    );
  }
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
    final c = context.c;
    final bars = rssi > -60 ? 3 : (rssi > -75 ? 2 : 1);
    return ListRow(
      icon: board ? Ic.board : Ic.bluetooth,
      iconColor: board ? c.text : c.text3,
      title: name,
      detail: id,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        _SignalBars(bars),
        const SizedBox(width: 12),
        SizedBox(width: 22, child: selected ? Icon(Ic.checkCircle, color: c.green, size: 22) : null),
      ]),
    );
  }
}

class _SignalBars extends StatelessWidget {
  final int level; // 1 a 3
  const _SignalBars(this.level);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (var i = 1; i <= 3; i++)
        Container(
          margin: const EdgeInsets.only(left: 2),
          width: 3,
          height: 5.0 + i * 4,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(1.5), color: i <= level ? c.text : c.line2),
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
            style: T.body.copyWith(color: context.c.text2),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => onChanged(),
          ),
        ),
      ]),
    );
  }
}

enum _BleFix { location, permission }

/// Pide la contraseña de una red. La de la placa viene escrita (es la de fábrica); las demás van ocultas.
class _PasswordSheet extends StatefulWidget {
  final String ssid;
  const _PasswordSheet({required this.ssid});

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  late final bool _board = WifiNet.isBoardSsid(widget.ssid);
  late final _ctrl = TextEditingController(text: _board ? WifiNet.defaultPass(widget.ssid) : '');
  late bool _hidden = !_board;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _ctrl.text;
    if (!WifiNet.validPassword(v)) {
      setState(() => _error = 'De 8 a 63 letras o números, sin tildes ni ñ.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SheetHeader(
            eyebrow: 'Red Wi-Fi',
            title: widget.ssid,
            detail: _board ? 'Es la red que crea el ESP32. Su contraseña de fábrica ya está escrita.' : 'Escribe la contraseña de esta red.',
          ),
        ),
        const SizedBox(height: 18),
        Panel(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                autofocus: !_board,
                obscureText: _hidden,
                style: T.body,
                decoration: const InputDecoration(hintText: 'Contraseña'),
                onSubmitted: (_) => _submit(),
              ),
            ),
            IconButton(
              tooltip: _hidden ? 'Mostrar contraseña' : 'Ocultar contraseña',
              onPressed: () => setState(() => _hidden = !_hidden),
              icon: Icon(_hidden ? Ic.eye : Ic.eyeOff, size: 20, color: c.text2),
            ),
          ]),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(_error!, style: T.small.copyWith(color: c.red))),
        ],
        const SizedBox(height: 18),
        PillButton('Unirse', expand: true, onTap: _submit),
      ]),
    );
  }
}

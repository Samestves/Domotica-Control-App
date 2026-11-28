import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/pantalla.dart';
import '../core/protocol.dart';
import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/carro_ajustes.dart';
import 'widgets/clave.dart';
import 'widgets/drive_controls.dart';
import 'widgets/kit.dart';
import 'widgets/robot_paper.dart';
import 'widgets/robot_tiles.dart';
import 'widgets/status.dart';

/// Panel de manejo en horizontal, como un control remoto.
class CarroPanel extends StatefulWidget {
  final SavedDevice device;
  const CarroPanel({super.key, required this.device});

  @override
  State<CarroPanel> createState() => _CarroPanelState();
}

class _CarroPanelState extends State<CarroPanel> with WidgetsBindingObserver {
  int _jx = 0, _jy = 0, _throttle = 0, _turret = 0;
  final _lastSent = <int, DateTime>{};
  Session? _session;
  Timer? _keepAlive;

  /// Si la sesión estaba conectada la última vez que miramos (para notar cortes y reconexiones).
  bool _wasOn = false;

  /// Falso mientras la app está en segundo plano: no se repite ninguna orden.
  bool _foreground = true;

  /// Avisos de la placa (por ejemplo, «suelta el joystick y el acelerador»).
  StreamSubscription? _messages;

  /// Tablero del robot de cada placa (manejar o escribir), mientras la app está abierta.
  static final _robotModes = <String, RobotMode>{};
  RobotMode get _mode => _robotModes[widget.device.id] ?? RobotMode.drive;

  /// Velocidad lenta: el joystick y el acelerador valen un tercio, para ubicar el robot en la hoja con precisión.
  bool _slow = false;
  static const _slowFactor = .35;

  /// Lo que dibujó el robot, para verlo en la hoja: se arma con cada posición que dice la placa.
  final _trail = RobotTrail();

  /// El texto que se está escribiendo en el modo escribir: la hoja muestra dónde caería.
  final _draft = ValueNotifier<String>('');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.read(context).session(widget.device);
    if (s == _session) return;
    _session?.removeListener(_onSession);
    _session?.telemetry.removeListener(_onTelemetry);
    _messages?.cancel();
    _messages = s.messages.listen(_onMessage);
    _session = s..addListener(_onSession);
    s.telemetry.addListener(_onTelemetry);
    _wasOn = s.connected;
    // Al abrir el panel, la placa recibe «quieto» antes de cualquier movimiento.
    if (s.connected) WidgetsBinding.instance.addPostFrameCallback((_) => _sendNeutral());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _keepAlive = Timer.periodic(CarPins.keepAlive, (_) => _repeat());
    Pantalla.encendida(true); // si la pantalla se apagara manejando, el carrito frenaría
  }

  /// Si se corta la conexión, el acelerador y el joystick vuelven a cero: al reconectar, el carro
  /// no arranca solo con la orden vieja. Al volver la conexión, la placa recibe «quieto».
  void _onSession() {
    _onTelemetry(); // el lápiz pudo bajar justo donde está: ahí empieza la tinta
    final on = _session?.connected ?? false;
    if (on == _wasOn || !mounted) return;
    _wasOn = on;
    if (on) {
      scheduleMicrotask(_sendNeutral);
    } else {
      setState(_zeroControls);
    }
  }

  /// Cada posición nueva del robot: si el marcador está abajo, es tinta en la hoja.
  void _onTelemetry() {
    final s = _session;
    if (s != null && isRobot(s)) _trail.add(robotPose(s), penDown: s.values[CarPins.pen] == '1');
  }

  /// La placa puso el seguro (se cortó la señal): la app suelta sus controles y le avisa «quieto».
  /// Para volver a andar hay que acelerar o mover el joystick otra vez, a propósito.
  void _onMessage(Msg m) {
    if (m.kind != 'ERR' || !m.value.startsWith('suelta') || !mounted) return;
    HapticFeedback.heavyImpact();
    setState(_zeroControls);
    _sendNeutral();
  }

  /// Si la app pasa a segundo plano (Inicio, una llamada, pantalla apagada), el carro frena.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground || !mounted) return;
    setState(_zeroControls);
    _sendNeutral();
  }

  void _zeroControls() {
    _jx = 0;
    _jy = 0;
    _throttle = 0;
  }

  void _sendNeutral() => _neutral(_session);

  static void _neutral(Session? s) {
    if (s == null || !s.connected) return;
    s.send(CarPins.joystick, '0,0', quiet: true);
    s.send(CarPins.throttle, 0, quiet: true);
  }

  /// Mientras el carro anda, repite la orden actual: la placa frena sola si deja de recibirla.
  /// También corrige el último movimiento del joystick si se lo saltó el límite de 90 ms.
  void _repeat() {
    final s = _session;
    if (s == null || !s.connected || !_foreground) return;
    if (_jx != 0 || _jy != 0) s.send(CarPins.joystick, _joyWire(_jx, _jy), quiet: true);
    if (_throttle != 0) s.send(CarPins.throttle, _scaled(_throttle), quiet: true);
  }

  @override
  void dispose() {
    _keepAlive?.cancel();
    _messages?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _session?.removeListener(_onSession);
    _session?.telemetry.removeListener(_onTelemetry);
    _trail.dispose();
    _draft.dispose();
    // Al salir: detener el carro (justo después, para no redibujar mientras se cierra la pantalla)
    // y volver a la orientación normal.
    final s = _session;
    scheduleMicrotask(() => _neutral(s));
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    Pantalla.encendida(false);
    super.dispose();
  }

  /// En velocidad lenta, un tercio de lo pedido (el robot se ubica con precisión en la hoja).
  int _scaled(int v) => _slow ? (v * _slowFactor).round() : v;
  String _joyWire(int x, int y) => '${_scaled(x)},${_scaled(y)}';

  /// Limita los mensajes continuos (joystick, dial, acelerador) a uno cada 90 ms por pin.
  void _sendThrottled(Session s, int pin, Object v, {bool force = false}) {
    final now = DateTime.now();
    final last = _lastSent[pin];
    if (!force && last != null && now.difference(last).inMilliseconds < 90) return;
    _lastSent[pin] = now;
    s.send(pin, v);
  }

  void _brake(Session s) {
    HapticFeedback.heavyImpact();
    setState(() => _throttle = 0);
    s.send(CarPins.throttle, 0);
    s.send(CarPins.joystick, '0,0');
  }

  /// Parar todo (el robot): la escritura, las ruedas y la prueba. Vale desde cualquier teléfono.
  void _stopAll(Session s) {
    HapticFeedback.heavyImpact();
    setState(_zeroControls);
    s.sendRaw('PARAR');
    s.send(CarPins.joystick, '0,0');
  }

  Widget _header(BuildContext context, Session s, {required String settings}) => Row(children: [
        RoundButton(icon: Ic.back, tooltip: 'Volver', size: 40, onTap: () => Navigator.pop(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.device.name, style: T.callout, maxLines: 2),
            if (s.connected) ...[const SizedBox(height: 5), ConnectionTag(session: s)],
          ]),
        ),
        RoundButton(icon: Ic.wheels, tooltip: settings, size: 40, onTap: () => showCarroAjustes(context, s)),
      ]);

  Widget _joystick(Session s, double size, {required bool enabled}) => Joystick(
        size: size,
        enabled: enabled,
        onChanged: (x, y) {
          setState(() {
            _jx = x;
            _jy = y;
          });
          _sendThrottled(s, CarPins.joystick, _joyWire(x, y), force: x == 0 && y == 0);
        },
      );

  /// Conectado, el estado va bajo el nombre; esta tarjeta solo aparece cuando hay algo que hacer
  /// (conectar, reintentar, la clave). Siempre ocupa su lugar (vacío si no hace falta): así lo de abajo
  /// no cambia de posición y no pierde lo que tenía (por ejemplo, el texto a medio escribir).
  Widget _connectionCard(Session s) => s.connected
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: ConnectionBar(session: s)),
        );

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = AppScope.of(context).session(widget.device);
    final overlay = (c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent);

    // El carrito (desde carro-0.4) pide clave como la casa: hasta tenerla, se muestra la tarjeta.
    if (showsClaveCard(s)) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 18, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                RoundButton(icon: Ic.back, tooltip: 'Volver', size: 40, onTap: () => Navigator.pop(context)),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 12), child: ClaveCard(session: s)),
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ]),
            ),
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 18, 12),
            // El robot que escribe (carro-0.6) y el carrito 4x4 (carro-0.5) tienen piezas distintas: cada uno su
            // tablero. La placa dice cuál es al conectarse (el robot dice su lápiz).
            child: LayoutBuilder(builder: (context, box) => isRobot(s) ? _robotBoard(context, s, box) : _carBoard(context, s, box)),
          ),
        ),
      ),
    );
  }

  /// Qué hace el robot, en pocas palabras: un aviso reciente de la placa, la letra que escribe o cómo se mueve.
  String _robotStatus(Session s) {
    if (!s.connected) return 'Sin conexión';
    final notice = recentNotice(s);
    if (notice != null) return notice;
    final p = writingProgress(s);
    if (p != null) return 'Escribiendo · letra ${p.$1} de ${p.$2}';
    if (robotGoing(s)) return 'Yendo al punto de la hoja';
    final motion = motionText(_jx, _jy, _throttle, reverse: s.values[CarPins.reverse] == '1');
    return _slow && motion != 'Quieto' ? '$motion · lento' : motion;
  }

  void _setMode(RobotMode m) {
    if (m == _mode) return;
    // Al cambiar de tablero el robot recibe «quieto»: el joystick o el acelerador no quedan puestos.
    setState(() {
      _robotModes[widget.device.id] = m;
      _zeroControls();
    });
    _sendNeutral();
  }

  /// Arriba: volver, el nombre y su conexión, el selector Manejar / Escribir y los ajustes.
  Widget _robotTopBar(BuildContext context, Session s) => Row(children: [
        RoundButton(icon: Ic.back, tooltip: 'Volver', size: 40, onTap: () => Navigator.pop(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Row(children: [
            Flexible(child: Text(widget.device.name, style: T.callout, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (s.connected) ...[const SizedBox(width: 10), ConnectionTag(session: s)],
          ]),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 250,
          child: Segmented<RobotMode>(
            value: _mode,
            items: const {RobotMode.drive: 'Manejar', RobotMode.write: 'Escribir'},
            icons: const {RobotMode.drive: Ic.steering, RobotMode.write: Ic.write},
            onChanged: _setMode,
          ),
        ),
        const SizedBox(width: 12),
        RoundButton(icon: Ic.wheels, tooltip: 'Ajustes del robot', size: 40, onTap: () => showCarroAjustes(context, s)),
      ]);

  /// El robot: arriba el selector de modo y abajo su tablero, que cambia con una transición suave.
  /// Con el teclado abierto queda poco alto: la barra de arriba y las columnas de los lados se achican a nada en
  /// su lugar (no se quitan), así la tarjeta de escribir no se rearma y no pierde el texto ni el teclado.
  Widget _robotBoard(BuildContext context, Session s, BoxConstraints box) {
    final roomy = box.maxHeight >= 200;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(child: roomy ? Padding(padding: const EdgeInsets.only(bottom: 10), child: _robotTopBar(context, s)) : null),
      _connectionCard(s),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: .985, end: 1.0).animate(a), child: child),
          ),
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: KeyedSubtree(
            key: ValueKey(_mode),
            child: LayoutBuilder(
              builder: (context, b) => _mode == RobotMode.drive ? _driveBoard(context, s, b) : _writeBoard(context, s, b, roomy: roomy),
            ),
          ),
        ),
      ),
    ]);
  }

  /// Manejar, como un control remoto: el joystick a la izquierda; la cara, la hoja y el lápiz al centro; el
  /// acelerador y reversa, velocidad y parar a la derecha. En teléfonos angostos la cara no entra y el lápiz va
  /// debajo de la hoja.
  Widget _driveBoard(BuildContext context, Session s, BoxConstraints box) {
    final c = context.c;
    final on = s.connected, busy = robotBusy(s);
    final reverse = s.values[CarPins.reverse] == '1';
    const gap = 10.0, throttleW = 64.0;
    final joyW = (box.maxWidth * .30).clamp(176.0, 270.0);
    final railW = (box.maxWidth * .16).clamp(108.0, 150.0);
    final centerW = box.maxWidth - joyW - throttleW - railW - 4 * gap;
    final wide = centerW >= 300;
    // La cara: dos pantallas de 2:1, una al lado de la otra, más su título.
    final faceH = ((centerW - 38) / 4 + 46).clamp(96.0, 150.0);
    final paper = PaperTile(session: s, trail: _trail, onOpenSettings: () => showCarroAjustes(context, s));
    final pen = PenTile(session: s);
    final stopValue = writingProgress(s) != null ? 'Escritura' : (robotGoing(s) ? 'Camino' : 'Todo');
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: joyW,
        child: DriveTile(session: s, status: _robotStatus(s), joystick: (size) => _joystick(s, size, enabled: on && !busy)),
      ),
      const SizedBox(width: gap),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (wide) ...[SizedBox(height: faceH, child: FaceTile(session: s)), const SizedBox(height: gap)],
          Expanded(
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: paper),
                    const SizedBox(width: gap),
                    SizedBox(width: 118, child: pen),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: paper),
                    const SizedBox(height: gap),
                    SizedBox(height: 72, child: pen),
                  ]),
          ),
        ]),
      ),
      const SizedBox(width: gap),
      SizedBox(
        width: throttleW,
        child: Throttle(
          value: _throttle,
          enabled: on && !busy,
          onChanged: (v) {
            setState(() => _throttle = v);
            _sendThrottled(s, CarPins.throttle, _scaled(v), force: v == 0);
          },
        ),
      ),
      const SizedBox(width: gap),
      SizedBox(
        width: railW,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: BentoTile(
              icon: Ic.reverse,
              label: 'Reversa',
              value: reverse ? 'Puesta' : 'No',
              active: reverse,
              accent: c.amber,
              onTap: on ? () => s.send(CarPins.reverse, reverse ? 0 : 1) : null,
            ),
          ),
          const SizedBox(height: gap),
          Expanded(
            child: BentoTile(
              icon: Ic.speed,
              label: 'Velocidad',
              value: _slow ? 'Lenta' : 'Normal',
              active: _slow,
              accent: c.green,
              onTap: on ? () => setState(() => _slow = !_slow) : null,
            ),
          ),
          const SizedBox(height: gap),
          Expanded(
            child: BentoTile(icon: Ic.brake, label: 'Parar', value: stopValue, active: true, accent: c.red, onTap: on ? () => _stopAll(s) : null),
          ),
        ]),
      ),
    ]);
  }

  /// Escribir: el texto con su vista previa (lo más grande) y a la derecha la hoja con dónde caería, el lápiz y
  /// parar. Con el teclado abierto ([roomy] falso) la columna de la derecha se achica a nada en su lugar.
  Widget _writeBoard(BuildContext context, Session s, BoxConstraints box, {required bool roomy}) {
    final c = context.c;
    final on = s.connected;
    const gap = 10.0;
    final railW = roomy ? (box.maxWidth * .34).clamp(220.0, 320.0) : 0.0;
    final stopValue = writingProgress(s) != null ? 'Escritura' : (robotGoing(s) ? 'Camino' : 'Todo');
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: WriteTile(session: s, draft: _draft, onOpenSettings: () => showCarroAjustes(context, s), onStop: () => _stopAll(s)),
      ),
      SizedBox(width: roomy ? gap : 0),
      SizedBox(
        width: railW,
        child: !roomy
            ? null
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: ValueListenableBuilder(
                    valueListenable: _draft,
                    builder: (context, draft, _) =>
                        PaperTile(session: s, trail: _trail, text: draft, onOpenSettings: () => showCarroAjustes(context, s)),
                  ),
                ),
                const SizedBox(height: gap),
                SizedBox(
                  height: 76,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: PenTile(session: s)),
                    const SizedBox(width: gap),
                    Expanded(
                      child: BentoTile(icon: Ic.brake, label: 'Parar', value: stopValue, active: true, accent: c.red, onTap: on ? () => _stopAll(s) : null),
                    ),
                  ]),
                ),
              ]),
      ),
    ]);
  }

  /// Carrito 4x4: joystick a la izquierda; obstáculo, torreta y qué hace al centro; acelerador y botones a la derecha.
  Widget _carBoard(BuildContext context, Session s, BoxConstraints box) {
    final c = context.c;
    final on = s.connected;
    final dist = int.tryParse(s.values[CarPins.distance] ?? '');
    // Reversa y luces: lo que dice la placa (las recuerda aunque se salga del panel).
    final reverse = s.values[CarPins.reverse] == '1';
    final lights = s.values[CarPins.lights] == '1';
    // En teléfonos chicos (640 × 360) las columnas de los lados se angostan y la torreta se achica.
    final side = (box.maxWidth * 0.28).clamp(168.0, 216.0);
    final compact = box.maxWidth - 2 * side - 28 < 330;
    final buttons = [
      BentoTile(icon: Ic.reverse, label: 'Reversa', active: reverse, accent: c.amber, row: true, onTap: on ? () => s.send(CarPins.reverse, reverse ? 0 : 1) : null),
      BentoTile(icon: Ic.headlights, label: 'Luces', active: lights, row: true, onTap: on ? () => s.send(CarPins.lights, lights ? 0 : 1) : null),
      BentoTile(
        icon: Ic.horn,
        label: 'Bocina',
        row: true,
        onTap: on
            ? () {
                HapticFeedback.mediumImpact();
                s.send(CarPins.horn, 1, remember: false);
              }
            : null,
      ),
      BentoTile(icon: Ic.brake, label: 'Freno', active: true, accent: c.red, row: true, onTap: on ? () => _brake(s) : null),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        width: side,
        child: Column(children: [
          _header(context, s, settings: 'Ruedas'),
          Expanded(child: Center(child: _joystick(s, side < 190 ? side - 8 : 176, enabled: on))),
        ]),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(children: [
          _connectionCard(s),
          // La velocidad ya la muestra el acelerador y la dirección el joystick: aquí solo lo que
          // el conductor no ve desde lejos, la distancia al obstáculo.
          _ObstacleBar(distance: dist),
          const SizedBox(height: 10),
          Expanded(
            child: Row(children: [
              // La torreta aparece solo si la placa dice que tiene una (envía V21 al conectar).
              if (s.values.containsKey(CarPins.turret)) ...[
                Panel(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
                  child: Row(children: [
                    Dial360(
                      value: _turret,
                      size: compact ? 84 : 104,
                      enabled: on,
                      onChanged: (v) {
                        setState(() => _turret = v);
                        _sendThrottled(s, CarPins.turret, v);
                      },
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      const Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Eyebrow('Torreta'),
                        SizedBox(height: 4),
                        Text('Giro 360°', style: T.callout),
                      ]),
                    ],
                  ]),
                ),
                const SizedBox(width: 10),
              ],
              // Lo técnico (los mensajes con la placa) solo en el modo técnico: manejando importa qué hace.
              Expanded(
                child: AppScope.of(context).showPins
                    ? _MiniLog(session: s)
                    : _DriveStatus(session: s, x: _jx, y: _jy, throttle: _throttle, reverse: reverse),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(width: 14),
      SizedBox(
        width: side,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Throttle(
            value: _throttle,
            enabled: on,
            onChanged: (v) {
              setState(() => _throttle = v);
              _sendThrottled(s, CarPins.throttle, v, force: v == 0);
            },
          ),
          const SizedBox(width: 10),
          // Cuatro tarjetas iguales que se reparten el alto: lo que más se toca, a mano.
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var i = 0; i < buttons.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                Expanded(child: buttons[i]),
              ],
            ]),
          ),
        ]),
      ),
    ]);
  }
}

/// Distancia al obstáculo de adelante: una barra que se llena al acercarse. Verde lejos, ámbar cerca
/// y roja (con la tarjeta entera en rojo) cuando hay que frenar.
class _ObstacleBar extends StatelessWidget {
  final int? distance;
  const _ObstacleBar({required this.distance});

  /// Desde esta distancia la barra empieza a llenarse.
  static const _range = 150.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = distance;
    final near = d != null && d < 20;
    final color = d == null ? c.text3 : (near ? c.red : (d < 50 ? c.amber : c.green));
    final fill = d == null ? 0.0 : (1 - d / _range).clamp(0.04, 1.0);
    return Semantics(
      label: d == null ? 'Obstáculo: sin datos del sensor' : 'Obstáculo a $d centímetros',
      excludeSemantics: true,
      child: Panel(
        color: near ? c.red.withValues(alpha: 0.12) : null,
        border: near ? c.red : null,
        padding: const EdgeInsets.fromLTRB(14, 10, 16, 12),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Ic.distance, size: 14, color: near ? c.red : c.text2),
              const SizedBox(width: 6),
              Eyebrow(near ? 'Obstáculo cerca' : 'Obstáculo', color: near ? c.red : null, maxLines: 1),
            ]),
            const SizedBox(height: 6),
            Text(d == null ? '—' : '$d cm', maxLines: 1, style: T.stat.copyWith(fontSize: 22, color: d == null ? c.text3 : (near ? c.red : c.text))),
          ]),
          const SizedBox(width: 18),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 8,
                color: c.surface2,
                alignment: Alignment.centerLeft,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: fill),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  builder: (_, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: AnimatedContainer(duration: const Duration(milliseconds: 220), color: color),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Qué hace el carrito, en grande, para verlo de reojo: «Adelante · 60 %», «Girando a la izquierda», «Quieto».
/// Si la placa acaba de avisar algo («otro teléfono está manejando»), se muestra eso unos segundos.
class _DriveStatus extends StatelessWidget {
  final Session session;
  final int x, y, throttle;
  final bool reverse;
  const _DriveStatus({required this.session, required this.x, required this.y, required this.throttle, required this.reverse});

  static const _noticeFor = Duration(seconds: 6);


  String _motion() => session.connected ? motionText(x, y, throttle, reverse: reverse) : 'Sin conexión';

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final notice = recentNotice(session, within: _noticeFor);
    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        if (notice != null) ...[
          Icon(Ic.warning, size: 22, color: c.amber),
          const SizedBox(height: 8),
          Text(notice, style: T.body.copyWith(color: c.text), maxLines: 3, overflow: TextOverflow.ellipsis),
        ] else ...[
          Text('Ahora', style: T.small.copyWith(color: c.text3)),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text(_motion(), key: ValueKey(_motion()), style: T.title, maxLines: 2),
          ),
        ],
      ]),
    );
  }
}

class _MiniLog extends StatelessWidget {
  final Session session;
  const _MiniLog({required this.session});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final items = session.log.take(4).toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final l in items)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: l.incoming ? '← ' : '→ ', style: TextStyle(color: l.incoming ? c.amber : c.green)),
              TextSpan(text: l.text, style: TextStyle(color: l.incoming ? c.text : c.text2)),
            ]),
            maxLines: 2,
            style: T.mono.copyWith(fontSize: 11),
          ),
        if (items.isEmpty) Text('Sin mensajes', style: T.mono.copyWith(fontSize: 11, color: c.text3)),
      ]),
    );
  }
}

/// Cómo se mueve, en pocas palabras: «Adelante · 60 %», «Girando a la izquierda», «Quieto».
String motionText(int x, int y, int throttle, {required bool reverse}) {
  if (x.abs() > 20 && x.abs() >= y.abs()) return x > 0 ? 'Girando a la derecha' : 'Girando a la izquierda';
  if (y > 10) return 'Adelante · $y %';
  if (y < -10) return 'Atrás · ${-y} %';
  if (throttle > 0) return reverse ? 'Reversa · $throttle %' : 'Adelante · $throttle %';
  return 'Quieto';
}

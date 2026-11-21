import 'dart:convert';

import 'package:control_domotica/core/casa_sim.dart';
import 'package:control_domotica/core/demo_link.dart';
import 'package:control_domotica/core/link.dart';
import 'package:control_domotica/core/protocol.dart';
import 'package:control_domotica/core/wifi_net.dart';
import 'package:control_domotica/main.dart';
import 'package:control_domotica/models/controls.dart';
import 'package:control_domotica/models/device.dart';
import 'package:control_domotica/state/app_state.dart';
import 'package:control_domotica/ui/carro_panel.dart';
import 'package:control_domotica/ui/credits_screen.dart';
import 'package:control_domotica/ui/widgets/carro_ajustes.dart';
import 'package:control_domotica/ui/widgets/casa_tiles.dart';
import 'package:control_domotica/ui/widgets/drive_controls.dart';
import 'package:control_domotica/ui/widgets/kit.dart';
import 'package:control_domotica/ui/widgets/status.dart';
import 'package:control_domotica/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Protocolo', () {
    test('lee mensajes de pin virtual', () {
      final m = Msg.parse('V10:24.1');
      expect(m.pin, 10);
      expect(m.value, '24.1');
      expect(Msg.parse('V20:-40,85').value, '-40,85');
    });

    test('lee mensajes de sistema', () {
      expect(Msg.parse('PONG').kind, 'PONG');
      final ok = Msg.parse('OK:V1:23:1');
      expect(ok.kind, 'OK');
      expect(ok.value, 'V1:23:1');
      expect(ok.isPin, isFalse);
    });

    test('arma mensajes y quita saltos de línea', () {
      expect(pinMsg(6, 'Hola\nmundo'), 'V6:Hola mundo');
      expect(cfgMsg(1, 23, inverted: true), 'CFG:V1:23:1:1');
      expect(cfgMsg(11, 34, inverted: false, enabled: false), 'CFG:V11:34:0:0');
    });

    test('junta trozos en líneas completas', () {
      final b = LineBuffer();
      expect(b.add('V1:'), isEmpty);
      expect(b.add('1\nV2:0\nV3'), ['V1:1', 'V2:0']);
      expect(b.add(':90\n'), ['V3:90']);
    });
  });

  test('guarda y lee dispositivos con sus pines', () {
    final d = SavedDevice(id: 'x', name: 'Casa', profile: Profile.casa, transport: Transport.wifi, address: '192.168.1.40');
    d.pins[1] = const PinConfig(22, inverted: true, enabled: false);
    final back = SavedDevice.fromJson(d.toJson());
    expect(back.transport, Transport.wifi);
    expect(back.pins[1]!.gpio, 22);
    expect(back.pins[1]!.inverted, isTrue);
    expect(back.pins[1]!.enabled, isFalse);
    expect(back.clave, isNull);
    d.clave = '482913';
    expect(SavedDevice.fromJson(d.toJson()).clave, '482913');
  });

  test('valida los GPIO igual que la placa', () {
    expect(gpioProblem(23, output: true), isNull);
    expect(gpioProblem(34, output: false), isNull);
    expect(gpioProblem(34, output: true), isNotNull); // solo entrada
    expect(gpioProblem(7, output: true), isNotNull); // memoria interna
    expect(gpioProblem(24, output: true), isNotNull); // no existe
    expect(gpioProblem(1, output: true), isNotNull); // cable USB (Monitor Serie)
    expect(gpioProblem(3, output: true), isNotNull);
    // Contraseñas Wi-Fi que Android acepta (si no, se perdería la red actual con un error en inglés).
    expect(WifiNet.validPassword('carrito4x4'), isTrue);
    expect(WifiNet.validPassword(''), isTrue, reason: 'red abierta');
    expect(WifiNet.validPassword('corta'), isFalse);
    expect(WifiNet.validPassword('contraseña1'), isFalse, reason: 'la ñ no la acepta Android');
    expect(gpioProblem(40, output: true), isNotNull);
  });

  test('al conectar envía los pines guardados a la placa', () async {
    final d = SavedDevice(id: 'd', name: 'Casa', profile: Profile.casa, transport: Transport.demo);
    d.pins[1] = const PinConfig(22, inverted: false);
    final s = Session(d);
    await s.connect();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(s.log.map((l) => l.text), containsAll(['CFG:V1:22:0:1', 'OK:V1:22:0:1', 'SYNC']));
    await s.disconnect();
  });

  test('si la conexión se cae, reintenta sola; si el usuario desconecta, no', () async {
    final links = <_FlakyLink>[];
    final d = SavedDevice(id: 'r', name: 'Casa', profile: Profile.casa, transport: Transport.ble);
    final s = Session(d, linkFor: (_) {
      links.add(_FlakyLink());
      return links.last;
    });
    await s.connect();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.connected, isTrue);

    links.last.drop();
    await Future<void>.delayed(Duration.zero);
    expect(s.retrying, isTrue);
    await Future<void>.delayed(Session.retryDelays.first + const Duration(milliseconds: 300));
    expect(links.length, 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(s.connected, isTrue);

    await s.disconnect();
    await Future<void>.delayed(Session.retryDelays.first + const Duration(milliseconds: 300));
    expect(links.length, 2);
    expect(s.connected, isFalse);
  });

  group('Conexión', () {
    final d = SavedDevice(id: 'h', name: 'Casa', profile: Profile.casa, transport: Transport.ble);

    testWidgets('si la placa se apaga sin avisar, el latido lo nota y la app reintenta', (t) async {
      final links = <_FlakyLink>[];
      final s = Session(d, linkFor: (_) => (links..add(_FlakyLink())).last);
      await s.connect();
      await t.pump(const Duration(milliseconds: 100));
      expect(s.connected, isTrue);
      expect(connOf(s), Conn.connected);

      // La placa ya no contesta nada (ni al PING): al pasar el límite de silencio, la conexión se da por caída.
      await t.pump(Session.silenceLimit + Session.heartbeat + const Duration(milliseconds: 100));
      expect(s.connected, isFalse);
      expect(connOf(s), Conn.reconnecting);
      expect(s.attempt, 1);

      // Siempre se puede cancelar: no queda «conectando» para siempre.
      await s.disconnect();
      await t.pump(Session.retryDelays.last * 2);
      expect(links.length, 1, reason: 'cancelado: no vuelve a intentar');
      expect(connOf(s), Conn.off);
    });

    testWidgets('si nunca vuelve, después de los reintentos queda «Sin conexión» con Reintentar', (t) async {
      final s = Session(d, linkFor: (_) => _DeadLink());
      await s.connect();
      for (final wait in Session.retryDelays) {
        expect(connOf(s), anyOf(Conn.reconnecting, Conn.failed));
        await t.pump(wait + const Duration(milliseconds: 50));
      }
      expect(s.retrying, isFalse);
      expect(connOf(s), Conn.failed);
      expect(s.error, isNotNull);
      await s.disconnect();
    });

    testWidgets('cancelar mientras conecta deja la placa desconectada, sin error', (t) async {
      final s = Session(d, linkFor: (_) => _SlowLink());
      final connecting = s.connect();
      await t.pump(const Duration(milliseconds: 100));
      expect(connOf(s), Conn.connecting);
      await s.disconnect();
      await t.pump(const Duration(seconds: 2));
      await connecting;
      expect(connOf(s), Conn.off);
    });
  });

  group('Conexión robusta (auditoría)', () {
    final d = SavedDevice(id: 'q', name: 'Casa', profile: Profile.casa, transport: Transport.ble);

    test('varias escrituras fallidas seguidas gastan un solo reintento y conservan el primer motivo', () async {
      final links = <_FlakyLink>[];
      final s = Session(d, linkFor: (_) => (links..add(_FlakyLink())).last);
      await s.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(s.connected, isTrue);
      links.single
        ..setState(LinkState.error, 'La placa se desconectó.')
        ..setState(LinkState.error, 'No se pudo enviar por Bluetooth.')
        ..setState(LinkState.error, 'No se pudo enviar por Bluetooth.');
      await Future<void>.delayed(Duration.zero);
      expect(s.attempt, 1, reason: 'una caída = un intento, no tres');
      expect(s.error, 'La placa se desconectó.');
      await s.disconnect();
    });

    // Con tiempo real: cerrar la conexión vieja necesita vueltas reales del reloj.
    test('cancelar y volver a conectar: la conexión vieja que termina tarde no estorba', () async {
      final links = <_SlowLink>[];
      final s = Session(d, linkFor: (_) => (links..add(_SlowLink())).last);
      final first = s.connect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await s.disconnect();
      final second = s.connect();
      await Future.wait([first, second]);
      await Future<void>.delayed(Session.claveTimeout + const Duration(milliseconds: 300)); // placa sin clave
      expect(links.length, 2);
      expect(links.first.state, isNot(LinkState.connected), reason: 'la vieja quedó cerrada');
      expect(s.connected, isTrue, reason: 'la nueva es la que vale');
      await s.disconnect();
    });

    test('dos toques en Conectar abren una sola conexión', () async {
      final links = <_SlowLink>[];
      final s = Session(d, linkFor: (_) => (links..add(_SlowLink())).last);
      await Future.wait([s.connect(), s.connect()]);
      expect(links.length, 1);
      await s.disconnect();
    });

    test('una respuesta de clave desconocida no deja «Conectando» para siempre', () async {
      final s = Session(d, linkFor: (_) => _ReplyLink('AUTH:RARO'));
      await s.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.clave, ClaveState.ask);
      expect(s.claveMessage, contains('RARO'));
      await s.disconnect();
    });

    test('«Clave cambiada» solo aparece si el usuario la cambió', () async {
      // Una casa lenta que contesta AUTH:OK después del tiempo de espera.
      final s = Session(d, linkFor: (_) => _ReplyLink('AUTH:OK', delay: Session.claveTimeout + const Duration(milliseconds: 300)));
      await s.connect();
      await Future<void>.delayed(Session.claveTimeout + const Duration(milliseconds: 700));
      expect(s.connected, isTrue);
      expect(s.claveMessage, isNull);
      await s.disconnect();
    });

    test('repetir la misma orden en silencio no redibuja la pantalla', () async {
      final s = Session(d, linkFor: (_) => _FlakyLink());
      var redraws = 0;
      s.addListener(() => redraws++);
      s.send(CarPins.throttle, 50, quiet: true);
      expect(redraws, 1, reason: 'cambió: hay que mostrarlo');
      s.send(CarPins.throttle, 50, quiet: true);
      expect(redraws, 1, reason: 'igual que antes: no hace falta');
      s.send(CarPins.throttle, 60, quiet: true);
      expect(redraws, 2);
    });

    test('las letras con tilde partidas entre dos paquetes llegan bien', () {
      final b = LineBuffer();
      final bytes = utf8.encode('OK:luces 5 · bocina ñ\n');
      final cut = bytes.indexOf(0xC2) + 1; // justo en medio del «·»
      expect(b.addBytes(bytes.sublist(0, cut)), isEmpty);
      expect(b.addBytes(bytes.sublist(cut)), ['OK:luces 5 · bocina ñ']);
      expect(b.addBytes([0xFF, 0x41, 0x0A]), ['\uFFFDA'], reason: 'un byte raro no corta la conexión');
      expect(b.addBytes([...List.filled(LineBuffer.maxLine + 10, 0x41), 0x0A, 0x42, 0x0A]), ['B'],
          reason: 'una línea larguísima se descarta entera');
    });

    test('Android deja una sola red de placa: una segunda placa por Wi-Fi avisa en vez de pisar la otra', () {
      WifiNet.claim('Casa Domotica');
      expect(WifiNet.busyWith('Carrito 4x4'), 'Casa Domotica');
      expect(WifiNet.busyWith('Casa Domotica'), isNull, reason: 'la misma red sí se puede compartir');
      WifiNet.unclaim('Casa Domotica');
      expect(WifiNet.busyWith('Carrito 4x4'), isNull);
    });
  });

  group('Datos guardados (auditoría)', () {
    final good = SavedDevice(id: 'a', name: 'Casa', profile: Profile.casa, transport: Transport.ble, address: 'X').toJson();

    test('un dispositivo que esta versión no entiende no borra los demás y se conserva', () async {
      final future = {...good, 'id': 'r', 'profile': 'robot'}; // de una versión más nueva de la app
      SharedPreferences.setMockInitialValues({'devices_v1': jsonEncode([future, good])});
      final app = AppState();
      await app.load();
      expect(app.devices.map((d) => d.id), ['a']);
      await app.save();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('devices_v1')!) as List<dynamic>;
      expect(saved.map((e) => (e as Map)['id']), containsAll(['a', 'r']), reason: 'el robot sigue guardado');
    });

    test('si todo está dañado, se guarda una copia y la app abre igual', () async {
      SharedPreferences.setMockInitialValues({'devices_v1': '{basura', 'ui_show_pins': 'no es bool'});
      final app = AppState();
      await app.load();
      expect(app.devices, isEmpty);
      expect(app.showPins, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('devices_v1_respaldo'), '{basura');
    });

    test('si el usuario borra todas las placas, las demos no vuelven a aparecer', () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState();
      await app.load();
      expect(app.devices, hasLength(2), reason: 'primer uso: dos demos');
      for (final d in [...app.devices]) {
        await app.remove(d);
      }
      final again = AppState();
      await again.load();
      expect(again.devices, isEmpty);
    });
  });

  group('Novedades al actualizar', () {
    final saved = jsonEncode([SavedDevice(id: 'a', name: 'Casa', profile: Profile.casa, transport: Transport.ble, address: 'X').toJson()]);
    Future<AppState> loaded(Map<String, Object> prefs) async {
      SharedPreferences.setMockInitialValues(prefs);
      final app = AppState();
      await app.load();
      return app;
    }

    test('la primera instalación no las muestra', () async {
      expect((await loaded({})).newsPending, isFalse);
      final again = AppState();
      await again.load();
      expect(again.newsPending, isFalse, reason: 'quedó anotado que ya conoce esta versión');
    });

    test('quien viene de la 0.9.1 (que no anotaba nada) las ve una sola vez', () async {
      final app = await loaded({'devices_v1': saved});
      expect(app.newsPending, isTrue);
      await app.markNewsSeen();
      final again = AppState();
      await again.load();
      expect(again.newsPending, isFalse);
    });

    test('salen con cada versión nueva, pero no al volver a una vieja', () async {
      expect((await loaded({'devices_v1': saved, 'novedades_vistas': appBuild - 1})).newsPending, isTrue);
      expect((await loaded({'devices_v1': saved, 'novedades_vistas': appBuild})).newsPending, isFalse);
      expect((await loaded({'devices_v1': saved, 'novedades_vistas': appBuild + 3})).newsPending, isFalse);
    });

    test('hay novedades escritas para esta versión', () {
      expect(appNews, isNotEmpty);
      expect(appNews.every((n) => n.trim().isNotEmpty && !n.contains("'")), isTrue, reason: 'publicar.ps1 las lee entre comillas simples');
    });

    testWidgets('al abrir la app recién actualizada sale la hoja, una sola vez', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(800, 1400);
      addTearDown(t.view.reset);
      final app = await loaded({'devices_v1': saved});
      await t.pumpWidget(ControlApp(state: app));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Qué hay de nuevo'), findsOneWidget);
      expect(find.text(appNews.first), findsOneWidget);
      expect(find.text('Actualizada a $appVersion'.toUpperCase()), findsOneWidget);

      await t.tap(find.text('ENTENDIDO'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('Qué hay de nuevo'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('novedades_vistas'), appBuild);
    });
  });

  group('Casa del grupo', () {
    test('el mapa de pines coincide con su documento de conexiones', () {
      final all = [...casaControls, casaSiren];
      expect(all.map((c) => c.vpin).toSet(), {for (var v = 0; v <= 15; v++) v});
      expect(all.map((c) => c.gpio).toSet().length, all.length, reason: 'dos controles en el mismo GPIO');
      expect(casaControls.firstWhere((c) => c.vpin == 10).gpio, 2); // Luz sala 1 = LED azul de la placa
      expect(casaRooms, ['Entrada', 'Sala', 'Cocina', 'Baño', 'Cuarto', 'Garaje']);
    });

    test('todas las luces se encienden con V16', () {
      final out = <String>[];
      CasaSim(out.add).handle('V16:1');
      expect(out, ['V10:1', 'V11:1', 'V12:1', 'V13:1', 'V14:1', 'V15:1']);
    });

    test('armada y con la puerta principal abierta, suena al terminar el tiempo de gracia', () async {
      final out = <String>[];
      final sim = CasaSim(out.add, grace: const Duration(milliseconds: 50));
      sim.handle('V17:1');
      sim.handle('V1:1');
      expect(out, contains(startsWith('V18:Acceso detectado')));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(out, containsAll(['V9:1', 'V18:Alarma sonando: entrada abierta']));

      out.clear();
      sim.handle('V17:0');
      expect(out, containsAll(['V9:0', 'V17:0']));
    });

    test('si se cierra la puerta a tiempo, no suena', () async {
      final out = <String>[];
      final sim = CasaSim(out.add, grace: const Duration(milliseconds: 50));
      sim.handle('V17:1');
      sim.handle('V0:1');
      sim.handle('V0:0');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(out, contains('V18:Entradas cerradas'));
      expect(out, isNot(contains('V9:1')));
    });

    test('la app avisa cuando suena la sirena', () async {
      final d = SavedDevice(id: 'a', name: 'Casa', profile: Profile.casa, transport: Transport.demo);
      final s = Session(d, linkFor: (_) => DemoLink('casa', casaGrace: const Duration(milliseconds: 50)));
      await s.connect();
      s.send(CasaPins.armed, 1);
      s.send(CasaPins.garage, 1);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(s.lastAlert, 'Alarma sonando en Casa');
      expect(s.values[CasaPins.siren], '1');
      await s.disconnect();
    });
  });

  group('Clave de la casa', () {
    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

    test('la primera vez se crea, se guarda y la siguiente conexión entra sola', () async {
      final board = _Board();
      var saves = 0;
      final d = SavedDevice(id: 'k', name: 'Casa', profile: Profile.casa, transport: Transport.ble);
      final s = Session(d, linkFor: (_) => _SimLink(board), onDeviceChanged: () => saves++);

      await s.connect();
      await settle();
      expect(s.clave, ClaveState.create);
      expect(s.connected, isFalse);
      expect(s.needsClave, isTrue);

      s.createClave('482913');
      await settle();
      expect(s.connected, isTrue);
      expect(d.clave, '482913');
      expect(saves, 1);
      expect(s.log.map((l) => l.text), contains('SYNC'));
      expect(s.log.map((l) => l.text), isNot(contains(contains('482913'))), reason: 'la clave no se muestra');

      await s.disconnect();
      await s.connect();
      await settle();
      expect(s.connected, isTrue, reason: 'entrega sola la clave guardada');
      await s.disconnect();
    });

    test('clave incorrecta: avisa los intentos y después hace esperar', () async {
      final board = _Board()..sim.clave = '1234';
      final d = SavedDevice(id: 'w', name: 'Casa', profile: Profile.casa, transport: Transport.ble, clave: '9999');
      final s = Session(d, linkFor: (_) => _SimLink(board));

      await s.connect();
      await settle();
      expect(s.clave, ClaveState.ask);
      expect(s.claveMessage, 'Clave incorrecta. Quedan 2 intentos.');
      expect(d.clave, isNull, reason: 'olvida la clave que ya no sirve');

      s.enterClave('0000');
      await settle();
      expect(s.claveMessage, 'Clave incorrecta. Queda 1 intento.');
      s.enterClave('1111');
      await settle();
      expect(s.clave, ClaveState.locked);
      expect(s.claveMessage, 'Demasiados intentos. Espera 30 segundos.');
      await s.disconnect();
    });

    test('sin la clave, la placa no obedece', () {
      final out = <String>[];
      final sim = CasaSim(out.add, usesClave: true)..clave = '1234';
      sim.handle('V10:1');
      expect(out, ['AUTH:PIDE']);
      sim.handle('AUTH:1234');
      sim.handle('V10:1');
      expect(out, ['AUTH:PIDE', 'AUTH:OK', 'V10:1']);
    });

    test('cambiar la clave guarda la nueva', () async {
      final board = _Board()..sim.clave = '1234';
      final d = SavedDevice(id: 'c', name: 'Casa', profile: Profile.casa, transport: Transport.ble, clave: '1234');
      final s = Session(d, linkFor: (_) => _SimLink(board));
      await s.connect();
      await settle();
      expect(s.connected, isTrue);
      s.changeClave('5678');
      await settle();
      expect(board.sim.clave, '5678');
      expect(d.clave, '5678');
      expect(s.claveMessage, 'Clave cambiada');
      expect(s.claveChange, ClaveChange.done);
      expect(s.connected, isTrue);
      await s.disconnect();
    });

    test('cambiar la clave: si la placa no responde lo avisa, y si contesta tarde igual la guarda', () async {
      final board = _Board()..sim.clave = '1234';
      final d = SavedDevice(id: 'm', name: 'Casa', profile: Profile.casa, transport: Transport.ble, clave: '1234');
      final s = Session(d, linkFor: (_) => _MuteLink(board));
      await s.connect();
      await settle();
      s.changeClave('5678');
      expect(s.claveChange, ClaveChange.saving);
      await Future<void>.delayed(Session.changeTimeout + const Duration(milliseconds: 200));
      expect(s.claveChange, ClaveChange.failed);
      expect(s.claveChangeError, contains('no respondió'));
      expect(d.clave, '1234', reason: 'sin confirmación, este teléfono sigue con la de antes');

      board.link!.emitLine('AUTH:OK'); // la respuesta llega tarde
      await settle();
      expect(s.claveChange, ClaveChange.done);
      expect(d.clave, '5678');
      await s.disconnect();
    });

    test('cambiar la clave: si se corta la conexión o la placa la pide otra vez, lo avisa', () async {
      final board = _Board()..sim.clave = '1234';
      final d = SavedDevice(id: 'x', name: 'Casa', profile: Profile.casa, transport: Transport.ble, clave: '1234');
      final s = Session(d, linkFor: (_) => _MuteLink(board));
      await s.connect();
      await settle();
      s.changeClave('5678');
      await s.disconnect();
      expect(s.claveChange, ClaveChange.failed);
      expect(s.claveChangeError, contains('Se cortó'));
      expect(d.clave, '1234');

      await s.connect();
      await settle();
      s.changeClave('5678');
      board.link!.emitLine('AUTH:PIDE');
      await settle();
      expect(s.claveChange, ClaveChange.failed);
      expect(s.claveChangeError, contains('pidió'));
      await s.disconnect();
    });

    test('una placa que no contesta (el carrito) se usa sin clave', () async {
      final d = SavedDevice(id: 'n', name: 'Carro', profile: Profile.carro, transport: Transport.ble);
      final s = Session(d, linkFor: (_) => _SilentLink());
      await s.connect();
      expect(s.state, LinkState.connecting, reason: 'mientras espera la respuesta');
      await Future<void>.delayed(Session.claveTimeout + const Duration(milliseconds: 100));
      expect(s.connected, isTrue);
      expect(s.keyed, isFalse);
      await s.disconnect();
    });
  });

  group('Carrito', () {
    test('responde ERR a la clave como la placa real: queda conectado sin clave', () async {
      final d = SavedDevice(id: 'c', name: 'Carrito 4x4', profile: Profile.carro, transport: Transport.demo);
      final s = Session(d, linkFor: (_) => DemoLink('carro'));
      await s.connect();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(s.connected, isTrue);
      expect(s.keyed, isFalse);
      expect(invertedWheels(s), [false, false, false, false], reason: 'SYNC trae las ruedas invertidas');

      s.send(CarPins.invert, '0100');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(s.values[CarPins.invert], '0100');
      expect(invertedWheels(s), [false, true, false, false]);
      await s.disconnect();
    });

    /// Panel del carrito con una placa simulada que anota todo lo que recibe.
    Future<(AppState, Session, List<_RecLink>)> openPanel(WidgetTester t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(900, 420);
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      final links = <_RecLink>[];
      final app = AppState(linkFor: (_) => (links..add(_RecLink())).last);
      await app.load();
      final carro = app.devices.firstWhere((d) => d.profile == Profile.carro);
      final s = app.session(carro);
      await s.connect();
      await t.pumpWidget(ControlApp(state: app, home: CarroPanel(device: carro)));
      await t.pump(const Duration(milliseconds: 300));
      expect(s.connected, isTrue);
      return (app, s, links);
    }

    Future<void> close(WidgetTester t, Session s) async {
      await t.pumpWidget(const SizedBox());
      await s.disconnect();
      await t.pump(const Duration(seconds: 1));
    }

    int throttleSent(List<String> lines) =>
        lines.where((l) => l.startsWith('V${CarPins.throttle}:')).map((l) => int.parse(l.split(':')[1])).fold(0, (a, b) => a > b ? a : b);

    testWidgets('al reconectar no arranca solo con el acelerador que tenía antes del corte', (t) async {
      final (_, s, links) = await openPanel(t);
      expect(links.single.sent, containsAll(['V${CarPins.joystick}:0,0', 'V${CarPins.throttle}:0']),
          reason: 'al abrir el panel la placa recibe «quieto»');

      await t.drag(find.byType(Throttle), const Offset(0, -80));
      await t.pump(const Duration(milliseconds: 500));
      expect(throttleSent(links.single.sent), greaterThan(0), reason: 'el acelerador se movió');

      links.single.drop(); // el carrito sale de alcance
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<Throttle>(find.byType(Throttle)).value, 0, reason: 'el acelerador vuelve a cero al cortarse');

      await t.pump(Session.retryDelays.first + const Duration(milliseconds: 300)); // se reconecta solo
      // Cerrar la conexión vieja necesita una vuelta real del reloj (en el teléfono es inmediato).
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100)); // un segundo de repeticiones
      }
      expect(links.length, 2, reason: 'hubo reconexión');
      expect(s.connected, isTrue);
      expect(links.last.sent, contains('V${CarPins.throttle}:0'), reason: 'al reconectar, «quieto»');
      expect(throttleSent(links.last.sent), 0, reason: 'nunca vuelve a mandar el acelerador viejo');
      await close(t, s);
    });

    testWidgets('si la app pasa a segundo plano, el carrito frena y no se repiten órdenes', (t) async {
      final (_, s, links) = await openPanel(t);
      await t.drag(find.byType(Throttle), const Offset(0, -80));
      await t.pump(const Duration(milliseconds: 300));
      expect(throttleSent(links.single.sent), greaterThan(0));

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await t.pump();
      links.single.sent.clear();
      await t.pump(const Duration(seconds: 1));
      expect(throttleSent(links.single.sent), 0, reason: 'en segundo plano no repite el acelerador');
      expect(t.widget<Throttle>(find.byType(Throttle)).value, 0);

      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await close(t, s);
    });

    testWidgets('si el carrito pide clave (carro-0.4), el panel muestra la tarjeta para crearla', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(900, 420);
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      final app = AppState(linkFor: (_) => _ReplyLink('AUTH:NUEVA'));
      await app.load();
      final carro = app.devices.firstWhere((d) => d.profile == Profile.carro);
      final s = app.session(carro);
      await s.connect();
      await t.pumpWidget(ControlApp(state: app, home: CarroPanel(device: carro)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Crea la clave del carrito'), findsOneWidget);
      expect(find.byType(Throttle), findsNothing, reason: 'sin clave no se maneja');
      await t.pumpWidget(const SizedBox());
      await s.disconnect();
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('cuando la placa pone el seguro, la app suelta sus controles y le avisa «quieto»', (t) async {
      final (_, s, links) = await openPanel(t);
      await t.drag(find.byType(Throttle), const Offset(0, -80));
      await t.pump(const Duration(milliseconds: 300));
      expect(t.widget<Throttle>(find.byType(Throttle)).value, greaterThan(0));

      links.single.sent.clear();
      links.single.emitLine('ERR:suelta el joystick y el acelerador para volver a manejar');
      await t.pump();
      await t.pump();
      expect(t.widget<Throttle>(find.byType(Throttle)).value, 0, reason: 'hay que volver a acelerar a propósito');
      expect(links.single.sent, containsAll(['V${CarPins.joystick}:0,0', 'V${CarPins.throttle}:0']));
      await t.pump(const Duration(seconds: 1));
      expect(throttleSent(links.single.sent), 0, reason: 'no vuelve a mandar el acelerador viejo');
      await close(t, s);
    });

    testWidgets('la reversa y las luces se leen de la placa al entrar al panel', (t) async {
      final (_, s, links) = await openPanel(t);
      final reversa = find.bySemanticsLabel('Reversa');
      expect(t.getSemantics(reversa), isSemantics(isToggled: false));
      links.single.emitLine('V${CarPins.reverse}:1'); // la placa recuerda la reversa de antes
      await t.pump();
      await t.pump(); // la línea llega después del primer cuadro
      expect(t.getSemantics(reversa), isSemantics(isToggled: true), reason: 'el botón muestra la marcha atrás que recuerda la placa');

      await t.tap(find.bySemanticsLabel('Reversa'));
      await t.pump();
      expect(links.single.sent.last, 'V${CarPins.reverse}:0', reason: 'tocar Reversa la quita, no la vuelve a poner');
      await close(t, s);
    });
  });

  group('Casa: doble toque', () {
    /// Una casa conectada que no confirma nada todavía (como una placa lenta): las órdenes quedan «enviando».
    Future<(Session, _RecLink)> casa(WidgetTester t, Widget Function(Session) build) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(500, 900);
      addTearDown(t.view.reset);
      SharedPreferences.setMockInitialValues({});
      final links = <_RecLink>[];
      final app = AppState(linkFor: (_) => (links..add(_RecLink())).last);
      await app.load();
      final s = app.session(app.devices.firstWhere((d) => d.profile == Profile.casa));
      await s.connect();
      // Como en el panel de la casa: la tarjeta se redibuja con cada cambio de la sesión.
      await t.pumpWidget(ControlApp(
        state: app,
        home: Scaffold(body: SingleChildScrollView(child: ListenableBuilder(listenable: s, builder: (_, _) => build(s)))),
      ));
      await t.pump(const Duration(milliseconds: 300));
      expect(s.connected, isTrue);
      links.single.sent.clear();
      return (s, links.single);
    }

    int count(_RecLink l, int pin) => l.sent.where((x) => x.startsWith('V$pin:')).length;

    testWidgets('dos toques en Armar no arman y desarman', (t) async {
      final (s, link) = await casa(t, (s) => SecurityCard(session: s));
      final at = t.getCenter(find.text('ARMAR'));
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(find.text('DESARMAR'), findsOneWidget, reason: 'el botón ya cambió de texto');
      await t.tapAt(at); // el segundo toque cae en el mismo lugar, que ahora dice «Desarmar»
      await t.pump(const Duration(milliseconds: 100));
      expect(count(link, CasaPins.armed), 1);
      expect(s.values[CasaPins.armed], '1', reason: 'queda armada');
      await s.disconnect();
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('Sirena y en seguida «Apagar alarma» no apaga lo que se acaba de pedir', (t) async {
      final (s, link) = await casa(t, (s) => SecurityCard(session: s));
      final at = t.getCenter(find.text('SIRENA'));
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 100));
      await t.pump();
      expect(find.text('APAGAR ALARMA'), findsOneWidget, reason: '«Apagar alarma» ocupa ahora ese lugar');
      await t.tapAt(at);
      await t.pump(const Duration(milliseconds: 100));
      expect(count(link, CasaPins.siren), 1);
      expect(count(link, CasaPins.armed), 0);
      await s.disconnect();
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('dos toques en una luz no la prenden y apagan', (t) async {
      final spec = casaControls.firstWhere((c) => c.vpin == 12); // luz de la cocina
      final (s, link) = await casa(t, (s) => ControlTile(session: s, spec: spec, showPins: false));
      await t.tap(find.byType(ControlTile));
      await t.pump(const Duration(milliseconds: 100));
      await t.tap(find.byType(ControlTile));
      await t.pump(const Duration(milliseconds: 100));
      expect(count(link, 12), 1);
      expect(s.values[12], '1');

      // Cuando la placa confirma, el siguiente toque sí vale.
      link.emitLine('V12:1');
      await t.pump();
      await t.pump();
      await t.tap(find.byType(ControlTile));
      await t.pump(const Duration(milliseconds: 100));
      expect(count(link, 12), 2);
      expect(s.values[12], '0');
      await s.disconnect();
      await t.pump(const Duration(seconds: 3));
    });
  });

  testWidgets('la pantalla de inicio muestra las placas demo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.load();
    await tester.pumpWidget(ControlApp(state: state));
    expect(find.text('Dispositivos'), findsWidgets); // título grande y el de la barra
    expect(find.text('Casa (demo)'), findsOneWidget);
    expect(find.text('Auto Robot (demo)'), findsOneWidget);
    expect(find.text('Agregar dispositivo'), findsOneWidget, reason: 'un solo lugar para agregar, al final de la lista');
    expect(find.byTooltip('Agregar dispositivo'), findsNothing, reason: 'arriba solo queda Ajustes');
    expect(find.byTooltip('Ajustes'), findsOneWidget);
    expect(find.byIcon(Ic.chevronRight), findsNWidgets(2), reason: 'cada tarjeta muestra que se puede abrir');
    expect(find.text('Mantén presionada una tarjeta para ver sus opciones.'), findsOneWidget);
    expect(find.text('CONECTAR'), findsWidgets, reason: 'cada placa desconectada tiene su botón');
  });

  testWidgets('«Cambiar la clave» está en las opciones del dispositivo y espera a que la casa confirme', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 1400);
    addTearDown(t.view.reset);
    final board = _Board()..sim.clave = '1234';
    SharedPreferences.setMockInitialValues({});
    final app = AppState(linkFor: (d) => d.transport == Transport.demo ? DemoLink(d.profile.name) : _SimLink(board));
    await app.load();
    final casa = SavedDevice(id: 'k', name: 'Casa real', profile: Profile.casa, transport: Transport.ble, address: 'X', clave: '1234');
    await app.add(casa);
    await t.pumpWidget(ControlApp(state: app));
    await t.pump();

    Future<void> options(String name) async {
      await t.longPress(find.text(name));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> close() async {
      await t.tapAt(const Offset(400, 40)); // fuera de la hoja
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    // Una demo no tiene clave: no aparece.
    await options('Casa (demo)');
    expect(find.text('Cambiar la clave'), findsNothing);
    await close();

    // Desconectada: se ve, pero pide conectarse.
    await options('Casa real');
    expect(find.text('Cambiar la clave'), findsOneWidget);
    expect(find.text('Conéctate para cambiarla'), findsOneWidget);

    // Conectada y con la clave entregada: abre la hoja.
    final s = app.session(casa);
    await t.runAsync(() async {
      await s.connect();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pump();
    expect(s.connected, isTrue);
    expect(find.text('Los otros teléfonos tendrán que escribir la nueva'), findsOneWidget);
    await t.tap(find.text('Cambiar la clave'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    await t.enterText(find.byType(TextField), '5678');
    await t.pump();
    await t.tap(find.text('GUARDAR CLAVE NUEVA'));
    await t.pump();
    expect(find.text('GUARDANDO…'), findsOneWidget, reason: 'espera la respuesta antes de cerrar');
    // La respuesta de la casa simulada cruza entre el reloj de la prueba y el real: se dejan correr los dos.
    for (var i = 0; i < 5; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Clave cambiada'), findsOneWidget);
    expect(board.sim.clave, '5678');
    expect(casa.clave, '5678');

    await t.tap(find.text('LISTO'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Clave cambiada'), findsNothing);
    await t.runAsync(s.disconnect);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('el nombre de un dispositivo se cambia desde sus opciones y queda guardado', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 1400);
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();
    await t.pumpWidget(ControlApp(state: app));
    await t.pump();

    await t.longPress(find.text('Casa (demo)'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('Cambiar nombre'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    await t.enterText(find.byType(TextField), 'Maqueta del grupo');
    await t.pump();
    await t.tap(find.text('GUARDAR NOMBRE'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    expect(find.text('Maqueta del grupo'), findsOneWidget);
    expect(find.text('Casa (demo)'), findsNothing);
    final again = AppState();
    await again.load();
    expect(again.devices.map((d) => d.name), contains('Maqueta del grupo'));
  });

  testWidgets('la tarjeta de seguridad avisa si la puerta principal está abierta antes de armar', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(800, 1400);
    addTearDown(t.view.reset);
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();
    final casa = app.devices.firstWhere((d) => d.profile == Profile.casa);
    final s = app.session(casa);
    await t.runAsync(() async {
      await s.connect();
      s.send(CasaPins.mainDoor, 1);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pumpWidget(ControlApp(state: app, home: Scaffold(body: ListenableBuilder(listenable: s, builder: (_, _) => SecurityCard(session: s)))));
    await t.pump();
    expect(find.text('La puerta principal está abierta. Si la armas así, la sirena suena en 20 s.'), findsOneWidget);

    await t.runAsync(() async {
      s.send(CasaPins.mainDoor, 0);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump();
    expect(find.text('Ármala para vigilar el garaje y la puerta principal.'), findsOneWidget);

    // Armar y desarmar: la placa avisa «Seguridad desarmada», que solo repite el título y no se muestra.
    await t.runAsync(() async {
      s.send(CasaPins.armed, 1);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      s.send(CasaPins.armed, 0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pump();
    expect(s.values[CasaPins.notice], 'Seguridad desarmada');
    expect(find.text('Seguridad desarmada'), findsNothing);
    expect(find.text('Ármala para vigilar el garaje y la puerta principal.'), findsOneWidget);
    await t.runAsync(s.disconnect);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('tres toques al logo en «Acerca de» abren la firma', (tester) async {
    // Ancho como el de siempre (la letra de prueba es más ancha que D-DIN), pero alto como un teléfono.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final state = AppState();
    await state.load();
    await tester.pumpWidget(ControlApp(state: state));
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Acerca de'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final logo = find.byKey(const ValueKey('logo-acerca'));
    await tester.tap(logo);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(logo);
    await tester.pump(const Duration(milliseconds: 200));
    Finder name(String full) {
      final cut = full.lastIndexOf(' ');
      return find.text('${full.substring(0, cut).toUpperCase()}  ${full.substring(cut + 1).toUpperCase()}', findRichText: true);
    }

    expect(name('Samuel Esteves'), findsNothing, reason: 'dos toques no bastan');
    expect(find.textContaining('Samuel'), findsNothing, reason: 'los nombres solo están en el guiño escondido');

    await tester.tap(logo);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    for (final n in Credits.team) {
      expect(name(n), findsOneWidget);
    }
    expect(Credits.team, [...Credits.team]..sort(), reason: 'en orden alfabético: nadie va primero');

    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(name('Samuel Esteves'), findsNothing, reason: 'un toque cierra los créditos');
    expect(find.text('Control Domótica'), findsWidgets, reason: 'vuelve a «Acerca de»');
  });
}

/// Placa simulada que anota cada línea recibida y contesta al latido.
class _RecLink extends _FlakyLink {
  final sent = <String>[];

  @override
  Future<void> sendLine(String line) async {
    sent.add(line);
    if (line == 'PING') emitLine('PONG');
    await super.sendLine(line);
  }
}

/// Conexión de prueba que se puede tumbar a mano.
class _FlakyLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  /// Como el programa anterior del ESP32: no conoce la clave.
  @override
  Future<void> sendLine(String line) async {
    if (line.startsWith('AUTH')) emitLine('ERR:no entiendo $line');
  }

  void drop() => setState(LinkState.error, 'caída simulada');
}

/// Una casa simulada que pide clave. Recuerda la clave entre conexiones, como el ESP32.
class _Board {
  _SimLink? link;
  late final CasaSim sim = CasaSim((l) => link?.emitLine(l), usesClave: true);
}

/// Conexión con la casa simulada: lo que responde la casa llega a la conexión abierta.
class _SimLink extends DeviceLink {
  final _Board board;
  _SimLink(this.board);

  @override
  Future<void> connect() async {
    board.link = this;
    board.sim.reconnect();
    setState(LinkState.connected);
  }

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {
    await Future<void>.delayed(Duration.zero);
    board.sim.handle(line);
  }
}

/// La casa simulada, pero la respuesta a CLAVE se pierde (la prueba la envía a mano cuando quiere).
class _MuteLink extends _SimLink {
  _MuteLink(super.board);

  @override
  Future<void> sendLine(String line) async {
    if (line.startsWith('CLAVE:')) return;
    await super.sendLine(line);
  }
}

/// Una placa apagada: cada intento de conectar falla.
class _DeadLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.error, 'no responde');

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {}
}

/// Placa que contesta a AUTH con [reply] (y a PING con PONG), opcionalmente con retraso.
class _ReplyLink extends DeviceLink {
  final String reply;
  final Duration delay;
  _ReplyLink(this.reply, {this.delay = Duration.zero});

  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {
    if (line == 'PING') emitLine('PONG');
    if (line.startsWith('AUTH')) Future<void>.delayed(delay, () => emitLine(reply));
  }
}

/// Tarda en conectar, y se puede cancelar mientras tanto (como el Bluetooth).
class _SlowLink extends DeviceLink {
  bool _closing = false;

  @override
  Future<void> connect() async {
    setState(LinkState.connecting);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (_closing) return setState(LinkState.disconnected);
    setState(LinkState.connected);
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
    setState(LinkState.disconnected);
  }

  @override
  Future<void> sendLine(String line) async {}
}

/// Una placa que nunca contesta, como un módulo HM-10 con otro programa.
class _SilentLink extends DeviceLink {
  @override
  Future<void> connect() async => setState(LinkState.connected);

  @override
  Future<void> disconnect() async => setState(LinkState.disconnected);

  @override
  Future<void> sendLine(String line) async {}
}

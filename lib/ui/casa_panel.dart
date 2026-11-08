import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/controls.dart';
import '../models/device.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';

class CasaPanel extends StatefulWidget {
  final SavedDevice device;
  const CasaPanel({super.key, required this.device});

  @override
  State<CasaPanel> createState() => _CasaPanelState();
}

class _CasaPanelState extends State<CasaPanel> {
  final _lcd = TextEditingController(text: 'Bienvenidos');
  double? _window; // valor local mientras se arrastra
  Timer? _windowTimer;
  String? _shownAlert;

  @override
  void dispose() {
    _lcd.dispose();
    _windowTimer?.cancel();
    super.dispose();
  }

  ControlSpec _spec(int vpin) => casaControls.firstWhere((c) => c.vpin == vpin);

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session(widget.device);
    _maybeAlert(s);
    final v = s.values;
    final lights = casaControls.where((c) => c.kind == ControlKind.toggle).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (k) {
              if (k == 'test') s.sendRaw('TEST');
              if (k == 'off') s.disconnect();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'test', child: Text('Probar salidas una por una')),
              PopupMenuItem(value: 'off', child: Text('Desconectar')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          ConnectionBar(session: s),
          const SizedBox(height: 12),
          _alarm(s),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
            children: [for (final c in lights) _toggleTile(s, c)],
          ),
          const SizedBox(height: 10),
          _door(s),
          const SizedBox(height: 10),
          _windowCard(s),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _reading(s, _spec(10), v[10] == null ? '—' : '${v[10]!.replaceAll('.', ',')} °C')),
            const SizedBox(width: 10),
            Expanded(child: _reading(s, _spec(11), v[11] == '1' ? 'Detectado' : 'Sin movimiento', alert: v[11] == '1')),
          ]),
          const SizedBox(height: 10),
          _lcdCard(s),
          const SizedBox(height: 10),
          _bell(s),
          const SizedBox(height: 12),
          MessageConsole(session: s),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Text('Mantén presionado un control para cambiar su pin o invertirlo.', style: TextStyle(color: C.ink2, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  void _maybeAlert(Session s) {
    final a = s.lastAlert;
    if (a == null) {
      _shownAlert = null;
      return;
    }
    if (a == _shownAlert) return;
    _shownAlert = a;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    });
  }

  // ---------- Alarma ----------
  Widget _alarm(Session s) {
    final armed = s.values[7] == '1';
    final fired = s.values[7]?.toUpperCase().startsWith('DISPARO') ?? false;
    final bg = fired ? C.danger : (armed ? C.night : C.card);
    final fg = fired || armed ? Colors.white : C.ink;
    return Panel(
      color: bg,
      child: Row(children: [
        Icon(fired ? Icons.warning_amber_rounded : Icons.shield_outlined, color: fg),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Alarma de seguridad', style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .7))),
            Text(fired ? '¡Movimiento detectado!' : (armed ? 'Armada · vigilando' : 'Desarmada'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 40),
            backgroundColor: armed || fired ? Colors.white : C.accent,
            foregroundColor: armed || fired ? C.ink : Colors.white,
          ),
          onPressed: s.connected
              ? () {
                  HapticFeedback.mediumImpact();
                  s.clearAlert();
                  s.send(7, armed || fired ? 0 : 1);
                }
              : null,
          child: Text(fired ? 'Apagar' : (armed ? 'Desarmar' : 'Armar')),
        ),
      ]),
    );
  }

  // ---------- Luces y switches ----------
  Widget _toggleTile(Session s, ControlSpec c) {
    final on = s.values[c.vpin] == '1';
    return Panel(
      onTap: s.connected ? () => _toggle(s, c, !on) : null,
      onLongPress: () => showPinSheet(context, s, c),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: on ? const Color(0xFFFFF3C4) : C.fill,
              borderRadius: BorderRadius.circular(11),
              boxShadow: on ? [const BoxShadow(color: Color(0x88FFC400), blurRadius: 16)] : null,
            ),
            child: Icon(c.icon, size: 19, color: on ? const Color(0xFF7A6100) : C.ink2),
          ),
          CupertinoSwitch(value: on, activeTrackColor: C.ok, onChanged: s.connected ? (x) => _toggle(s, c, x) : null),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 3),
          PinTag(pinLabel(s.device, c)),
        ]),
      ]),
    );
  }

  void _toggle(Session s, ControlSpec c, bool on) {
    HapticFeedback.selectionClick();
    s.send(c.vpin, on ? 1 : 0);
  }

  // ---------- Puerta ----------
  Widget _door(Session s) {
    final c = _spec(3);
    final open = (int.tryParse(s.values[3] ?? '0') ?? 0) > 0;
    return Panel(
      onLongPress: () => showPinSheet(context, s, c),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: C.fill, borderRadius: BorderRadius.circular(12)),
          child: AnimatedRotation(
            turns: open ? -0.08 : 0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: Icon(open ? Icons.door_front_door : c.icon, color: C.accent),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 2),
            Row(children: [
              Text(open ? 'Abierta · ${c.openValue}°' : 'Cerrada · 0°', style: const TextStyle(color: C.ink2, fontSize: 13)),
              const SizedBox(width: 6),
              PinTag(pinLabel(s.device, c)),
            ]),
          ]),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size(84, 40)),
          onPressed: s.connected
              ? () {
                  HapticFeedback.mediumImpact();
                  s.send(3, open ? 0 : c.openValue);
                }
              : null,
          child: Text(open ? 'Cerrar' : 'Abrir'),
        ),
      ]),
    );
  }

  // ---------- Ventana ----------
  Widget _windowCard(Session s) {
    final c = _spec(4);
    final value = _window ?? (double.tryParse(s.values[4] ?? '0') ?? 0);
    return Panel(
      onLongPress: () => showPinSheet(context, s, c),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(children: [
        Row(children: [
          Icon(c.icon, color: C.ink2, size: 20),
          const SizedBox(width: 8),
          Text(c.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(width: 8),
          PinTag(pinLabel(s.device, c)),
          const Spacer(),
          Text('${value.round()}°', style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
        ]),
        Slider(
          value: value.clamp(c.min.toDouble(), c.max.toDouble()),
          min: c.min.toDouble(),
          max: c.max.toDouble(),
          onChanged: s.connected
              ? (x) {
                  setState(() => _window = x);
                  // No saturar la placa: como mucho un mensaje cada 120 ms.
                  if (_windowTimer?.isActive ?? false) return;
                  _windowTimer = Timer(const Duration(milliseconds: 120), () => s.send(4, _window!.round(), quiet: true));
                }
              : null,
          onChangeEnd: (x) {
            _windowTimer?.cancel();
            s.send(4, x.round());
            setState(() => _window = null);
          },
        ),
      ]),
    );
  }

  // ---------- Lecturas ----------
  Widget _reading(Session s, ControlSpec c, String text, {bool alert = false}) {
    return Panel(
      onLongPress: c.gpio != null ? () => showPinSheet(context, s, c) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(c.icon, size: 18, color: alert ? C.danger : C.ink2),
          const SizedBox(width: 6),
          Text(c.label, style: const TextStyle(fontSize: 12.5, color: C.ink2)),
        ]),
        const SizedBox(height: 6),
        Text(text, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: alert ? C.danger : C.ink)),
        const SizedBox(height: 4),
        PinTag('${pinLabel(s.device, c)} ← placa'),
      ]),
    );
  }

  // ---------- Pantalla LCD ----------
  Widget _lcdCard(Session s) {
    final ack = s.values[6] == 'OK';
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.tv_outlined, size: 20, color: C.ink2),
          const SizedBox(width: 8),
          const Text('Pantalla LCD', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(width: 8),
          const PinTag('V6'),
          const Spacer(),
          if (ack) const Text('Recibido ✓', style: TextStyle(color: C.ok, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _lcd,
              maxLength: 32,
              style: const TextStyle(fontFamily: 'monospace', color: Color(0xFFB8FF7A)),
              decoration: InputDecoration(
                counterText: '',
                fillColor: const Color(0xFF1F3B18),
                hintText: 'Texto para la pantalla',
                hintStyle: TextStyle(color: const Color(0xFFB8FF7A).withValues(alpha: .5)),
              ),
              onSubmitted: s.connected ? (_) => _sendLcd(s) : null,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: s.connected ? () => _sendLcd(s) : null,
            child: const Text('Enviar'),
          ),
        ]),
      ]),
    );
  }

  void _sendLcd(Session s) {
    s.values.remove(6);
    s.send(6, _lcd.text.trim(), remember: false);
    FocusScope.of(context).unfocus();
  }

  // ---------- Timbre ----------
  Widget _bell(Session s) {
    final c = _spec(5);
    return Panel(
      onLongPress: () => showPinSheet(context, s, c),
      child: Row(children: [
        Icon(c.icon, color: C.ink2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Timbre / sonido', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 3),
            PinTag(pinLabel(s.device, c)),
          ]),
        ),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size(84, 40)),
          onPressed: s.connected
              ? () {
                  HapticFeedback.mediumImpact();
                  s.send(5, 1, remember: false);
                }
              : null,
          child: const Text('Sonar'),
        ),
      ]),
    );
  }
}

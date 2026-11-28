import 'package:flutter/material.dart';

import '../../core/board_update.dart';
import '../../core/firmware.dart';
import '../../main.dart';
import '../../models/device.dart';
import '../theme.dart';
import 'kit.dart';

/// Hoja para instalar en una placa la versión nueva de su programa, por Wi-Fi (ver lib/core/board_update.dart).
/// Si ya hay una actualización en curso, la muestra: cerrar la hoja no la detiene.
Future<void> showBoardUpdateSheet(BuildContext context, SavedDevice device) =>
    showAppSheet<void>(context, (_) => _BoardUpdateSheet(device: device));

class _BoardUpdateSheet extends StatelessWidget {
  final SavedDevice device;
  const _BoardUpdateSheet({required this.device});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final job = app.boardJob(device);
    final release = job?.release ?? app.boardUpdate(device);
    final c = context.c;

    if (release == null) {
      if (device.firmware == null) {
        return _Frame(
          eyebrow: device.name,
          title: 'Versión anterior',
          detail: 'Esta placa no dice su versión: tiene un programa anterior a casa-0.9 o carro-0.5. Esa primera vez se '
              'instala por cable, desde la página del instalador.',
        );
      }
      if (!app.boardsKnown) {
        return _Frame(
          eyebrow: device.name,
          title: 'Sin revisar',
          detail: 'Tiene ${device.firmware}. Para saber si hay una versión nueva hace falta internet una vez: si el '
              'teléfono está en la red de la placa, cámbialo a tu Wi-Fi o a datos.',
          children: [
            PillButton(app.checkingBoards ? 'Revisando…' : 'Revisar ahora',
                icon: Ic.sync, expand: true, onTap: app.checkingBoards ? null : app.checkBoards),
          ],
        );
      }
      return _Frame(eyebrow: device.name, title: 'Ya está al día', detail: 'Tiene ${device.firmware}, la más nueva.');
    }

    final step = job?.step ?? BoardUpdateStep.ready;
    final pct = '${((job?.progress ?? 0) * 100).round()} %';
    final net = device.transport == Transport.wifi ? (device.ssid ?? 'la red de la placa') : BoardUpdate.boardSsid(device.profile);
    final askAgain = device.transport == Transport.wifi ? ' Si Android pregunta por «$net», toca «Conectar».' : '';
    final (title, detail) = switch (step) {
      BoardUpdateStep.ready => (
          release.version,
          'Hay una versión nueva para «${device.name}» (tiene ${device.firmware}). Se instala por Wi-Fi en menos de un '
              'minuto, y la clave y los ajustes se conservan.'
        ),
      BoardUpdateStep.downloading => ('Bajando ${release.version}', 'Descargando… $pct de ${release.sizeText}'),
      BoardUpdateStep.connecting => (
          'Conectando con la placa',
          'La app se une a la red «$net». Si Android pregunta, toca «Conectar».'
        ),
      BoardUpdateStep.sending => ('Enviando · $pct', 'La placa guarda la versión nueva aparte y sigue funcionando mientras tanto.'),
      BoardUpdateStep.restarting => ('La placa se reinicia', 'Comprobando que arrancó con ${release.version}…$askAgain'),
      BoardUpdateStep.installed => (
          'Instalada',
          'La placa recibió ${release.version} completa y revisada, y se reinició. Falta que vuelva a conectarse para '
              'comprobarla: conéctate a «${device.name}» y esto se actualiza solo.'
        ),
      BoardUpdateStep.done => ('Listo', '«${device.name}» ya tiene ${release.version}.'),
      BoardUpdateStep.failed => ('No se pudo actualizar', job?.error ?? 'Algo salió mal. La placa sigue con su versión.'),
    };
    final working = job?.busy ?? false;
    final measured = step == BoardUpdateStep.downloading || step == BoardUpdateStep.sending;

    return _Frame(
      eyebrow: 'Programa de la placa · ${device.name}',
      title: title,
      detail: detail,
      children: [
        if (working)
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: measured ? job!.progress : null,
              minHeight: 6,
              color: c.text,
              backgroundColor: c.surface2,
            ),
          ),
        if (working) ...[
          const SizedBox(height: 14),
          Text('Quédate cerca de la placa con la app abierta. Si se corta, la placa sigue con su versión.',
              style: T.small.copyWith(color: c.text3), textAlign: TextAlign.center),
        ],
        if (step == BoardUpdateStep.ready) ...[
          PillButton('Instalar · ${release.sizeText}', icon: Ic.download, expand: true, onTap: () => app.updateBoard(device, release)),
          const SizedBox(height: 14),
          Text('La app se une un momento a la red «$net» de la placa y después vuelve a tu Wi-Fi.',
              style: T.small.copyWith(color: c.text3), textAlign: TextAlign.center),
        ],
        if (step == BoardUpdateStep.done) PillButton('Listo', icon: Ic.check, expand: true, onTap: () => Navigator.pop(context)),
        if (step == BoardUpdateStep.installed) PillButton('Cerrar', kind: PillKind.secondary, expand: true, onTap: () => Navigator.pop(context)),
        if (step == BoardUpdateStep.failed) ...[
          PillButton('Intentar otra vez', expand: true, onTap: () => app.updateBoard(device, release)),
          const SizedBox(height: 10),
          PillButton('Cerrar', kind: PillKind.secondary, expand: true, onTap: () => Navigator.pop(context)),
        ],
      ],
    );
  }
}

class _Frame extends StatelessWidget {
  final String eyebrow, title, detail;
  final List<Widget> children;
  const _Frame({required this.eyebrow, required this.title, required this.detail, this.children = const []});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SheetHeader(eyebrow: eyebrow, title: title, detail: detail),
        ),
        if (children.isNotEmpty) const SizedBox(height: 18),
        ...children,
      ]),
    );
  }
}

/// Aviso en el inicio: una placa tiene una versión nueva (o se está actualizando). Un toque abre la hoja.
class BoardUpdateBanner extends StatelessWidget {
  final SavedDevice device;
  final BoardRelease release;
  const BoardUpdateBanner({super.key, required this.device, required this.release});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final job = AppScope.of(context).boardJob(device);
    final (eyebrow, color, line) = switch (job?.step) {
      _ when job != null && job.busy => ('Actualizando', c.amber, '${device.name} · ${(job.progress * 100).round()} %'),
      BoardUpdateStep.installed => ('Instalada en ${device.name}', c.green, '${release.version} · falta comprobarla al conectarse'),
      BoardUpdateStep.failed => ('No se pudo actualizar ${device.name}', c.red, '${release.version} · toca para ver qué pasó'),
      _ => ('Versión nueva para ${device.name}', c.green, '${release.version} · toca para instalar'),
    };
    return Tap(
      onTap: () => showBoardUpdateSheet(context, device),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(children: [
          Icon(Ic.board, size: 24, color: c.text),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow(eyebrow, color: color),
              const SizedBox(height: 4),
              Text(line, style: T.callout, maxLines: 2),
            ]),
          ),
          Icon(Ic.chevronRight, size: 18, color: c.text3),
        ]),
      ),
    );
  }
}

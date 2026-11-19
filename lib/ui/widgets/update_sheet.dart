import 'package:flutter/material.dart';

import '../../core/updater.dart';
import '../../main.dart';
import '../../version.dart';
import '../theme.dart';
import 'kit.dart';

/// Hoja para actualizar la app: busca en GitHub, descarga el APK y abre el instalador de Android.
/// Si ya se sabe que hay una versión nueva ([release]), empieza mostrándola.
Future<void> showUpdateSheet(BuildContext context, {AppRelease? release}) =>
    showAppSheet<void>(context, (_) => _UpdateSheet(release: release));

enum _Step { checking, upToDate, available, downloading, permission, installing, failed }

class _UpdateSheet extends StatefulWidget {
  final AppRelease? release;
  const _UpdateSheet({this.release});

  @override
  State<_UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<_UpdateSheet> with WidgetsBindingObserver {
  _Step _step = _Step.checking;
  AppRelease? _release;
  double _progress = 0;
  String? _error;
  String? _apk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final r = widget.release;
    if (r != null) {
      _release = r;
      _step = _Step.available;
    } else {
      _check();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver del ajuste de Android («Permitir de esta fuente»), se sigue solo con la instalación.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == _Step.permission) _install();
  }

  Future<void> _check() async {
    setState(() {
      _step = _Step.checking;
      _error = null;
    });
    try {
      final r = await Updater.check();
      if (!mounted) return;
      AppScope.read(context).setUpdate(r);
      setState(() {
        _release = r;
        _step = r == null ? _Step.upToDate : _Step.available;
      });
    } on UpdateProblem catch (e) {
      if (mounted) setState(() => _fail(e.message));
    }
  }

  Future<void> _download() async {
    final r = _release;
    if (r == null) return;
    setState(() {
      _step = _Step.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      _apk = await Updater.download(r, (p) {
        // Se redibuja de a 1 %: no hace falta por cada pedacito que llega.
        if (mounted && (p - _progress >= 0.01 || p == 1)) setState(() => _progress = p);
      });
      await _install();
    } on UpdateProblem catch (e) {
      if (mounted) setState(() => _fail(e.message));
    }
  }

  Future<void> _install() async {
    final apk = _apk;
    if (apk == null) return;
    if (!await Updater.canInstall()) {
      if (mounted) setState(() => _step = _Step.permission);
      return;
    }
    if (!mounted) return;
    setState(() => _step = _Step.installing);
    try {
      await Updater.install(apk);
    } on UpdateProblem catch (e) {
      if (mounted) setState(() => _fail(e.message));
    }
  }

  void _fail(String message) {
    _step = _Step.failed;
    _error = message;
  }

  void _retry() {
    if (_release == null) {
      _check();
    } else if (_apk != null) {
      _install();
    } else {
      _download();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = _release;
    final (title, detail) = switch (_step) {
      _Step.checking => ('Buscando actualización', 'Revisando en GitHub…'),
      _Step.upToDate => ('Ya está al día', 'Tienes la versión más nueva: $appVersion.'),
      _Step.available => (r!.title, 'Hay una versión nueva. Tienes $appVersion.'),
      _Step.downloading => (r!.title, 'Descargando… ${(_progress * 100).round()} % de ${r.sizeText}'),
      _Step.permission => (
          'Falta un permiso',
          'Android pide permitir, una sola vez, que Control Domótica instale sus actualizaciones. '
              'Activa «Permitir de esta fuente» y vuelve: la instalación sigue sola.'
        ),
      _Step.installing => (
          'Instalando',
          'Toca «Actualizar» o «Instalar» en la ventana de Android. La app se cierra y queda actualizada; '
              'tus dispositivos guardados se conservan.'
        ),
      _Step.failed => ('No se pudo actualizar', _error ?? 'Algo salió mal.'),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SheetHeader(eyebrow: 'Actualizaciones', title: title, detail: detail),
        ),
        const SizedBox(height: 18),
        if (_step == _Step.checking || _step == _Step.downloading)
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _step == _Step.downloading ? _progress : null,
              minHeight: 6,
              color: c.text,
              backgroundColor: c.surface2,
            ),
          ),
        if (_step == _Step.available && r != null) ...[
          if (r.notes.isNotEmpty)
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Eyebrow('Qué trae'),
                const SizedBox(height: 8),
                Text(r.notes, style: T.small.copyWith(color: c.text2), maxLines: 14, overflow: TextOverflow.fade),
              ]),
            ),
          const SizedBox(height: 16),
          if (r.apkUrl == null)
            Text('Esta versión no trae un APK para el procesador de este teléfono. Pide el APK universal.',
                style: T.small.copyWith(color: c.amber))
          else
            PillButton('Descargar e instalar · ${r.sizeText}', icon: Ic.download, expand: true, onTap: _download),
        ],
        if (_step == _Step.permission) ...[
          PillButton('Dar permiso', expand: true, onTap: Updater.openInstallPermission),
          const SizedBox(height: 10),
          PillButton('Ya lo activé', kind: PillKind.secondary, expand: true, onTap: _install),
        ],
        if (_step == _Step.installing)
          PillButton('Abrir el instalador otra vez', kind: PillKind.secondary, expand: true, onTap: _install),
        if (_step == _Step.failed) PillButton('Intentar otra vez', expand: true, onTap: _retry),
        if (_step == _Step.upToDate) PillButton('Buscar otra vez', kind: PillKind.secondary, expand: true, onTap: _check),
        const SizedBox(height: 14),
        Text('Las versiones se publican en github.com/${Updater.repo}', style: T.small.copyWith(color: c.text3), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// Aviso en el inicio cuando hay una versión nueva. Un toque abre la hoja para actualizar.
class UpdateBanner extends StatelessWidget {
  final AppRelease release;
  const UpdateBanner({super.key, required this.release});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: () => showUpdateSheet(context, release: release),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(children: [
          Icon(Ic.download, size: 24, color: c.text),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Eyebrow('Versión nueva', color: c.green),
              const SizedBox(height: 4),
              Text('${release.title} · toca para actualizar', style: T.callout, maxLines: 2),
            ]),
          ),
          Icon(Ic.chevronRight, size: 18, color: c.text3),
        ]),
      ),
    );
  }
}

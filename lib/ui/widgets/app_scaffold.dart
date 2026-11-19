import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'kit.dart';

/// Pantalla con título grande que, al bajar, queda como una barra fina con el título pequeño.
/// Debajo del título puede ir una etiqueta ([eyebrow]) y una línea de estado ([subtitle]).
class AppScaffold extends StatefulWidget {
  final String? eyebrow;
  final String title;
  final Widget? subtitle;
  final List<Widget> actions;
  final List<Widget> slivers;

  /// Barra fija abajo (el micrófono, «Guardar»...).
  final Widget? bottomBar;

  /// Logo de la app arriba a la izquierda (solo en la pantalla de inicio).
  final Widget? brand;

  const AppScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    this.bottomBar,
    this.brand,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  static const _barHeight = 58.0;
  final _scroll = ScrollController();
  double _collapse = 0; // 0 = título grande, 1 = barra compacta

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final v = ((_scroll.offset - 20) / 40).clamp(0.0, 1.0);
      if ((v - _collapse).abs() > 0.01) setState(() => _collapse = v);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pad = MediaQuery.paddingOf(context);
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final overlay = (c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: c.bg);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: c.bg,
        body: Stack(children: [
          CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: pad.top + _barHeight)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
                sliver: SliverToBoxAdapter(
                  child: Opacity(
                    opacity: 1 - _collapse * 0.85,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (widget.eyebrow != null) ...[Eyebrow(widget.eyebrow!), const SizedBox(height: 10)],
                      Text(widget.title, style: T.display),
                      if (widget.subtitle != null) ...[const SizedBox(height: 12), widget.subtitle!],
                    ]),
                  ),
                ),
              ),
              ...widget.slivers,
              SliverToBoxAdapter(child: SizedBox(height: pad.bottom + (widget.bottomBar == null ? 36 : 120))),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: pad.top + _barHeight,
              padding: EdgeInsets.fromLTRB(14, pad.top, 14, 0),
              decoration: BoxDecoration(
                color: c.bg.withValues(alpha: _collapse),
                border: Border(bottom: BorderSide(color: c.line.withValues(alpha: _collapse))),
              ),
              child: Row(children: [
                if (widget.brand != null)
                  Expanded(child: Align(alignment: Alignment.centerLeft, child: widget.brand))
                else ...[
                  SizedBox(
                    width: 100,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: canPop ? RoundButton(icon: Ic.back, tooltip: 'Volver', size: 40, onTap: () => Navigator.of(context).maybePop()) : null,
                    ),
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: _collapse,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(widget.title.toUpperCase(), textAlign: TextAlign.center, style: T.button.copyWith(color: c.text), maxLines: 1),
                      ),
                    ),
                  ),
                ],
                SizedBox(
                  width: 100,
                  child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    for (final (i, a) in widget.actions.indexed) ...[if (i > 0) const SizedBox(width: 8), a],
                  ]),
                ),
              ]),
            ),
          ),
          if (widget.bottomBar != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(16, 12, 16, pad.bottom + 12),
                decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.line))),
                child: widget.bottomBar,
              ),
            ),
        ]),
      ),
    );
  }
}

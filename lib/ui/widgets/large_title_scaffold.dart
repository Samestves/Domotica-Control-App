import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'glass.dart';

/// Pantalla al estilo iOS: título grande que, al bajar, se convierte en una barra de vidrio
/// con el título pequeño. Debajo va el fondo «de pantalla».
class LargeTitleScaffold extends StatefulWidget {
  final String title;
  final Widget? subtitle;
  final List<Widget> actions;
  final List<Widget> slivers;

  /// Barra fija abajo (por ejemplo, el botón «Guardar»). Se dibuja sobre vidrio desenfocado.
  final Widget? bottomBar;

  const LargeTitleScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.actions = const [],
    this.bottomBar,
  });

  @override
  State<LargeTitleScaffold> createState() => _LargeTitleScaffoldState();
}

class _LargeTitleScaffoldState extends State<LargeTitleScaffold> {
  static const _barHeight = 52.0;
  final _scroll = ScrollController();
  double _collapse = 0; // 0 = título grande visible, 1 = barra compacta

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final c = (_scroll.offset / 44).clamp(0.0, 1.0);
      if ((c - _collapse).abs() > 0.01) setState(() => _collapse = c);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    // Por pantalla, no por navegador: una hoja abierta encima no debe mostrar «volver» aquí.
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(children: [
          const Positioned.fill(child: Wallpaper()),
          CustomScrollView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: pad.top + _barHeight)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                sliver: SliverToBoxAdapter(
                  child: Opacity(
                    opacity: 1 - _collapse * 0.9,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.title, style: T.largeTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (widget.subtitle != null) ...[const SizedBox(height: 8), widget.subtitle!],
                    ]),
                  ),
                ),
              ),
              ...widget.slivers,
              SliverToBoxAdapter(child: SizedBox(height: pad.bottom + (widget.bottomBar == null ? 32 : 110))),
            ],
          ),
          Positioned(top: 0, left: 0, right: 0, child: _TopBar(
            height: pad.top + _barHeight,
            topPadding: pad.top,
            collapse: _collapse,
            title: widget.title,
            leading: canPop
                ? GlassIconButton(icon: Icons.arrow_back_ios_new_rounded, tooltip: 'Volver', onTap: () => Navigator.of(context).maybePop())
                : null,
            actions: widget.actions,
          )),
          if (widget.bottomBar != null)
            Positioned(left: 0, right: 0, bottom: 0, child: _BottomBar(bottomPadding: pad.bottom, child: widget.bottomBar!)),
        ]),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final double height, topPadding, collapse;
  final String title;
  final Widget? leading;
  final List<Widget> actions;
  const _TopBar({required this.height, required this.topPadding, required this.collapse, required this.title, required this.leading, required this.actions});

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: height,
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, 0),
      decoration: BoxDecoration(
        color: Color.fromRGBO(246, 248, 251, 0.72 * collapse),
        border: Border(bottom: BorderSide(color: C.separator.withValues(alpha: 0.12 * collapse), width: 0.6)),
      ),
      child: Row(children: [
        SizedBox(width: 44, child: leading),
        Expanded(
          child: Opacity(
            opacity: collapse,
            child: Text(title, textAlign: TextAlign.center, style: T.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        SizedBox(
          width: 96,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            for (final (i, a) in actions.indexed) ...[if (i > 0) const SizedBox(width: 8), a],
          ]),
        ),
      ]),
    );
    if (collapse <= 0) return bar;
    return ClipRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 24 * collapse, sigmaY: 24 * collapse), child: bar),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final double bottomPadding;
  final Widget child;
  const _BottomBar({required this.bottomPadding, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPadding + 12),
          decoration: const BoxDecoration(
            color: Color(0xB8F6F8FB),
            border: Border(top: BorderSide(color: C.separator, width: 0.6)),
          ),
          child: child,
        ),
      ),
    );
  }
}

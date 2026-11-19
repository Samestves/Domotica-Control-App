import 'package:flutter/material.dart';

import '../../version.dart';
import '../theme.dart';
import 'kit.dart';

/// Hoja «Qué hay de nuevo». Sale sola una vez al abrir la app después de actualizar ([justUpdated]),
/// y se puede volver a ver en Ajustes → Acerca de.
Future<void> showNewsSheet(BuildContext context, {bool justUpdated = false}) =>
    showAppSheet<void>(context, (_) => NewsSheet(justUpdated: justUpdated));

class NewsSheet extends StatelessWidget {
  final bool justUpdated;
  const NewsSheet({super.key, this.justUpdated = false});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (justUpdated) ...[StatusDot(color: c.green), const SizedBox(width: 9)],
              Flexible(
                child: Eyebrow(
                  justUpdated ? 'Actualizada a $appVersion' : '$appVersion · compilación $appBuild',
                  color: justUpdated ? c.green : null,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('Qué hay de nuevo', style: T.title),
            if (justUpdated) ...[
              const SizedBox(height: 6),
              Text('Tus dispositivos y sus claves siguen guardados.', style: T.small.copyWith(color: c.text2)),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < appNews.length; i++) ...[
              if (i > 0) const Hairline(),
              _Item(number: i + 1, text: appNews[i]),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        PillButton(justUpdated ? 'Entendido' : 'Listo', expand: true, onTap: () => Navigator.pop(context)),
      ]),
    );
  }
}

/// Un punto de la lista: el número a la izquierda, como en una ficha técnica.
class _Item extends StatelessWidget {
  final int number;
  final String text;
  const _Item({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 28,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Eyebrow(number.toString().padLeft(2, '0'), color: c.text3),
          ),
        ),
        Expanded(child: Text(text, style: T.body)),
      ]),
    );
  }
}

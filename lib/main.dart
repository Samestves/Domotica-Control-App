import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final state = AppState();
  try {
    await state.load();
  } catch (e) {
    // Nunca quedarse en la pantalla de carga por un dato guardado raro: la app abre igual.
    debugPrint('No se pudo leer lo guardado: $e');
  }
  runApp(ControlApp(state: state));
  state.checkForUpdateQuietly(); // sin esperar: la app abre al instante
  // Si al abrirla no había internet (el teléfono estaba en la red de una placa), se revisa al volver a ella.
  AppLifecycleListener(onResume: state.checkBoardsIfStale);
}

/// Hace llegar el estado de la app a todas las pantallas.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class ControlApp extends StatelessWidget {
  final AppState state;

  /// Pantalla inicial. Por defecto, la lista de dispositivos; las capturas de diseño usan otras.
  final Widget home;

  /// Para las capturas: obliga un tema sin tocar el ajuste guardado.
  final ThemeMode? forceTheme;

  const ControlApp({super.key, required this.state, this.home = const HomeScreen(), this.forceTheme});

  static final _light = buildTheme(Brightness.light);
  static final _dark = buildTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ValueListenableBuilder(
        valueListenable: state.theme,
        builder: (context, _, _) => MaterialApp(
          title: 'Control Domótica',
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
          themeMode: forceTheme ?? state.themeMode,
          home: home,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'state/app_state.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
  final state = AppState();
  await state.load();
  runApp(ControlApp(state: state));
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

  const ControlApp({super.key, required this.state, this.home = const HomeScreen()});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Control Domótica',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: home,
      ),
    );
  }
}

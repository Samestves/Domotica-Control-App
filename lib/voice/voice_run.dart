import 'dart:async';

import '../state/app_state.dart';
import 'voice_commands.dart';

/// Envía una orden y espera que la placa confirme cada pin con su respuesta (por ejemplo, `V1:1`).
///
/// Devuelve null si la placa lo confirmó todo, o el problema para mostrar al usuario.
Future<String?> runVoiceCommand(Session s, VoiceCommand c, {Duration timeout = const Duration(seconds: 2)}) async {
  if (!s.connected) return 'La casa no está conectada.';

  final pending = Map.of(c.expects);
  final result = Completer<String?>();
  void finish(String? problem) {
    if (!result.isCompleted) result.complete(problem);
  }

  final sub = s.messages.listen((m) {
    if (m.isPin && pending[m.pin] == int.tryParse(m.value)) pending.remove(m.pin);
    if (m.kind == 'ERR') finish('La casa respondió: ${m.value}');
    if (m.kind == 'AUTH') finish('La casa pide la clave.');
    if (pending.isEmpty) finish(null);
  });
  c.sends.forEach((pin, value) => s.send(pin, value));
  if (pending.isEmpty) finish(null);

  final problem = await result.future.timeout(timeout, onTimeout: () => 'La casa no respondió.');
  await sub.cancel();
  return problem;
}

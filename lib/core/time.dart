import 'package:clock/clock.dart';

/// Agora, em milissegundos desde a época Unix: a mesma escala dos timestamps
/// das amostras. Usa `clock` para que os testes possam controlar o tempo.
double nowMs() => clock.now().microsecondsSinceEpoch / 1000.0;

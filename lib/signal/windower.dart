import 'dart:collection';

import '../core/imu.dart';

/// Transforma o fluxo contínuo de amostras em janelas temporais.
///
/// O janelamento é por tempo (timestamps), não por contagem de amostras,
/// porque a taxa real do sensor oscila e alguns aparelhos entregam bem mais
/// que a taxa pedida. O buffer guarda só o necessário para cobrir uma janela
/// (descarta por tempo), então funciona com qualquer taxa real. Uma janela é
/// emitida quando:
///   1. o buffer cobre pelo menos [windowSizeMs] de sinal, e
///   2. passaram [hopMs] desde o fim da janela anterior.
/// Com janela de 4 s e sobreposição de 0.75, sai uma janela de 4 s a cada 1 s.
class Windower {
  Windower({required this.windowSizeMs, required this.hopMs});

  final double windowSizeMs;
  final double hopMs;
  final Queue<ImuSample> _buffer = Queue();
  double? _lastWindowEnd;

  int get bufferSize => _buffer.length;

  /// Adiciona uma amostra e devolve uma janela se for hora de emitir.
  SignalWindow? push(ImuSample sample) {
    _buffer.addLast(sample);
    final end = sample.timestamp;
    final start = end - windowSizeMs;
    // Descarta o que ficou antes do início da janela, mantendo uma amostra
    // no início ou antes dele para saber que a janela está coberta.
    while (_buffer.length > 1 && _buffer.elementAt(1).timestamp <= start) {
      _buffer.removeFirst();
    }
    if (end - _buffer.first.timestamp < windowSizeMs) return null;
    final last = _lastWindowEnd;
    if (last != null && end - last < hopMs) return null;

    _lastWindowEnd = end;
    return SignalWindow(
      startTimestamp: start,
      endTimestamp: end,
      samples: [for (final s in _buffer) if (s.timestamp >= start) s],
    );
  }
}

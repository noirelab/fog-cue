import 'fog.dart';

class Transition {
  const Transition(this.from, this.to);
  final FogState from;
  final FogState to;
  bool get changed => from != to;
}

/// Máquina de estados do episódio de FoG. Recebe uma decisão binária por
/// janela (do detector) e decide o estado. Não conhece tempo nem sensores.
///
/// Transições (d = janela detectada, !d = não detectada):
///
///   NORMAL       --d-->  POSSIBLE_FOG   (ou FOG_DETECTED se confirmWindows = 1)
///   POSSIBLE_FOG --d-->  FOG_DETECTED   ao acumular confirmWindows positivas
///   POSSIBLE_FOG --!d--> NORMAL         (alarme descartado)
///   FOG_DETECTED --d-->  FOG_DETECTED
///   FOG_DETECTED --!d--> RECOVERY
///   RECOVERY     --d-->  FOG_DETECTED   (episódio retomado)
///   RECOVERY     --!d--> NORMAL         ao acumular recoveryWindows negativas
///   qualquer     --force()--> FOG_DETECTED   (botão "Simular FoG")
///
/// confirmWindows reduz falsos positivos isolados; recoveryWindows funciona
/// como histerese na saída do episódio.
class FogStateMachine {
  FogStateMachine({required this.confirmWindows, required this.recoveryWindows});

  final int confirmWindows;
  final int recoveryWindows;

  FogState _state = FogState.normal;
  int _positives = 0;
  int _negatives = 0;

  FogState get state => _state;

  Transition update(bool detected) {
    final from = _state;
    _state = _next(detected);
    return Transition(from, _state);
  }

  Transition force() {
    final from = _state;
    _state = FogState.fogDetected;
    _positives = confirmWindows;
    _negatives = 0;
    return Transition(from, _state);
  }

  void reset() {
    _state = FogState.normal;
    _positives = 0;
    _negatives = 0;
  }

  FogState _next(bool detected) {
    switch (_state) {
      case FogState.normal:
      case FogState.possibleFog:
        if (!detected) {
          _positives = 0;
          return FogState.normal;
        }
        _positives++;
        return _positives >= confirmWindows ? FogState.fogDetected : FogState.possibleFog;
      case FogState.fogDetected:
        if (detected) return FogState.fogDetected;
        _negatives = 0;
        return FogState.recovery;
      case FogState.recovery:
        if (detected) return FogState.fogDetected;
        _negatives++;
        if (_negatives >= recoveryWindows) {
          _positives = 0;
          return FogState.normal;
        }
        return FogState.recovery;
    }
  }
}

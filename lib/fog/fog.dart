import 'dart:async';

import '../core/imu.dart';

enum FogState {
  normal('NORMAL'),
  possibleFog('POSSIBLE_FOG'),
  fogDetected('FOG_DETECTED'),
  recovery('RECOVERY');

  const FogState(this.code);

  /// Nome usado no CSV e na interface.
  final String code;
}

class FogDetectionResult {
  const FogDetectionResult({
    required this.detected,
    required this.confidence,
    required this.timestamp,
    this.metadata = const {},
  });

  final bool detected;

  /// Entre 0 e 1.
  final double confidence;

  /// Momento (ms Unix) em que a análise terminou.
  final double timestamp;
  final Map<String, Object?> metadata;
}

/// Contrato de qualquer detector de FoG.
///
/// Implementações previstas: HeuristicFogDetector, FreezeIndexDetector,
/// LogisticRegressionDetector, RandomForestDetector, SvmDetector,
/// NeuralNetworkDetector, TfliteFogDetector. O resto do app só conhece esta
/// interface: trocar de detector não muda a interface gráfica, o logger nem
/// o Cue Engine.
abstract interface class FogDetector {
  String get name;

  /// Versão gravada nos metadados da sessão, para reprodutibilidade.
  String get version;

  FutureOr<FogDetectionResult> analyze(SignalWindow window);
}

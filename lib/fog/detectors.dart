import '../config/experiment.dart';
import '../core/imu.dart';
import '../core/time.dart';
import '../signal/features.dart';
import '../signal/spectral.dart';
import 'fog.dart';

/// Detector nulo: nunca detecta FoG.
///
/// Serve para rodar a pipeline inteira (sensores, janelas, logger) sem
/// algoritmo nenhum. Episódios só aparecem via "Simular FoG".
class MockFogDetector implements FogDetector {
  @override
  String get name => 'MockFogDetector';

  @override
  String get version => '0.1.0';

  @override
  FogDetectionResult analyze(SignalWindow window) => FogDetectionResult(
        detected: false,
        confidence: 0,
        timestamp: nowMs(),
        metadata: {'samples': window.samples.length},
      );
}

/// ATENÇÃO: DETECTOR DE TESTE, SEM VALIDADE CLÍNICA.
///
/// Existe só para exercitar a pipeline com sinal real: marca "detectado"
/// quando o desvio padrão da magnitude do acelerômetro na janela passa de
/// [threshold] (em m/s²). Qualquer movimento vigoroso (andar rápido, sacudir
/// o celular) dispara; parado nunca dispara. Ele NÃO distingue FoG de
/// caminhada e NÃO deve ser usado como resultado do TCC.
///
/// Detectores reais (Freeze Index, modelos treinados em Python) devem
/// implementar a mesma interface [FogDetector].
class HeuristicFogDetector implements FogDetector {
  HeuristicFogDetector(this.threshold);

  final double threshold;

  @override
  String get name => 'HeuristicFogDetector';

  @override
  String get version => '0.1.0-test-only';

  @override
  FogDetectionResult analyze(SignalWindow window) {
    final value = extractFeatures(window)['acc_mag_std'] ?? double.nan;
    final detected = value.isFinite && value > threshold;
    // Confiança 0.5 no limiar e 1 em 2x o limiar. Não é uma probabilidade.
    final confidence = value.isFinite ? (value / (2 * threshold)).clamp(0.0, 1.0) : 0.0;
    return FogDetectionResult(
      detected: detected,
      confidence: confidence,
      timestamp: nowMs(),
      metadata: {'acc_mag_std': value, 'threshold': threshold},
    );
  }
}

/// Detector pelo Freeze Index (Moore et al., 2008; Bächlin et al., 2010).
///
/// Para cada janela: magnitude do acelerômetro sem gravidade, espectro de
/// potência, e as energias nas bandas locomotora (0,5 a 3 Hz) e de freeze
/// (3 a 8 Hz). Freeze Index = energia de freeze / energia locomotora.
///
///   - energia total < [powerThreshold]: a pessoa está parada, não detecta;
///   - senão, detecta se o Freeze Index passa de [freezeIndexThreshold].
///
/// Os limiares padrão são pontos de partida para calibração. Os trabalhos
/// originais ajustavam os limiares por paciente e usavam sensor fixo na
/// perna; com o celular no bolso, o desempenho precisa ser medido.
class FreezeIndexDetector implements FogDetector {
  FreezeIndexDetector({
    required this.freezeIndexThreshold,
    required this.powerThreshold,
    required int sampleRateHz,
  }) : _features = FreezeIndexFeatures(sampleRateHz: sampleRateHz.toDouble());

  final double freezeIndexThreshold;
  final double powerThreshold;
  final FreezeIndexFeatures _features;

  @override
  String get name => 'FreezeIndexDetector';

  @override
  String get version => '0.1.0';

  @override
  FogDetectionResult analyze(SignalWindow window) {
    if (window.samples.length < 8) {
      return FogDetectionResult(detected: false, confidence: 0, timestamp: nowMs(), metadata: const {'reason': 'poucas amostras'});
    }
    final f = _features.extract(window);
    final fi = f['freeze_index']!;
    final power = f['total_power']!;
    final moving = power >= powerThreshold;
    final detected = moving && fi > freezeIndexThreshold;
    // Confiança 0.5 no limiar e 1 em 2x o limiar. Não é uma probabilidade.
    final confidence = moving ? (fi / (2 * freezeIndexThreshold)).clamp(0.0, 1.0) : 0.0;
    return FogDetectionResult(detected: detected, confidence: confidence, timestamp: nowMs(), metadata: f);
  }
}

/// Ponto único onde o detector ativo é escolhido. Novo detector = novo case.
FogDetector createDetector(ExperimentSettings settings) => switch (settings.detector) {
      DetectorName.mock => MockFogDetector(),
      DetectorName.heuristic => HeuristicFogDetector(settings.fogThreshold),
      DetectorName.freezeIndex => FreezeIndexDetector(
          freezeIndexThreshold: settings.freezeIndexThreshold,
          powerThreshold: settings.powerThreshold,
          sampleRateHz: settings.sampleRateHz,
        ),
    };

const detectorLabels = <DetectorName, String>{
  DetectorName.mock: 'Mock (nunca detecta)',
  DetectorName.heuristic: 'Heurístico (somente teste)',
  DetectorName.freezeIndex: 'Freeze Index',
};

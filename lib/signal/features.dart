import 'dart:math' as math;

import '../core/imu.dart';

// Estatísticas descritivas. Todas retornam NaN para lista vazia, para que um
// erro de janelamento apareça nos dados em vez de virar zero.

double mean(List<double> v) {
  if (v.isEmpty) return double.nan;
  var sum = 0.0;
  for (final x in v) {
    sum += x;
  }
  return sum / v.length;
}

/// Desvio padrão populacional (ddof=0), igual a numpy.std por padrão.
double std(List<double> v) {
  if (v.isEmpty) return double.nan;
  final m = mean(v);
  var acc = 0.0;
  for (final x in v) {
    acc += (x - m) * (x - m);
  }
  return math.sqrt(acc / v.length);
}

double rms(List<double> v) {
  if (v.isEmpty) return double.nan;
  var acc = 0.0;
  for (final x in v) {
    acc += x * x;
  }
  return math.sqrt(acc / v.length);
}

double minOf(List<double> v) => v.isEmpty ? double.nan : v.reduce(math.min);

double maxOf(List<double> v) => v.isEmpty ? double.nan : v.reduce(math.max);

/// Vetor de características com nomes estáveis (viram colunas em Python).
typedef FeatureVector = Map<String, double>;

/// Um extrator recebe a janela e devolve features nomeadas. Novos extratores
/// (FFT, potência por banda, Freeze Index, features espectrais) entram aqui
/// sem alterar os detectores existentes.
abstract interface class FeatureExtractor {
  String get name;
  FeatureVector extract(SignalWindow window);
}

/// Estatísticas da magnitude do acelerômetro na janela.
class AccMagnitudeStats implements FeatureExtractor {
  const AccMagnitudeStats();

  @override
  String get name => 'acc_magnitude_stats';

  @override
  FeatureVector extract(SignalWindow window) {
    final mag = [for (final s in window.samples) magnitude(s.accelerometer)];
    return {
      'acc_mag_mean': mean(mag),
      'acc_mag_std': std(mag),
      'acc_mag_rms': rms(mag),
      'acc_mag_min': minOf(mag),
      'acc_mag_max': maxOf(mag),
    };
  }
}

const List<FeatureExtractor> defaultExtractors = [AccMagnitudeStats()];

/// Roda todos os extratores e junta os resultados num único vetor.
FeatureVector extractFeatures(SignalWindow window, [List<FeatureExtractor> extractors = defaultExtractors]) => {
      for (final e in extractors) ...e.extract(window),
    };

import 'dart:math' as math;
import 'dart:typed_data';

import '../config/experiment.dart';
import '../core/imu.dart';
import 'features.dart';

/// Reamostra a série (t em ms, v) numa grade uniforme de [rateHz] por
/// interpolação linear, do primeiro ao último instante.
///
/// Necessário porque a FFT supõe amostras igualmente espaçadas, e o sensor
/// entrega intervalos que oscilam alguns ms em torno do nominal.
List<double> resampleUniform(List<double> t, List<double> v, double rateHz) {
  if (t.length < 2) return List.of(v);
  final step = 1000 / rateHz;
  final n = ((t.last - t.first) / step).floor() + 1;
  final out = List<double>.filled(n, 0);
  var j = 0;
  for (var i = 0; i < n; i++) {
    final ti = t.first + i * step;
    while (j < t.length - 2 && t[j + 1] < ti) {
      j++;
    }
    final span = t[j + 1] - t[j];
    final a = span > 0 ? ((ti - t[j]) / span).clamp(0.0, 1.0) : 0.0;
    out[i] = v[j] + (v[j + 1] - v[j]) * a;
  }
  return out;
}

int _nextPowerOfTwo(int n) {
  var p = 1;
  while (p < n) {
    p <<= 1;
  }
  return p;
}

/// FFT radix-2 iterativa (Cooley-Tukey), no lugar. O tamanho de [re] e [im]
/// precisa ser potência de 2.
void fft(Float64List re, Float64List im) {
  final n = re.length;
  // Reordenação por inversão de bits.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; (j & bit) != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final angle = -2 * math.pi / len;
    final wRe = math.cos(angle);
    final wIm = math.sin(angle);
    final half = len >> 1;
    for (var start = 0; start < n; start += len) {
      var cRe = 1.0;
      var cIm = 0.0;
      for (var k = 0; k < half; k++) {
        final a = start + k;
        final b = a + half;
        final tRe = re[b] * cRe - im[b] * cIm;
        final tIm = re[b] * cIm + im[b] * cRe;
        re[b] = re[a] - tRe;
        im[b] = im[a] - tIm;
        re[a] += tRe;
        im[a] += tIm;
        final nRe = cRe * wRe - cIm * wIm;
        cIm = cRe * wIm + cIm * wRe;
        cRe = nRe;
      }
    }
  }
}

/// Espectro de potência unilateral.
class PowerSpectrum {
  const PowerSpectrum(this.power, this.binHz);

  /// power[k] corresponde à frequência k * binHz.
  final Float64List power;
  final double binHz;

  /// Soma da potência nas frequências em [loHz, hiHz).
  double band(double loHz, double hiHz) {
    var sum = 0.0;
    for (var k = 0; k < power.length; k++) {
      final f = k * binHz;
      if (f >= loHz && f < hiHz) sum += power[k];
    }
    return sum;
  }
}

/// Espectro de potência com janela de Hann e preenchimento com zeros até a
/// próxima potência de 2. A escala faz a soma de todas as raias aproximar a
/// variância do sinal (Parseval): a potência de uma banda fica na mesma
/// unidade da variância (aqui, (m/s²)²) e não depende do tamanho da janela.
PowerSpectrum powerSpectrum(List<double> x, double rateHz) {
  final n = x.length;
  final m = _nextPowerOfTwo(math.max(n, 2));
  final re = Float64List(m);
  final im = Float64List(m);
  var windowEnergy = 0.0;
  for (var i = 0; i < n; i++) {
    final w = n == 1 ? 1.0 : 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    re[i] = x[i] * w;
    windowEnergy += w * w;
  }
  fft(re, im);
  final half = m ~/ 2;
  final power = Float64List(half + 1);
  if (windowEnergy > 0) {
    for (var k = 0; k <= half; k++) {
      final oneSided = (k == 0 || k == half) ? 1.0 : 2.0;
      power[k] = oneSided * (re[k] * re[k] + im[k] * im[k]) / (m * windowEnergy);
    }
  }
  return PowerSpectrum(power, rateHz / m);
}

/// Features do Freeze Index (Moore et al., 2008), calculadas sobre a
/// magnitude do acelerômetro sem a componente constante (gravidade).
///
/// A magnitude é usada porque não depende da orientação do celular no
/// bolso; os trabalhos originais usavam o eixo vertical de um sensor fixo
/// na perna.
class FreezeIndexFeatures implements FeatureExtractor {
  const FreezeIndexFeatures({required this.sampleRateHz});

  final double sampleRateHz;

  @override
  String get name => 'freeze_index';

  @override
  FeatureVector extract(SignalWindow window) {
    final t = [for (final s in window.samples) s.timestamp];
    final mag = [for (final s in window.samples) magnitude(s.accelerometer)];
    final uniform = resampleUniform(t, mag, sampleRateHz);
    final m = mean(uniform);
    final spectrum = powerSpectrum([for (final v in uniform) v - m], sampleRateHz);
    final locomotor = spectrum.band(locomotorBandHz.$1, locomotorBandHz.$2);
    final freeze = spectrum.band(freezeBandHz.$1, freezeBandHz.$2);
    return {
      'locomotor_power': locomotor,
      'freeze_power': freeze,
      'total_power': locomotor + freeze,
      // Evita divisão por zero em sinal parado; o limiar de potência já
      // descarta esse caso antes de olhar o índice.
      'freeze_index': freeze / math.max(locomotor, 1e-9),
    };
  }
}

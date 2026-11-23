import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fog_cue/core/imu.dart';
import 'package:fog_cue/fog/detectors.dart';
import 'package:fog_cue/signal/spectral.dart';

const rate = 50.0;

/// Janela de [seconds] a 50 Hz com z = gravidade + sinal(t). [jitterMs]
/// desloca os timestamps de forma irregular, como no sensor real.
SignalWindow window(double Function(double t) signal, {double seconds = 4, double jitterMs = 0}) {
  final rnd = math.Random(42);
  final n = (seconds * rate).round() + 1;
  final samples = <ImuSample>[];
  for (var i = 0; i < n; i++) {
    final tMs = i * 20.0 + (i == 0 || i == n - 1 ? 0 : (rnd.nextDouble() * 2 - 1) * jitterMs);
    samples.add(ImuSample(
      timestamp: tMs,
      accelerometer: Vector3(0, 0, 9.81 + signal(tMs / 1000)),
      gyroscope: const Vector3(0, 0, 0),
    ));
  }
  return SignalWindow(startTimestamp: samples.first.timestamp, endTimestamp: samples.last.timestamp, samples: samples);
}

double sine(double t, double hz, double amplitude) => amplitude * math.sin(2 * math.pi * hz * t);

void main() {
  group('FFT', () {
    test('igual à DFT direta em um sinal aleatório', () {
      final rnd = math.Random(1);
      final x = [for (var i = 0; i < 16; i++) rnd.nextDouble() * 2 - 1];
      final re = Float64List.fromList(x);
      final im = Float64List(16);
      fft(re, im);
      for (var k = 0; k < 16; k++) {
        var dRe = 0.0;
        var dIm = 0.0;
        for (var n = 0; n < 16; n++) {
          dRe += x[n] * math.cos(2 * math.pi * k * n / 16);
          dIm -= x[n] * math.sin(2 * math.pi * k * n / 16);
        }
        expect(re[k], closeTo(dRe, 1e-9));
        expect(im[k], closeTo(dIm, 1e-9));
      }
    });

    test('potência de uma senoide aparece na frequência certa e soma a variância', () {
      // Senoide de amplitude 2 tem variância 2²/2 = 2.
      final x = [for (var i = 0; i < 200; i++) sine(i / rate, 5, 2)];
      final s = powerSpectrum(x, rate);
      expect(s.band(3, 8), closeTo(2, 0.05));
      expect(s.band(0.5, 3), lessThan(0.02));
      var peak = 0;
      for (var k = 1; k < s.power.length; k++) {
        if (s.power[k] > s.power[peak]) peak = k;
      }
      expect(peak * s.binHz, closeTo(5, s.binHz));
    });
  });

  test('resampleUniform interpola linearmente em grade uniforme', () {
    final out = resampleUniform([0, 10, 30, 40], [0, 10, 30, 40], 100);
    expect(out, [0, 10, 20, 30, 40]);
  });

  group('Freeze Index', () {
    const features = FreezeIndexFeatures(sampleRateHz: rate);

    test('caminhada (1,5 Hz) tem índice baixo; tremor (5 Hz) tem índice alto', () {
      final walk = features.extract(window((t) => sine(t, 1.5, 3)));
      final tremor = features.extract(window((t) => sine(t, 5, 1)));
      expect(walk['freeze_index'], lessThan(0.1));
      expect(tremor['freeze_index'], greaterThan(10));
      expect(walk['total_power'], closeTo(4.5, 0.3)); // 3²/2, gravidade removida
    });

    test('detector: tremor dispara; caminhada e repouso não', () {
      final d = FreezeIndexDetector(freezeIndexThreshold: 2, powerThreshold: 0.2, sampleRateHz: 50);
      final tremor = d.analyze(window((t) => sine(t, 5, 1), jitterMs: 4));
      final walk = d.analyze(window((t) => sine(t, 1.5, 3), jitterMs: 4));
      final still = d.analyze(window((t) => 0.01 * math.sin(2 * math.pi * 5 * t)));
      expect(tremor.detected, isTrue);
      expect(tremor.confidence, greaterThan(0.5));
      expect(walk.detected, isFalse);
      // Parado: índice pode ser alto, mas não há energia suficiente.
      expect(still.detected, isFalse);
      expect(still.confidence, 0);
    });

    test('caminhada com tremor sobreposto: decide pela razão entre bandas', () {
      final d = FreezeIndexDetector(freezeIndexThreshold: 2, powerThreshold: 0.2, sampleRateHz: 50);
      final mostlyWalk = d.analyze(window((t) => sine(t, 1.5, 3) + sine(t, 5, 0.5)));
      final mostlyTremor = d.analyze(window((t) => sine(t, 1.5, 0.3) + sine(t, 5, 1.5)));
      expect(mostlyWalk.detected, isFalse);
      expect(mostlyTremor.detected, isTrue);
    });
  });
}

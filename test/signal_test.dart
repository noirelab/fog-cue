import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fog_cue/core/imu.dart';
import 'package:fog_cue/signal/circular_buffer.dart';
import 'package:fog_cue/signal/features.dart';
import 'package:fog_cue/signal/preprocessing.dart';
import 'package:fog_cue/signal/windower.dart';

ImuSample sample(double t, [double x = 0, double y = 0, double z = 9.81]) =>
    ImuSample(timestamp: t, accelerometer: Vector3(x, y, z), gyroscope: const Vector3(0, 0, 0));

void main() {
  group('CircularBuffer', () {
    test('mantém ordem cronológica e sobrescreve o mais antigo', () {
      final b = CircularBuffer<int>(3);
      for (final n in [1, 2, 3, 4, 5]) {
        b.push(n);
      }
      expect(b.toList(), [3, 4, 5]);
      expect(b.length, 3);
      expect(b.first, 3);
      expect(b.last, 5);
    });

    test('funciona parcialmente cheio e depois de clear', () {
      final b = CircularBuffer<int>(4);
      expect(b.first, isNull);
      b
        ..push(7)
        ..push(8);
      expect(b.toList(), [7, 8]);
      b.clear();
      expect(b.isEmpty, isTrue);
    });

    test('rejeita capacidade inválida', () {
      expect(() => CircularBuffer<int>(0), throwsArgumentError);
    });
  });

  test('magnitude é a norma euclidiana', () {
    expect(magnitude(const Vector3(3, 4, 0)), 5);
    expect(magnitude(const Vector3(0, 0, -1)), 1);
  });

  group('estatísticas', () {
    const v = <double>[2, 4, 4, 4, 5, 5, 7, 9];
    test('média, desvio (ddof=0), RMS, mínimo, máximo', () {
      expect(mean(v), 5);
      expect(std(v), 2);
      expect(rms([3, 4]), closeTo(math.sqrt(12.5), 1e-12));
      expect(minOf(v), 2);
      expect(maxOf(v), 9);
    });
    test('lista vazia retorna NaN', () {
      for (final f in [mean, std, rms, minOf, maxOf]) {
        expect(f(const []).isNaN, isTrue);
      }
    });
  });

  test('extractFeatures calcula estatísticas da magnitude do acelerômetro', () {
    final w = SignalWindow(
      startTimestamp: 0,
      endTimestamp: 20,
      samples: [sample(0, 0, 0, 1), sample(10, 0, 0, 3), sample(20, 3, 4, 0)],
    );
    final f = extractFeatures(w);
    expect(f['acc_mag_mean'], 3);
    expect(f['acc_mag_min'], 1);
    expect(f['acc_mag_max'], 5);
    expect(f['acc_mag_std'], closeTo(math.sqrt(8 / 3), 1e-12));
    expect(f['acc_mag_rms'], closeTo(math.sqrt(35 / 3), 1e-12));
  });

  test('preprocess sem etapas devolve a mesma janela; etapas rodam em ordem', () {
    final w = SignalWindow(startTimestamp: 0, endTimestamp: 0, samples: [sample(0)]);
    expect(identical(preprocess(w, const []), w), isTrue);
    final order = <String>[];
    preprocess(w, [
      (x) {
        order.add('a');
        return x;
      },
      (x) {
        order.add('b');
        return x;
      },
    ]);
    expect(order, ['a', 'b']);
  });

  group('Windower', () {
    test('janelas de 2 s a cada 1 s com sobreposição de 50% (50 Hz)', () {
      final w = Windower(windowSizeMs: 2000, hopMs: 1000);
      final windows = <SignalWindow>[];
      for (var t = 0; t <= 5000; t += 20) {
        final out = w.push(sample(t.toDouble()));
        if (out != null) windows.add(out);
      }
      expect(windows.map((x) => x.endTimestamp), [2000, 3000, 4000, 5000]);
      for (final win in windows) {
        expect(win.endTimestamp - win.startTimestamp, 2000);
        expect(win.samples.length, 101);
        expect(win.samples.first.timestamp, win.startTimestamp);
      }
    });

    test('continua emitindo janelas com o sensor 4x mais rápido que o pedido', () {
      final w = Windower(windowSizeMs: 2000, hopMs: 1000);
      final ends = <double>[];
      for (var t = 0; t <= 4000; t += 5) {
        final out = w.push(sample(t.toDouble()));
        if (out != null) ends.add(out.endTimestamp);
      }
      expect(ends, [2000, 3000, 4000]);
      expect(w.bufferSize, lessThanOrEqualTo(402));
    });

    test('sem sobreposição, janelas não se sobrepõem', () {
      final w = Windower(windowSizeMs: 1000, hopMs: 1000);
      final ends = <double>[];
      for (var t = 0; t <= 3000; t += 20) {
        final out = w.push(sample(t.toDouble()));
        if (out != null) ends.add(out.endTimestamp);
      }
      expect(ends, [1000, 2000, 3000]);
    });
  });
}

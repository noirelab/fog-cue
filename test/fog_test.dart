import 'package:flutter_test/flutter_test.dart';
import 'package:fog_cue/core/imu.dart';
import 'package:fog_cue/fog/detectors.dart';
import 'package:fog_cue/fog/fog.dart';
import 'package:fog_cue/fog/state_machine.dart';

const n = FogState.normal;
const p = FogState.possibleFog;
const d = FogState.fogDetected;
const r = FogState.recovery;

List<FogState> run(FogStateMachine m, List<bool> inputs) => [for (final x in inputs) m.update(x).to];

SignalWindow windowWithMagnitudes(List<double> mags) => SignalWindow(
      startTimestamp: 0,
      endTimestamp: (mags.length - 1) * 20,
      samples: [
        for (var i = 0; i < mags.length; i++)
          ImuSample(timestamp: i * 20.0, accelerometer: Vector3(0, 0, mags[i]), gyroscope: const Vector3(0, 0, 0)),
      ],
    );

void main() {
  group('FogStateMachine', () {
    test('exige confirmWindows positivas antes de FOG_DETECTED', () {
      final m = FogStateMachine(confirmWindows: 3, recoveryWindows: 2);
      expect(run(m, [true, true, true]), [p, p, d]);
    });

    test('descarta alarme isolado: POSSIBLE_FOG volta a NORMAL e zera a contagem', () {
      final m = FogStateMachine(confirmWindows: 2, recoveryWindows: 2);
      expect(run(m, [true, false, true, true]), [p, n, p, d]);
    });

    test('confirmWindows = 1 vai direto para FOG_DETECTED', () {
      final m = FogStateMachine(confirmWindows: 1, recoveryWindows: 1);
      expect(run(m, [true]), [d]);
    });

    test('sai do episódio via RECOVERY com histerese', () {
      final m = FogStateMachine(confirmWindows: 1, recoveryWindows: 2);
      expect(run(m, [true, true, false, false, false]), [d, d, r, r, n]);
    });

    test('RECOVERY volta a FOG_DETECTED se detectar de novo', () {
      final m = FogStateMachine(confirmWindows: 1, recoveryWindows: 3);
      expect(run(m, [true, false, true]), [d, r, d]);
    });

    test('force() leva a FOG_DETECTED de qualquer estado e informa mudança', () {
      final m = FogStateMachine(confirmWindows: 3, recoveryWindows: 1);
      final t = m.force();
      expect((t.from, t.to, t.changed), (n, d, true));
      expect(m.force().changed, isFalse);
      expect(run(m, [false, false]), [r, n]);
    });
  });

  group('detectores', () {
    test('Mock nunca detecta', () {
      final res = MockFogDetector().analyze(windowWithMagnitudes([1, 5, 1, 5]));
      expect(res.detected, isFalse);
      expect(res.confidence, 0);
    });

    test('Heurístico (teste) dispara só acima do limiar de desvio padrão', () {
      final det = HeuristicFogDetector(0.5);
      expect(det.analyze(windowWithMagnitudes([1, 1, 1, 1])).detected, isFalse);
      final moving = det.analyze(windowWithMagnitudes([0, 2, 0, 2]));
      expect(moving.detected, isTrue);
      expect(moving.confidence, 1);
    });
  });
}

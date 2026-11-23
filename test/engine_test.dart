import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fog_cue/config/experiment.dart';
import 'package:fog_cue/core/imu.dart';
import 'package:fog_cue/core/time.dart';
import 'package:fog_cue/cues/cue_engine.dart';
import 'package:fog_cue/fog/fog.dart';
import 'package:fog_cue/monitoring/monitoring_engine.dart';
import 'package:fog_cue/sessions/models.dart';

final settings = defaultSettings.copyWith(
  detector: DetectorName.heuristic,
  fogThreshold: 3,
  sampleRateHz: 50,
  windowSizeMs: 1000,
  windowOverlap: 0,
  confirmWindows: 2,
  recoveryWindows: 1,
  cueCooldownMs: 0,
  warmupSeconds: 0,
  cue: const CueSettings(hapticEnabled: true, audioEnabled: true, bpm: 120, durationSeconds: 1),
);

class FakeOutputs implements CueOutputs {
  int haptic = 0;
  int audio = 0;
  @override
  void hapticPulse() => haptic++;
  @override
  void audioClick() => audio++;
}

class MemoryStore implements SessionStore {
  final samples = <SampleRecord>[];
  final events = <SessionEvent>[];
  final sessions = <Session>[];
  final finished = <String>[];

  @override
  Future<void> createSession(Session session) async => sessions.add(session);
  @override
  Future<void> finishSession(String id, double endedAt) async => finished.add(id);
  /// Quantas próximas escritas de amostras devem falhar.
  int failSampleWrites = 0;

  @override
  Future<void> insertSamples(String sessionId, List<SampleRecord> rows) async {
    if (failSampleWrites > 0) {
      failSampleWrites--;
      throw StateError('disco cheio');
    }
    samples.addAll(rows);
  }
  @override
  Future<void> insertEvents(String sessionId, List<SessionEvent> evs) async => events.addAll(evs);
}

/// Monta o engine com dependências falsas e um "sensor" controlado pelo teste.
class Harness {
  Harness(this.async);
  final FakeAsync async;
  final store = MemoryStore();
  final outputs = FakeOutputs();
  void Function(ImuSample)? _emit;
  late MonitoringEngine engine;

  void start(ExperimentSettings s) {
    final deps = EngineDeps(
      startImu: (_, onSample) {
        _emit = onSample;
        return () => _emit = null;
      },
      cueOutputs: outputs,
      store: store,
      appVersion: 'test',
      platform: 'test',
    );
    MonitoringEngine.start(s, const SessionInfo(phonePlacement: PhonePlacement.pocket), deps).then((e) => engine = e);
    async.flushMicrotasks();
  }

  /// Avança 20 ms (50 Hz) e entrega uma amostra com magnitude [z].
  void feed(double z) {
    async.elapse(const Duration(milliseconds: 20));
    _emit?.call(ImuSample(timestamp: nowMs(), accelerometer: Vector3(0, 0, z), gyroscope: const Vector3(0, 0, 0)));
    async.flushMicrotasks();
  }

  /// Encerra e devolve o erro, se houver.
  Object? stop() {
    Object? error;
    engine.stop().catchError((Object e) => error = e);
    async.flushMicrotasks();
    return error;
  }
}

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1000000);

  test('aquecimento: agitação no início (guardar o celular) não dispara', () {
    fakeAsync((async) {
      final h = Harness(async)..start(settings.copyWith(warmupSeconds: 3));
      for (var i = 0; i < 100; i++) {
        h.feed(i.isOdd ? 19.0 : 1.0); // 2 s agitado, dentro dos 3 s
      }
      for (var i = 0; i < 100; i++) {
        h.feed(9.81);
      }
      expect(h.store.events.where((e) => e.type == SessionEventType.fogDetected), isEmpty);
      expect(h.outputs.haptic, 0);

      // Depois do aquecimento, o mesmo sinal dispara.
      for (var i = 0; i < 150; i++) {
        h.feed(i.isOdd ? 19.0 : 1.0);
      }
      expect(h.engine.snapshot().state, FogState.fogDetected);
      h.stop();
    }, initialTime: t0);
  });

  test('parado, agitado, parado: percorre todos os estados e dispara o cue', () {
    fakeAsync((async) {
      final h = Harness(async)..start(settings);
      final states = <FogState>[];
      void run(int count, double Function(int i) z) {
        for (var i = 0; i < count; i++) {
          h.feed(z(i));
          final s = h.engine.snapshot().state;
          if (states.isEmpty || states.last != s) states.add(s);
        }
      }

      run(50, (_) => 9.81); // 1 s parado
      run(100, (i) => i.isOdd ? 19.0 : 1.0); // 2 s agitado
      run(150, (_) => 9.81); // 3 s parado

      expect(states, [FogState.normal, FogState.possibleFog, FogState.fogDetected, FogState.recovery, FogState.normal]);
      expect(h.outputs.haptic, greaterThan(0));
      expect(h.outputs.audio, greaterThan(0));

      final snap = h.engine.snapshot();
      expect(snap.measuredRateHz, closeTo(50, 0.01));
      expect(snap.processingLatencyMs, 0); // relógio falso: processamento instantâneo
      expect(snap.cueLatencyMs, 0);

      h.stop();
      expect(h.store.events.map((e) => e.type), [
        SessionEventType.sessionStarted,
        SessionEventType.fogPossible,
        SessionEventType.fogDetected,
        SessionEventType.cueStarted,
        SessionEventType.cueFinished,
        SessionEventType.recovery,
        SessionEventType.sessionFinished,
      ]);
      expect(h.store.samples, hasLength(300));
      expect(h.store.samples.any((s) => s.cueTriggered), isTrue);
      expect(h.store.sessions.single.metadata.detectorName, 'HeuristicFogDetector');
      expect(h.store.finished, [h.engine.session.id]);
    }, initialTime: t0);
  });

  test('"Simular FoG" força FOG_DETECTED e dispara o cue mesmo com o detector mock', () {
    fakeAsync((async) {
      final h = Harness(async)..start(settings.copyWith(detector: DetectorName.mock));
      h.engine.simulateFog();
      expect(h.engine.snapshot().state, FogState.fogDetected);
      expect(h.engine.snapshot().cueActive, isTrue);
      h.stop();
      final detected = h.store.events.firstWhere((e) => e.type == SessionEventType.fogDetected);
      expect(detected.metadata['simulated'], isTrue);
      expect(h.store.events.map((e) => e.type), contains(SessionEventType.cueStarted));
    }, initialTime: t0);
  });

  test('falha de gravação ao encerrar: avisa, não perde dados e pode tentar de novo', () {
    fakeAsync((async) {
      final h = Harness(async)..start(settings.copyWith(detector: DetectorName.mock));
      for (var i = 0; i < 30; i++) {
        h.feed(9.81);
      }
      h.store.failSampleWrites = 2; // as duas tentativas do stop falham
      expect(h.stop(), isA<StateError>());
      expect(h.store.finished, isEmpty); // não marca como encerrada
      expect(h.stop(), isNull); // segunda tentativa grava tudo
      expect(h.store.samples, hasLength(30));
      expect(h.store.finished, [h.engine.session.id]);
      expect(h.store.events.where((e) => e.type == SessionEventType.sessionFinished), hasLength(1));
    }, initialTime: t0);
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fog_cue/config/experiment.dart';
import 'package:fog_cue/cues/cue_engine.dart';

const settings = CueSettings(hapticEnabled: true, audioEnabled: true, bpm: 120, durationSeconds: 2);

class FakeOutputs implements CueOutputs {
  int haptic = 0;
  int audio = 0;
  @override
  void hapticPulse() => haptic++;
  @override
  void audioClick() => audio++;
}

void main() {
  test('canStartCue aplica cooldown a partir do fim do cue anterior', () {
    expect(canStartCue(active: false, lastEndedAt: null, now: 1000, cooldownMs: 5000), isTrue);
    expect(canStartCue(active: true, lastEndedAt: null, now: 1000, cooldownMs: 0), isFalse);
    expect(canStartCue(active: false, lastEndedAt: 1000, now: 5999, cooldownMs: 5000), isFalse);
    expect(canStartCue(active: false, lastEndedAt: 1000, now: 6000, cooldownMs: 5000), isTrue);
  });

  group('CueEngine', () {
    final t0 = DateTime.fromMillisecondsSinceEpoch(0);

    test('toca no ritmo do BPM durante durationSeconds', () {
      fakeAsync((async) {
        final out = FakeOutputs();
        final starts = <double>[];
        final finishes = <(double, String)>[];
        final engine = CueEngine(out, onStart: (t, _) => starts.add(t), onFinish: (t, r) => finishes.add((t, r)));

        expect(engine.trigger(settings, 0).startedAt, 0);
        expect(starts, [0]);
        expect(out.haptic, 1);
        async.elapse(const Duration(milliseconds: 1999));
        // 120 BPM = um beat a cada 500 ms: t = 0, 500, 1000, 1500
        expect(out.haptic, 4);
        expect(out.audio, 4);
        async.elapse(const Duration(milliseconds: 1));
        expect(finishes.single, (2000.0, 'completed'));
        expect(engine.active, isFalse);
      }, initialTime: t0);
    });

    test('não sobrepõe cues e respeita o cooldown', () {
      fakeAsync((async) {
        final engine = CueEngine(FakeOutputs());
        engine.trigger(settings, 3000);
        expect(engine.trigger(settings, 3000).rejection, CueRejection.active);
        async.elapse(const Duration(seconds: 2));
        expect(engine.trigger(settings, 3000).rejection, CueRejection.cooldown);
        async.elapse(const Duration(seconds: 3));
        expect(engine.trigger(settings, 3000).started, isTrue);
        engine.stop();
      }, initialTime: t0);
    });

    test('respeita vibração/áudio desligados', () {
      fakeAsync((async) {
        final out = FakeOutputs();
        final engine = CueEngine(out);
        final off = settings.copyWith(hapticEnabled: false, audioEnabled: false);
        expect(engine.trigger(off, 0).rejection, CueRejection.disabled);
        engine.trigger(settings.copyWith(audioEnabled: false), 0);
        expect(out.haptic, 1);
        expect(out.audio, 0);
        engine.stop();
      }, initialTime: t0);
    });

    test('stop() encerra e para os beats', () {
      fakeAsync((async) {
        final out = FakeOutputs();
        final reasons = <String>[];
        final engine = CueEngine(out, onFinish: (_, r) => reasons.add(r));
        engine.trigger(settings, 0);
        engine.stop();
        expect(reasons, ['stopped']);
        async.elapse(const Duration(seconds: 5));
        expect(out.haptic, 1);
      }, initialTime: t0);
    });
  });
}

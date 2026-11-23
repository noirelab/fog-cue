import 'dart:async';

import '../config/experiment.dart';
import '../core/time.dart';

/// Saídas físicas. Implementadas em services/ (vibration e audioplayers).
abstract interface class CueOutputs {
  void hapticPulse();
  void audioClick();
}

enum CueRejection { active, cooldown, disabled }

class TriggerResult {
  const TriggerResult.started(double this.startedAt) : rejection = null;
  const TriggerResult.rejected(CueRejection this.rejection) : startedAt = null;

  final double? startedAt;
  final CueRejection? rejection;
  bool get started => rejection == null;
}

/// Regra de cooldown: um novo cue só começa se nenhum estiver tocando e se
/// já passaram [cooldownMs] desde o fim do anterior.
bool canStartCue({
  required bool active,
  required double? lastEndedAt,
  required double now,
  required int cooldownMs,
}) {
  if (active) return false;
  return lastEndedAt == null || now - lastEndedAt >= cooldownMs;
}

/// Toca um metrônomo (vibração e/ou clique) por durationSeconds, no ritmo de
/// bpm. Vibração e áudio saem do mesmo timer, então ficam sincronizados.
///
/// Limitação: o Timer do Dart tem jitter de alguns ms por beat; se o TCC
/// precisar de ritmo preciso, mover o metrônomo para código nativo.
class CueEngine {
  CueEngine(this._outputs, {this.onStart, this.onFinish});

  final CueOutputs _outputs;

  /// Chamado no primeiro beat, com o instante real de início.
  final void Function(double startedAt, CueSettings settings)? onStart;
  final void Function(double finishedAt, String reason)? onFinish;

  Timer? _beatTimer;
  Timer? _endTimer;
  double? _lastEndedAt;

  bool get active => _beatTimer != null;

  TriggerResult trigger(CueSettings settings, int cooldownMs) {
    if (!settings.hapticEnabled && !settings.audioEnabled) {
      return const TriggerResult.rejected(CueRejection.disabled);
    }
    if (active) return const TriggerResult.rejected(CueRejection.active);
    final now = nowMs();
    if (!canStartCue(active: false, lastEndedAt: _lastEndedAt, now: now, cooldownMs: cooldownMs)) {
      return const TriggerResult.rejected(CueRejection.cooldown);
    }

    void beat() {
      if (settings.hapticEnabled) _outputs.hapticPulse();
      if (settings.audioEnabled) _outputs.audioClick();
    }

    beat();
    _beatTimer = Timer.periodic(Duration(microseconds: (60e6 / settings.bpm).round()), (_) => beat());
    _endTimer = Timer(Duration(seconds: settings.durationSeconds), () => _finish('completed'));
    onStart?.call(now, settings);
    return TriggerResult.started(now);
  }

  void stop() {
    if (active) _finish('stopped');
  }

  void _finish(String reason) {
    _beatTimer?.cancel();
    _endTimer?.cancel();
    _beatTimer = null;
    _endTimer = null;
    final now = nowMs();
    _lastEndedAt = now;
    onFinish?.call(now, reason);
  }
}

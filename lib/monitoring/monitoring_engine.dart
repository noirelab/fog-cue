import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';

import '../config/experiment.dart';
import '../core/imu.dart';
import '../core/time.dart';
import '../cues/cue_engine.dart';
import '../fog/detectors.dart';
import '../fog/fog.dart';
import '../fog/state_machine.dart';
import '../sessions/models.dart';
import '../sessions/session_logger.dart';
import '../signal/circular_buffer.dart';
import '../signal/preprocessing.dart';
import '../signal/windower.dart';

/// Segundos de sinal mantidos para os gráficos da tela de monitoramento.
const displaySeconds = 5;

/// Etapas de pré-processamento aplicadas antes do detector. Vazio nesta versão.
const List<Preprocessor> _preprocessors = [];

class SessionInfo {
  const SessionInfo({required this.phonePlacement, this.participantId, this.notes});
  final String? participantId;
  final PhonePlacement phonePlacement;
  final String? notes;
}

/// Armazenamento da sessão. Em produção é o SQLite (services/database.dart).
abstract interface class SessionStore implements SessionSink {
  Future<void> createSession(Session session);
  Future<void> finishSession(String id, double endedAt);
}

/// Inicia a captura e devolve a função que a encerra.
typedef StartImu = void Function() Function(int sampleRateHz, void Function(ImuSample) onSample);

/// Dependências de plataforma, injetadas para o engine ser testável.
class EngineDeps {
  const EngineDeps({
    required this.startImu,
    required this.cueOutputs,
    required this.store,
    required this.appVersion,
    required this.platform,
  });

  final StartImu startImu;
  final CueOutputs cueOutputs;
  final SessionStore store;
  final String appVersion;
  final String platform;
}

class MonitoringSnapshot {
  const MonitoringSnapshot({
    required this.sessionId,
    required this.elapsedMs,
    required this.state,
    required this.confidence,
    required this.sampleCount,
    required this.measuredRateHz,
    required this.windowBufferSize,
    required this.windowsAnalyzed,
    required this.windowsSkipped,
    required this.lastSample,
    required this.lastInferenceMs,
    required this.processingLatencyMs,
    required this.cueLatencyMs,
    required this.cueActive,
    required this.detectorMetadata,
    required this.detectorErrors,
    required this.lastDetectorError,
    required this.eventCounts,
    required this.pendingWrites,
    required this.storageError,
  });

  final String sessionId;
  final double elapsedMs;
  final FogState state;
  final double confidence;
  final int sampleCount;
  final double measuredRateHz;
  final int windowBufferSize;
  final int windowsAnalyzed;
  final int windowsSkipped;
  final ImuSample? lastSample;

  /// Tempo gasto só no detector (pré-processamento + análise).
  final double? lastInferenceMs;

  /// Fim da janela no sensor até a decisão do detector.
  final double? processingLatencyMs;

  /// Fim da janela no sensor até o primeiro beat do cue.
  final double? cueLatencyMs;
  final bool cueActive;

  /// Valores calculados pelo detector na última janela (ex.: Freeze Index).
  final Map<String, Object?> detectorMetadata;
  final int detectorErrors;
  final String? lastDetectorError;
  final Map<SessionEventType, int> eventCounts;
  final int pendingWrites;
  final String? storageError;
}

String _newSessionId(DateTime t) {
  String p(int n) => n.toString().padLeft(2, '0');
  final rand = math.Random().nextInt(1 << 16).toRadixString(16).padLeft(4, '0');
  return '${t.year}${p(t.month)}${p(t.day)}-${p(t.hour)}${p(t.minute)}${p(t.second)}-$rand';
}

/// Orquestra uma sessão de monitoramento:
///
///   IMU -> Windower -> pré-processamento -> detector -> máquina de estados
///       -> Cue Engine
///   IMU -> SessionLogger -> SQLite (em paralelo, em lotes)
///
/// Latências (ms, relógio do sistema):
///   processingLatency = detectionTimestamp - sensorWindowEndTimestamp
///   cueLatency        = cueStartTimestamp  - sensorWindowEndTimestamp
/// No FoG simulado, a referência é o instante do toque no botão.
class MonitoringEngine {
  MonitoringEngine._(this.settings, SessionInfo info, this._deps) {
    _detector = createDetector(settings);
    _windower = Windower(windowSizeMs: settings.windowSizeMs.toDouble(), hopMs: settings.windowHopMs);
    _machine = FogStateMachine(confirmWindows: settings.confirmWindows, recoveryWindows: settings.recoveryWindows);
    _display = CircularBuffer(settings.sampleRateHz * displaySeconds);
    final startedAt = nowMs();
    session = Session(
      id: _newSessionId(clock.now()),
      participantId: info.participantId,
      phonePlacement: info.phonePlacement,
      notes: info.notes,
      startedAt: startedAt,
      metadata: SessionMetadata(
        sampleRate: settings.sampleRateHz,
        windowSize: settings.windowSizeMs,
        windowOverlap: settings.windowOverlap,
        detectorName: _detector.name,
        detectorVersion: _detector.version,
        cueSettings: settings.cue,
        appVersion: _deps.appVersion,
        platform: _deps.platform,
        settings: settings,
      ),
    );
    _logger = SessionLogger(session.id, _deps.store);
    _cue = CueEngine(
      _deps.cueOutputs,
      onStart: (startedAt, _) {
        final ref = _cueReference;
        _cueLatencyMs = ref == null ? null : startedAt - ref;
        _log(
          SessionEvent(
            timestamp: startedAt,
            type: SessionEventType.cueStarted,
            metadata: {'cueLatencyMs': _cueLatencyMs},
          ),
        );
      },
      onFinish: (finishedAt, reason) =>
          _log(SessionEvent(timestamp: finishedAt, type: SessionEventType.cueFinished, metadata: {'reason': reason})),
    );
  }

  final ExperimentSettings settings;
  final EngineDeps _deps;
  late final Session session;
  late final FogDetector _detector;
  late final Windower _windower;
  late final FogStateMachine _machine;
  late final CueEngine _cue;
  late final SessionLogger _logger;
  late final CircularBuffer<ImuSample> _display;

  void Function()? _stopImu;
  Timer? _flushTimer;
  bool _stopped = false;
  bool _analyzing = false;
  double? _cueReference;
  double? _episodeStartedAt;

  /// Timestamp da primeira amostra: referência do aquecimento.
  double? _firstSampleAt;
  int _sampleCount = 0;
  int _windowsAnalyzed = 0;
  int _windowsSkipped = 0;
  double _confidence = 0;
  double? _lastInferenceMs;
  double? _processingLatencyMs;
  double? _cueLatencyMs;
  Map<String, Object?> _detectorMetadata = const {};
  int _detectorErrors = 0;
  String? _lastDetectorError;
  final Map<SessionEventType, int> _eventCounts = {};

  /// Cria a sessão no banco e começa a coletar.
  static Future<MonitoringEngine> start(ExperimentSettings settings, SessionInfo info, EngineDeps deps) async {
    final engine = MonitoringEngine._(settings, info, deps);
    await deps.store.createSession(engine.session);
    engine._log(SessionEvent(timestamp: engine.session.startedAt, type: SessionEventType.sessionStarted));
    try {
      engine._stopImu = deps.startImu(settings.sampleRateHz, engine._onSample);
    } catch (_) {
      // Sem sensor não há sessão: fecha o registro já criado no banco.
      await engine.stop();
      rethrow;
    }
    engine._flushTimer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(engine._logger.flush()));
    return engine;
  }

  /// Encerra a coleta e grava tudo. Chamadas repetidas reaproveitam a mesma
  /// operação; se a gravação falhar, o erro chega a quem chamou e uma nova
  /// chamada tenta gravar de novo (os dados continuam em memória).
  Future<void> stop() => _stopping ??= _stop().catchError((Object error, StackTrace stack) {
    _stopping = null;
    return Future<void>.error(error, stack);
  });

  Future<void>? _stopping;
  double? _endedAt;

  Future<void> _stop() async {
    if (!_stopped) {
      _stopped = true;
      _stopImu?.call();
      _flushTimer?.cancel();
      _cue.stop();
      _endedAt = nowMs();
      _log(
        SessionEvent(
          timestamp: _endedAt!,
          type: SessionEventType.sessionFinished,
          metadata: {'samples': _sampleCount, 'detectorErrors': _detectorErrors},
        ),
      );
    }
    await _logger.flush();
    if (_logger.pending > 0) await _logger.flush();
    if (_logger.pending > 0) {
      throw StateError('Não foi possível gravar ${_logger.pending} registros: ${_logger.lastError}');
    }
    await _deps.store.finishSession(session.id, _endedAt!);
  }

  /// Força FOG_DETECTED (botão de debug). Passa pelo mesmo caminho do detector real.
  void simulateFog() {
    if (_stopped) return;
    _confidence = 1;
    _handleTransition(_machine.force(), nowMs(), {'simulated': true});
  }

  List<ImuSample> recentSamples() => _display.toList();

  MonitoringSnapshot snapshot() {
    final first = _display.first;
    final last = _display.last;
    final span = first != null && last != null ? last.timestamp - first.timestamp : 0.0;
    return MonitoringSnapshot(
      sessionId: session.id,
      elapsedMs: nowMs() - session.startedAt,
      state: _machine.state,
      confidence: _confidence,
      sampleCount: _sampleCount,
      measuredRateHz: span > 0 ? (_display.length - 1) * 1000 / span : 0,
      windowBufferSize: _windower.bufferSize,
      windowsAnalyzed: _windowsAnalyzed,
      windowsSkipped: _windowsSkipped,
      lastSample: last,
      lastInferenceMs: _lastInferenceMs,
      processingLatencyMs: _processingLatencyMs,
      cueLatencyMs: _cueLatencyMs,
      cueActive: _cue.active,
      detectorMetadata: _detectorMetadata,
      detectorErrors: _detectorErrors,
      lastDetectorError: _lastDetectorError,
      eventCounts: Map.unmodifiable(_eventCounts),
      pendingWrites: _logger.pending,
      storageError: _logger.lastError?.toString(),
    );
  }

  void _onSample(ImuSample s) {
    if (_stopped) return;
    _firstSampleAt ??= s.timestamp;
    _sampleCount++;
    _display.push(s);
    _logger.logSample(
      SampleRecord(
        timestamp: s.timestamp,
        accX: s.accelerometer.x,
        accY: s.accelerometer.y,
        accZ: s.accelerometer.z,
        accMagnitude: magnitude(s.accelerometer),
        gyroX: s.gyroscope.x,
        gyroY: s.gyroscope.y,
        gyroZ: s.gyroscope.z,
        fogState: _machine.state,
        fogConfidence: _confidence,
        cueTriggered: _cue.active,
      ),
    );
    final window = _windower.push(s);
    if (window != null) unawaited(_analyze(window));
  }

  Future<void> _analyze(SignalWindow window) async {
    // Se o detector ainda está ocupado com a janela anterior, esta é
    // descartada (e contada) em vez de acumular atraso.
    if (_analyzing) {
      _windowsSkipped++;
      return;
    }
    _analyzing = true;
    try {
      final t0 = nowMs();
      final result = await _detector.analyze(preprocess(window, _preprocessors));
      final detectedAt = nowMs();
      if (_stopped) return;
      _windowsAnalyzed++;
      _lastInferenceMs = detectedAt - t0;
      _processingLatencyMs = detectedAt - window.endTimestamp;
      _confidence = result.confidence;
      _detectorMetadata = result.metadata;
      // Janelas que começam no aquecimento (guardar o celular no bolso
      // sacode o aparelho) não contam como detecção.
      final warmupEnd = (_firstSampleAt ?? window.startTimestamp) + settings.warmupSeconds * 1000;
      final detected = result.detected && window.startTimestamp >= warmupEnd;
      _handleTransition(_machine.update(detected), window.endTimestamp, {
        ...result.metadata,
        'confidence': result.confidence,
        'processingLatencyMs': _processingLatencyMs,
        'inferenceMs': _lastInferenceMs,
        'windowStart': window.startTimestamp,
        'windowEnd': window.endTimestamp,
      });
    } catch (error) {
      // Um erro do detector não pode derrubar a coleta. Fica contado (e vai
      // no evento SESSION_FINISHED), sem virar um falso evento de FoG.
      if (!_stopped) {
        _detectorErrors++;
        _lastDetectorError = '$error';
      }
    } finally {
      _analyzing = false;
    }
  }

  void _handleTransition(Transition tr, double reference, Map<String, Object?> metadata) {
    final now = nowMs();
    if (tr.changed) {
      switch (tr.to) {
        case FogState.possibleFog:
          _log(SessionEvent(timestamp: now, type: SessionEventType.fogPossible, metadata: metadata));
        case FogState.fogDetected:
          if (tr.from != FogState.recovery) _episodeStartedAt = now;
          _log(
            SessionEvent(
              timestamp: now,
              type: SessionEventType.fogDetected,
              metadata: {...metadata, 'from': tr.from.code},
            ),
          );
        case FogState.recovery:
          final start = _episodeStartedAt;
          _log(
            SessionEvent(
              timestamp: now,
              type: SessionEventType.recovery,
              metadata: {...metadata, 'episodeDurationMs': start == null ? null : now - start},
            ),
          );
        case FogState.normal:
          break;
      }
    }
    // Enquanto o estado for FOG_DETECTED, tenta disparar o cue; o cooldown e
    // o "já está tocando" do CueEngine evitam cues em sequência.
    if (tr.to == FogState.fogDetected) {
      _cueReference = reference;
      _cue.trigger(settings.cue, settings.cueCooldownMs);
    }
  }

  void _log(SessionEvent event) {
    _eventCounts.update(event.type, (n) => n + 1, ifAbsent: () => 1);
    _logger.logEvent(event);
  }
}

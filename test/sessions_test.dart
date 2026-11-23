import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fog_cue/config/experiment.dart';
import 'package:fog_cue/fog/fog.dart';
import 'package:fog_cue/sessions/csv.dart';
import 'package:fog_cue/sessions/models.dart';
import 'package:fog_cue/sessions/session_logger.dart';

const row = SampleRecord(
  timestamp: 1759700000000.5,
  accX: 0.01,
  accY: -9.8,
  accZ: 0.12,
  accMagnitude: 9.81,
  gyroX: 0.002,
  gyroY: 0.01,
  gyroZ: -0.003,
  fogState: FogState.normal,
  fogConfidence: 0,
  cueTriggered: false,
);

SampleRecord withNaN() => const SampleRecord(
      timestamp: 1,
      accX: 0,
      accY: 0,
      accZ: 0,
      accMagnitude: 0,
      gyroX: double.nan,
      gyroY: double.nan,
      gyroZ: double.nan,
      fogState: FogState.fogDetected,
      fogConfidence: double.nan,
      cueTriggered: true,
    );

class MemorySink implements SessionSink {
  final sampleBatches = <int>[];
  final eventBatches = <int>[];
  bool failSamples = false;

  @override
  Future<void> insertSamples(String sessionId, List<SampleRecord> rows) async {
    if (failSamples) throw StateError('disco');
    sampleBatches.add(rows.length);
  }

  @override
  Future<void> insertEvents(String sessionId, List<SessionEvent> events) async => eventBatches.add(events.length);
}

void main() {
  group('exportação CSV/JSON', () {
    test('cabeçalho e linhas no formato esperado pelo pandas', () {
      final lines = samplesToCsv([row, withNaN()]).trimRight().split('\n');
      expect(lines[0], 'timestamp,acc_x,acc_y,acc_z,acc_magnitude,gyro_x,gyro_y,gyro_z,fog_state,fog_confidence,cue_triggered');
      expect(lines[1], '1759700000000.5,0.01,-9.8,0.12,9.81,0.002,0.01,-0.003,NORMAL,0.0,0');
      // NaN vira campo vazio
      expect(lines[2], '1.0,0.0,0.0,0.0,0.0,,,,FOG_DETECTED,,1');
    });

    test('escapa o JSON de metadata dos eventos e troca NaN por null', () {
      final csv = eventsToCsv(const [
        SessionEvent(timestamp: 10, type: SessionEventType.fogDetected, metadata: {'confidence': 0.8, 'note': 'a,"b"'}),
        SessionEvent(timestamp: 20, type: SessionEventType.sessionFinished, metadata: {'x': double.nan}),
      ]);
      expect(
        csv,
        'timestamp,type,metadata\n'
        '10.0,FOG_DETECTED,"{""confidence"":0.8,""note"":""a,\\""b\\""""}"\n'
        '20.0,SESSION_FINISHED,"{""x"":null}"\n',
      );
    });

    test('JSON de metadados contém os parâmetros experimentais', () {
      const session = Session(
        id: 's1',
        startedAt: 1,
        phonePlacement: PhonePlacement.pocket,
        metadata: SessionMetadata(
          sampleRate: 50,
          windowSize: 2000,
          windowOverlap: 0.5,
          detectorName: 'MockFogDetector',
          detectorVersion: '0.1.0',
          cueSettings: CueSettings(hapticEnabled: true, audioEnabled: true, bpm: 100, durationSeconds: 10),
          appVersion: '0.1.0',
          platform: 'android',
          settings: defaultSettings,
        ),
      );
      final parsed = jsonDecode(sessionToJson(session, samples: 3, events: 2)) as Map<String, Object?>;
      final meta = parsed['metadata'] as Map<String, Object?>;
      expect(meta['sampleRate'], 50);
      expect(meta['detectorName'], 'MockFogDetector');
      expect(parsed['counts'], {'samples': 3, 'events': 2});
      expect(SessionMetadata.fromJson(meta).cueSettings.bpm, 100);
    });
  });

  group('SessionLogger', () {
    test('grava em lotes ao atingir o limite e no flush manual', () async {
      final sink = MemorySink();
      final logger = SessionLogger('s1', sink, maxBuffered: 3);
      logger.logEvent(const SessionEvent(timestamp: 0, type: SessionEventType.sessionStarted));
      for (var i = 0; i < 4; i++) {
        logger.logSample(row);
      }
      await logger.flush();
      expect(sink.sampleBatches, [3, 1]);
      expect(sink.eventBatches, [1]);
      expect(logger.writtenSamples, 4);
      expect(logger.pending, 0);
    });

    test('não perde linhas se a escrita falhar', () async {
      final sink = MemorySink()..failSamples = true;
      final logger = SessionLogger('s1', sink);
      logger.logSample(row);
      await logger.flush();
      expect(logger.pending, 1);
      expect(logger.lastError, isA<StateError>());
      sink.failSamples = false;
      await logger.flush();
      expect(logger.pending, 0);
      expect(logger.writtenSamples, 1);
    });
  });

  group('configurações', () {
    test('padrões são válidos e o passo respeita a sobreposição', () {
      expect(validateSettings(defaultSettings), isEmpty);
      expect(defaultSettings.windowHopMs, 1000);
    });

    test('rejeita valores absurdos', () {
      final errors = validateSettings(defaultSettings.copyWith(
        sampleRateHz: 1000,
        windowOverlap: 1,
        cue: defaultSettings.cue.copyWith(bpm: 500),
      ));
      expect(errors.keys.toSet(), {SettingKey.sampleRateHz, SettingKey.windowOverlap, SettingKey.bpm});
    });

    test('fromJson completa campos ausentes e descarta inválidos', () {
      expect(ExperimentSettings.fromJson({'sampleRateHz': 60}).sampleRateHz, 60);
      expect(ExperimentSettings.fromJson({'cue': {'bpm': 90}}).cue.bpm, 90);
      expect(ExperimentSettings.fromJson({'fogThreshold': 4}).fogThreshold, 4.0);
      expect(identical(ExperimentSettings.fromJson({'sampleRateHz': 99999}), defaultSettings), isTrue);
      expect(identical(ExperimentSettings.fromJson('lixo'), defaultSettings), isTrue);
      final roundTrip = ExperimentSettings.fromJson(jsonDecode(jsonEncode(defaultSettings.toJson())));
      expect(roundTrip.toJson(), defaultSettings.toJson());
    });
  });
}

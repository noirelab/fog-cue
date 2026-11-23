import '../config/experiment.dart';
import '../fog/fog.dart';

enum PhonePlacement {
  pocket('Bolso'),
  waist('Cintura'),
  hand('Mão'),
  other('Outra');

  const PhonePlacement(this.label);
  final String label;
}

/// Tudo o que é preciso para reproduzir as condições do experimento.
class SessionMetadata {
  const SessionMetadata({
    required this.sampleRate,
    required this.windowSize,
    required this.windowOverlap,
    required this.detectorName,
    required this.detectorVersion,
    required this.cueSettings,
    required this.appVersion,
    required this.platform,
    required this.settings,
  });

  final int sampleRate;
  final int windowSize;
  final double windowOverlap;
  final String detectorName;
  final String detectorVersion;
  final CueSettings cueSettings;
  final String appVersion;
  final String platform;
  final ExperimentSettings settings;

  Map<String, Object?> toJson() => {
        'sampleRate': sampleRate,
        'windowSize': windowSize,
        'windowOverlap': windowOverlap,
        'detectorName': detectorName,
        'detectorVersion': detectorVersion,
        'cueSettings': cueSettings.toJson(),
        'appVersion': appVersion,
        'platform': platform,
        'settings': settings.toJson(),
      };

  static SessionMetadata fromJson(Map<String, Object?> json) {
    final settings = ExperimentSettings.fromJson(json['settings']);
    return SessionMetadata(
      sampleRate: jsonInt(json, 'sampleRate', settings.sampleRateHz),
      windowSize: jsonInt(json, 'windowSize', settings.windowSizeMs),
      windowOverlap: jsonDouble(json, 'windowOverlap', settings.windowOverlap),
      detectorName: jsonString(json, 'detectorName', '?'),
      detectorVersion: jsonString(json, 'detectorVersion', '?'),
      cueSettings: CueSettings.fromJson(json['cueSettings'], settings.cue),
      appVersion: jsonString(json, 'appVersion', '?'),
      platform: jsonString(json, 'platform', '?'),
      settings: settings,
    );
  }
}

class Session {
  const Session({
    required this.id,
    required this.startedAt,
    required this.phonePlacement,
    required this.metadata,
    this.participantId,
    this.endedAt,
    this.notes,
  });

  final String id;
  final String? participantId;

  /// ms Unix.
  final double startedAt;
  final double? endedAt;
  final PhonePlacement phonePlacement;
  final String? notes;
  final SessionMetadata metadata;

  Map<String, Object?> toJson() => {
        'id': id,
        'participantId': participantId,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'phonePlacement': phonePlacement.name,
        'notes': notes,
        'metadata': metadata.toJson(),
      };
}

/// Uma linha do CSV de amostras. A ordem de [toRow] segue [sampleColumns].
class SampleRecord {
  const SampleRecord({
    required this.timestamp,
    required this.accX,
    required this.accY,
    required this.accZ,
    required this.accMagnitude,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.fogState,
    required this.fogConfidence,
    required this.cueTriggered,
  });

  final double timestamp;
  final double accX;
  final double accY;
  final double accZ;
  final double accMagnitude;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final FogState fogState;
  final double fogConfidence;

  /// true enquanto um cue está tocando nesta amostra.
  final bool cueTriggered;

  List<Object> toRow() => [
        timestamp,
        accX,
        accY,
        accZ,
        accMagnitude,
        gyroX,
        gyroY,
        gyroZ,
        fogState.code,
        fogConfidence,
        cueTriggered ? 1 : 0,
      ];
}

const sampleColumns = [
  'timestamp',
  'acc_x',
  'acc_y',
  'acc_z',
  'acc_magnitude',
  'gyro_x',
  'gyro_y',
  'gyro_z',
  'fog_state',
  'fog_confidence',
  'cue_triggered',
];

enum SessionEventType {
  sessionStarted('SESSION_STARTED'),
  sessionFinished('SESSION_FINISHED'),
  fogPossible('FOG_POSSIBLE'),
  fogDetected('FOG_DETECTED'),
  cueStarted('CUE_STARTED'),
  cueFinished('CUE_FINISHED'),
  recovery('RECOVERY');

  const SessionEventType(this.code);
  final String code;

  static SessionEventType? fromCode(String code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

class SessionEvent {
  const SessionEvent({required this.timestamp, required this.type, this.metadata = const {}});

  final double timestamp;
  final SessionEventType type;
  final Map<String, Object?> metadata;
}

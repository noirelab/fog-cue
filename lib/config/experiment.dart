/// Parâmetros experimentais centralizados.
///
/// Nenhum outro módulo tem esses valores fixos no código: todos recebem um
/// [ExperimentSettings]. Os valores são gravados junto de cada sessão para
/// permitir reproduzir o experimento depois.
library;

enum DetectorName { mock, heuristic, freezeIndex }

/// Bandas do Freeze Index em Hz (Moore et al., 2008; Bächlin et al., 2010):
/// a caminhada concentra energia na banda locomotora; o tremor do
/// congelamento, na banda de freeze.
const locomotorBandHz = (0.5, 3.0);
const freezeBandHz = (3.0, 8.0);

class CueSettings {
  const CueSettings({
    required this.hapticEnabled,
    required this.audioEnabled,
    required this.bpm,
    required this.durationSeconds,
  });

  final bool hapticEnabled;
  final bool audioEnabled;
  final int bpm;
  final int durationSeconds;

  CueSettings copyWith({bool? hapticEnabled, bool? audioEnabled, int? bpm, int? durationSeconds}) => CueSettings(
    hapticEnabled: hapticEnabled ?? this.hapticEnabled,
    audioEnabled: audioEnabled ?? this.audioEnabled,
    bpm: bpm ?? this.bpm,
    durationSeconds: durationSeconds ?? this.durationSeconds,
  );

  Map<String, Object?> toJson() => {
    'hapticEnabled': hapticEnabled,
    'audioEnabled': audioEnabled,
    'bpm': bpm,
    'durationSeconds': durationSeconds,
  };

  static CueSettings fromJson(Object? json, CueSettings fallback) {
    if (json is! Map<String, Object?>) return fallback;
    return CueSettings(
      hapticEnabled: jsonBool(json, 'hapticEnabled', fallback.hapticEnabled),
      audioEnabled: jsonBool(json, 'audioEnabled', fallback.audioEnabled),
      bpm: jsonInt(json, 'bpm', fallback.bpm),
      durationSeconds: jsonInt(json, 'durationSeconds', fallback.durationSeconds),
    );
  }
}

class ExperimentSettings {
  const ExperimentSettings({
    required this.sampleRateHz,
    required this.windowSizeMs,
    required this.windowOverlap,
    required this.fogThreshold,
    required this.freezeIndexThreshold,
    required this.powerThreshold,
    required this.cueCooldownMs,
    required this.confirmWindows,
    required this.recoveryWindows,
    required this.detector,
    required this.cue,
    required this.researchMode,
    required this.warmupSeconds,
  });

  /// SAMPLE_RATE_HZ: frequência pedida aos sensores. A real pode variar.
  final int sampleRateHz;

  /// WINDOW_SIZE_MS: duração de cada janela analisada pelo detector.
  final int windowSizeMs;

  /// WINDOW_OVERLAP: fração de sobreposição entre janelas (0 = nenhuma).
  final double windowOverlap;

  /// FOG_THRESHOLD do detector heurístico: desvio padrão da magnitude (m/s²).
  final double fogThreshold;

  /// Freeze Index acima do qual a janela conta como congelamento.
  final double freezeIndexThreshold;

  /// Energia mínima (m/s²)² entre 0,5 e 8 Hz para considerar que há
  /// movimento. Abaixo disso a pessoa está parada, não congelada.
  final double powerThreshold;

  /// CUE_COOLDOWN: tempo mínimo (ms) entre o fim de um cue e o início do próximo.
  final int cueCooldownMs;

  /// Janelas positivas consecutivas para confirmar FOG_DETECTED.
  final int confirmWindows;

  /// Janelas negativas consecutivas em RECOVERY para voltar a NORMAL.
  final int recoveryWindows;

  final DetectorName detector;
  final CueSettings cue;

  /// Ligado: telas completas do pesquisador (gráficos, métricas, histórico,
  /// "Simular FoG"). Desligado: modo simples para o participante.
  final bool researchMode;

  /// Segundos iniciais da sessão sem detecção: tempo de guardar o celular no
  /// bolso, que sacode o aparelho e parece congelamento. Janelas que começam
  /// antes disso não contam.
  final int warmupSeconds;

  /// Passo entre o início de janelas consecutivas.
  double get windowHopMs => windowSizeMs * (1 - windowOverlap);

  ExperimentSettings copyWith({
    int? sampleRateHz,
    int? windowSizeMs,
    double? windowOverlap,
    double? fogThreshold,
    double? freezeIndexThreshold,
    double? powerThreshold,
    int? cueCooldownMs,
    int? confirmWindows,
    int? recoveryWindows,
    DetectorName? detector,
    CueSettings? cue,
    bool? researchMode,
    int? warmupSeconds,
  }) => ExperimentSettings(
    sampleRateHz: sampleRateHz ?? this.sampleRateHz,
    windowSizeMs: windowSizeMs ?? this.windowSizeMs,
    windowOverlap: windowOverlap ?? this.windowOverlap,
    fogThreshold: fogThreshold ?? this.fogThreshold,
    freezeIndexThreshold: freezeIndexThreshold ?? this.freezeIndexThreshold,
    powerThreshold: powerThreshold ?? this.powerThreshold,
    cueCooldownMs: cueCooldownMs ?? this.cueCooldownMs,
    confirmWindows: confirmWindows ?? this.confirmWindows,
    recoveryWindows: recoveryWindows ?? this.recoveryWindows,
    detector: detector ?? this.detector,
    cue: cue ?? this.cue,
    researchMode: researchMode ?? this.researchMode,
    warmupSeconds: warmupSeconds ?? this.warmupSeconds,
  );

  Map<String, Object?> toJson() => {
    'sampleRateHz': sampleRateHz,
    'windowSizeMs': windowSizeMs,
    'windowOverlap': windowOverlap,
    'fogThreshold': fogThreshold,
    'freezeIndexThreshold': freezeIndexThreshold,
    'powerThreshold': powerThreshold,
    'cueCooldownMs': cueCooldownMs,
    'confirmWindows': confirmWindows,
    'recoveryWindows': recoveryWindows,
    'detector': detector.name,
    'cue': cue.toJson(),
    'researchMode': researchMode,
    'warmupSeconds': warmupSeconds,
  };

  /// Lê um JSON salvo (talvez de uma versão antiga do app), completando com
  /// os padrões. Se o resultado for inválido, devolve os padrões.
  static ExperimentSettings fromJson(Object? json) {
    if (json is! Map<String, Object?>) return defaultSettings;
    const d = defaultSettings;
    final s = ExperimentSettings(
      sampleRateHz: jsonInt(json, 'sampleRateHz', d.sampleRateHz),
      windowSizeMs: jsonInt(json, 'windowSizeMs', d.windowSizeMs),
      windowOverlap: jsonDouble(json, 'windowOverlap', d.windowOverlap),
      fogThreshold: jsonDouble(json, 'fogThreshold', d.fogThreshold),
      freezeIndexThreshold: jsonDouble(json, 'freezeIndexThreshold', d.freezeIndexThreshold),
      powerThreshold: jsonDouble(json, 'powerThreshold', d.powerThreshold),
      cueCooldownMs: jsonInt(json, 'cueCooldownMs', d.cueCooldownMs),
      confirmWindows: jsonInt(json, 'confirmWindows', d.confirmWindows),
      recoveryWindows: jsonInt(json, 'recoveryWindows', d.recoveryWindows),
      detector: DetectorName.values.asNameMap()[json['detector']] ?? d.detector,
      cue: CueSettings.fromJson(json['cue'], d.cue),
      researchMode: jsonBool(json, 'researchMode', d.researchMode),
      warmupSeconds: jsonInt(json, 'warmupSeconds', d.warmupSeconds),
    );
    return validateSettings(s).isEmpty ? s : defaultSettings;
  }
}

/// Padrões. Janela de 4 s com novo resultado a cada 1 s e Freeze Index com
/// energia mínima de 0,5, escolhidos por scripts/calibrar_detectores.py: no
/// Daphnet (coxa) deram sensibilidade por episódio de 0,31 e 0,35 falso
/// alarme por minuto de caminhada sem freeze, e nenhum alarme numa caminhada normal com o celular no
/// bolso. O heurístico (desvio padrão) dispara com a caminhada comum e fica
/// só como referência. São valores de partida, não validados clinicamente.
const defaultSettings = ExperimentSettings(
  sampleRateHz: 50,
  windowSizeMs: 4000,
  windowOverlap: 0.75,
  fogThreshold: 3.5,
  freezeIndexThreshold: 2.0,
  powerThreshold: 0.5,
  cueCooldownMs: 5000,
  confirmWindows: 2,
  recoveryWindows: 2,
  detector: DetectorName.freezeIndex,
  cue: CueSettings(hapticEnabled: true, audioEnabled: true, bpm: 100, durationSeconds: 10),
  researchMode: false,
  warmupSeconds: 15,
);

/// Campos numéricos editáveis, usados na validação e na tela de configurações.
enum SettingKey {
  sampleRateHz,
  windowSizeMs,
  windowOverlap,
  fogThreshold,
  freezeIndexThreshold,
  powerThreshold,
  cueCooldownMs,
  confirmWindows,
  recoveryWindows,
  bpm,
  durationSeconds,
  warmupSeconds,
}

class Limit {
  const Limit(this.min, this.max);
  final num min;
  final num max;
}

/// Limites aceitos. Mínimo de 20 Hz para cobrir a banda de freeze (até 8 Hz,
/// Nyquist de 10 Hz); máximo de 100 Hz (Android 12+ limita a 200 Hz sem
/// permissão extra).
const limits = <SettingKey, Limit>{
  SettingKey.sampleRateHz: Limit(20, 100),
  SettingKey.windowSizeMs: Limit(500, 10000),
  SettingKey.windowOverlap: Limit(0, 0.9),
  SettingKey.fogThreshold: Limit(0.1, 50),
  SettingKey.freezeIndexThreshold: Limit(0.5, 20),
  SettingKey.powerThreshold: Limit(0.001, 50),
  SettingKey.cueCooldownMs: Limit(0, 60000),
  SettingKey.confirmWindows: Limit(1, 10),
  SettingKey.recoveryWindows: Limit(1, 20),
  SettingKey.bpm: Limit(40, 180),
  SettingKey.durationSeconds: Limit(1, 60),
  SettingKey.warmupSeconds: Limit(0, 60),
};

Map<SettingKey, num> numericValues(ExperimentSettings s) => {
  SettingKey.sampleRateHz: s.sampleRateHz,
  SettingKey.windowSizeMs: s.windowSizeMs,
  SettingKey.windowOverlap: s.windowOverlap,
  SettingKey.fogThreshold: s.fogThreshold,
  SettingKey.freezeIndexThreshold: s.freezeIndexThreshold,
  SettingKey.powerThreshold: s.powerThreshold,
  SettingKey.cueCooldownMs: s.cueCooldownMs,
  SettingKey.confirmWindows: s.confirmWindows,
  SettingKey.recoveryWindows: s.recoveryWindows,
  SettingKey.bpm: s.cue.bpm,
  SettingKey.durationSeconds: s.cue.durationSeconds,
  SettingKey.warmupSeconds: s.warmupSeconds,
};

/// Devolve um mapa vazio quando tudo é válido.
Map<SettingKey, String> validateSettings(ExperimentSettings s) {
  final errors = <SettingKey, String>{};
  numericValues(s).forEach((key, value) {
    final limit = limits[key]!;
    if (!value.isFinite || value < limit.min || value > limit.max) {
      errors[key] = 'Use um valor entre ${limit.min} e ${limit.max}.';
    }
  });
  return errors;
}

// Leitura tolerante de JSON: tipo errado ou ausente vira o valor padrão.

int jsonInt(Map<String, Object?> json, String key, int fallback) => switch (json[key]) {
  final int v => v,
  _ => fallback,
};

double jsonDouble(Map<String, Object?> json, String key, double fallback) => switch (json[key]) {
  final num v => v.toDouble(),
  _ => fallback,
};

bool jsonBool(Map<String, Object?> json, String key, bool fallback) => switch (json[key]) {
  final bool v => v,
  _ => fallback,
};

String jsonString(Map<String, Object?> json, String key, String fallback) => switch (json[key]) {
  final String v => v,
  _ => fallback,
};

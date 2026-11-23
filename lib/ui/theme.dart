import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../fog/fog.dart';

/// Tokens visuais. Neutros quentes com um único acento teal; as cores fortes
/// ficam reservadas aos estados do detector para que eles se destaquem.
class Palette {
  const Palette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.chartX,
    required this.chartY,
    required this.chartZ,
    required this.chartMag,
    required this.grid,
    required this.state,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color border;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color onAccent;
  final Color danger;
  final Color chartX;
  final Color chartY;
  final Color chartZ;
  final Color chartMag;
  final Color grid;

  /// (texto, fundo) de cada estado do detector.
  final Map<FogState, (Color, Color)> state;

  static const light = Palette(
    brightness: Brightness.light,
    bg: Color(0xFFF4F5F2),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFECEEEA),
    border: Color(0xFFDFE2DC),
    text: Color(0xFF15191C),
    textMuted: Color(0xFF5A6368),
    accent: Color(0xFF0F766E),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFB42318),
    chartX: Color(0xFFC2410C),
    chartY: Color(0xFF0F766E),
    chartZ: Color(0xFF4338CA),
    chartMag: Color(0xFF15191C),
    grid: Color(0xFFE4E7E1),
    state: {
      FogState.normal: (Color(0xFF166534), Color(0xFFE3F2E6)),
      FogState.possibleFog: (Color(0xFF92400E), Color(0xFFFBEFD9)),
      FogState.fogDetected: (Color(0xFFFFFFFF), Color(0xFFB42318)),
      FogState.recovery: (Color(0xFF1E40AF), Color(0xFFE2E9FA)),
    },
  );

  static const dark = Palette(
    brightness: Brightness.dark,
    bg: Color(0xFF0E1113),
    surface: Color(0xFF171B1E),
    surfaceAlt: Color(0xFF20262A),
    border: Color(0xFF2A3135),
    text: Color(0xFFECEFF0),
    textMuted: Color(0xFF9BA5AA),
    accent: Color(0xFF2BB3A5),
    onAccent: Color(0xFF04201D),
    danger: Color(0xFFF2735F),
    chartX: Color(0xFFFB923C),
    chartY: Color(0xFF2DD4BF),
    chartZ: Color(0xFFA5B4FC),
    chartMag: Color(0xFFECEFF0),
    grid: Color(0xFF262C30),
    state: {
      FogState.normal: (Color(0xFF86EFAC), Color(0xFF13291B)),
      FogState.possibleFog: (Color(0xFFFCD34D), Color(0xFF33260E)),
      FogState.fogDetected: (Color(0xFFFFFFFF), Color(0xFFC2341F)),
      FogState.recovery: (Color(0xFFA5C0FF), Color(0xFF16213D)),
    },
  );

  /// (texto, fundo) do painel de monitoramento. "Sem sinal" reusa o âmbar de
  /// alerta e o cue ativo reusa o vermelho do FoG; o ícone e o texto os separam.
  (Color, Color) statusColors(MonitorStatus s) => switch (s) {
    MonitorStatus.starting => (text, surfaceAlt),
    MonitorStatus.noSignal => state[FogState.possibleFog]!,
    MonitorStatus.normal => state[FogState.normal]!,
    MonitorStatus.possibleFog => state[FogState.possibleFog]!,
    MonitorStatus.fogDetected || MonitorStatus.cueActive => state[FogState.fogDetected]!,
    MonitorStatus.recovery => state[FogState.recovery]!,
  };

  static Palette of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Palette p) {
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: p.brightness).copyWith(
    primary: p.accent,
    onPrimary: p.onAccent,
    surface: p.surface,
    onSurface: p.text,
    error: p.danger,
    outline: p.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 0.5, space: 0.5),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceAlt,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: p.danger),
      ),
      hintStyle: TextStyle(color: p.textMuted),
      helperStyle: TextStyle(color: p.textMuted),
    ),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.accent, selectionHandleColor: p.accent),
  );
}

/// O que o painel de monitoramento mostra. Além dos estados do detector,
/// cobre os casos sem leitura confiável, para nunca exibir "Normal" sem dados.
/// Cada estado tem ícone e texto próprios, não só cor.
enum MonitorStatus {
  starting('Iniciando', 'Ligando os sensores', 'Preparando', 'Aguarde um instante', LucideIcons.hourglass),
  noSignal(
    'Sensor sem sinal',
    'Nenhuma leitura há mais de 2 s. A detecção está parada.',
    'O celular parou de medir',
    'Pare a caminhada e comece de novo',
    LucideIcons.unplug,
  ),
  normal('Normal', 'Nenhum episódio em andamento', 'Tudo certo', 'Pode caminhar normalmente', LucideIcons.circleCheck),
  possibleFog(
    'Possível FoG',
    'Aguardando confirmação nas próximas janelas',
    'Tudo certo',
    'Pode caminhar normalmente',
    LucideIcons.triangleAlert,
  ),
  fogDetected(
    'FoG detectado',
    'Episódio confirmado',
    'Pare e respire',
    'Depois dê um passo grande',
    LucideIcons.circleAlert,
  ),
  recovery('Recuperação', 'Sinal voltando ao normal', 'Muito bem', 'Continue caminhando', LucideIcons.rotateCcw),
  cueActive('Cue ativo', 'Siga o ritmo', 'Siga o ritmo', 'Dê um passo a cada batida', LucideIcons.audioLines);

  const MonitorStatus(this.title, this.hint, this.plainTitle, this.plainHint, this.icon);

  /// Textos do modo pesquisa.
  final String title;
  final String hint;

  /// Textos do modo simples, para o participante: sem jargão.
  final String plainTitle;
  final String plainHint;
  final IconData icon;

  /// No modo simples, "possível FoG" aparece como normal: é um estado de
  /// espera do detector, e avisar a pessoa a cada suspeita só assusta.
  MonitorStatus forParticipant() => this == possibleFog ? normal : this;

  /// [state] nulo significa que nenhuma amostra chegou ainda. Sensor parado
  /// vem antes de tudo: com ele, o resto do painel não é confiável.
  static MonitorStatus from({required FogState? state, required bool cueActive, required bool sensorStale}) {
    if (sensorStale) return noSignal;
    if (state == null) return starting;
    if (cueActive) return MonitorStatus.cueActive;
    return switch (state) {
      FogState.normal => normal,
      FogState.possibleFog => possibleFog,
      FogState.fogDetected => fogDetected,
      FogState.recovery => recovery,
    };
  }
}

/// Números com largura fixa, para valores que mudam ao vivo não "tremerem".
const tabular = [FontFeature.tabularFigures()];

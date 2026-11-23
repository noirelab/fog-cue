import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_settings.dart';
import '../fog/detectors.dart';
import '../fog/fog.dart';
import '../monitoring/monitoring_engine.dart';
import '../services/imu_service.dart';
import '../sessions/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'history_screen.dart';
import 'monitor_screen.dart';
import 'new_session_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Future<ImuAvailability> _imu = checkImuAvailability();

  void _open(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  /// O participante não escolhe nada antes de caminhar: celular no bolso.
  void _startWalk() {
    final settings = SettingsScope.of(context).settings;
    _open(
      MonitorScreen(
        settings: settings,
        info: const SessionInfo(phonePlacement: PhonePlacement.pocket),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = SettingsScope.of(context).settings;
    return s.researchMode ? _buildResearch(context) : _buildSimple(context);
  }

  /// Tela inicial do participante: uma frase, uma ação. O acesso do
  /// pesquisador fica atrás de um toque longo, para não mudar nada sem querer.
  Widget _buildSimple(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<ImuAvailability>(
          future: _imu,
          builder: (context, snap) {
            final imu = snap.data;
            final ready = imu?.accelerometer ?? false;
            final title = imu == null
                ? 'Verificando o celular'
                : ready
                ? 'Pronto para caminhar'
                : 'Este celular não consegue medir os passos';
            return ScreenBody(
              footer: AppButton(
                label: 'Começar caminhada',
                icon: LucideIcons.footprints,
                large: true,
                onPressed: ready ? _startWalk : null,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Text(
                    title,
                    style: TextStyle(color: p.text, fontSize: 34, fontWeight: FontWeight.w700, height: 1.2),
                  ),
                ),
                Text(
                  'Guarde o celular no bolso da calça. Se você travar ao caminhar, ele vibra e toca um ritmo '
                  'para ajudar no próximo passo.',
                  style: TextStyle(color: p.text, fontSize: 20, height: 1.5),
                ),
                const Muted('Este aplicativo é um projeto de pesquisa e não substitui o seu médico.'),
                GestureDetector(
                  onLongPress: () => _open(const SettingsScreen()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Área do pesquisador (toque e segure)',
                      style: TextStyle(color: p.textMuted, fontSize: 14),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildResearch(BuildContext context) {
    final p = Palette.of(context);
    final s = SettingsScope.of(context).settings;
    final cues = [if (s.cue.hapticEnabled) 'vibração', if (s.cue.audioEnabled) 'áudio'].join(' + ');

    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<ImuAvailability>(
          future: _imu,
          builder: (context, snap) {
            final imu = snap.data;
            final ready = imu?.accelerometer ?? false;
            String sensorText(bool? ok) => ok == null ? 'verificando' : (ok ? 'disponível' : 'indisponível');
            final (pillFg, pillBg) = ready ? p.state[FogState.normal]! : (p.textMuted, p.surfaceAlt);

            return ScreenBody(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FoG Cue',
                        style: TextStyle(color: p.text, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.6),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Coleta de sinais inerciais e pistas sensoriais para pesquisa sobre Freezing of Gait.',
                        style: TextStyle(color: p.textMuted, fontSize: 16, height: 1.45),
                      ),
                    ],
                  ),
                ),
                Section(
                  title: 'Status do sistema',
                  aside: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(999)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: pillFg, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          imu == null ? 'Verificando' : (ready ? 'Pronto' : 'Sem sensores'),
                          style: TextStyle(color: pillFg, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  children: [
                    KeyValueRow('Acelerômetro', sensorText(imu?.accelerometer)),
                    KeyValueRow('Giroscópio', sensorText(imu?.gyroscope)),
                    KeyValueRow('Detector', detectorLabels[s.detector]!),
                    KeyValueRow('Amostragem e janela', '${s.sampleRateHz} Hz, ${s.windowSizeMs / 1000} s'),
                    KeyValueRow('Cue', cues.isEmpty ? 'desligado' : '$cues, ${s.cue.bpm} BPM', last: true),
                  ],
                ),
                AppButton(
                  label: 'Iniciar sessão',
                  icon: LucideIcons.play,
                  onPressed: imu != null && !ready ? null : () => _open(const NewSessionScreen()),
                ),
                Section(
                  children: [
                    _NavRow(
                      icon: LucideIcons.history,
                      label: 'Histórico de sessões',
                      onTap: () => _open(const HistoryScreen()),
                    ),
                    _NavRow(
                      icon: LucideIcons.slidersHorizontal,
                      label: 'Configurações experimentais',
                      onTap: () => _open(const SettingsScreen()),
                      last: true,
                    ),
                  ],
                ),
                const Muted(
                  'Projeto acadêmico e experimental. Este aplicativo não é dispositivo médico, não faz diagnóstico e '
                  'não substitui acompanhamento profissional. Todos os dados ficam neste aparelho.',
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.label, required this.onTap, this.last = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: last
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: p.border, width: 0.5)),
              ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: p.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

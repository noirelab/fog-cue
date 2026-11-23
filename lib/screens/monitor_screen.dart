import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config/experiment.dart';
import '../core/imu.dart';
import '../monitoring/monitoring_engine.dart';
import '../services/cue_outputs.dart';
import '../services/background.dart';
import '../services/database.dart';
import '../services/imu_service.dart';
import '../sessions/models.dart';
import '../ui/format.dart';
import '../ui/line_chart.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'session_detail_screen.dart';

/// Frequência de atualização da interface. Os sensores rodam independentes.
const _uiRefresh = Duration(milliseconds: 100);

/// Sem amostra nova por mais que isso, o painel mostra "Sensor sem sinal".
const _staleAfter = Duration(seconds: 2);

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key, required this.settings, required this.info});

  /// Configurações congeladas no início: a sessão inteira usa as mesmas.
  final ExperimentSettings settings;
  final SessionInfo info;

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  MonitoringEngine? _engine;
  DeviceCueOutputs? _outputs;
  MonitoringSnapshot? _snap;
  List<ImuSample> _samples = const [];
  Timer? _uiTimer;
  Object? _error;
  String? _warning;
  bool _stopping = false;
  bool _starting = false;

  // Saúde do sensor: medida no relógio da tela, pela contagem de amostras,
  // para não depender do relógio do sensor.
  int _lastCount = -1;
  DateTime _lastProgressAt = DateTime.now();
  bool _stale = false;

  /// Modo pesquisa: gráficos, métricas e tela sempre acesa. Fora dele, modo
  /// simples para o participante, com a tela livre para apagar no bolso.
  bool get _research => widget.settings.researchMode;

  @override
  void initState() {
    super.initState();
    if (_research) unawaited(WakelockPlus.enable());
    unawaited(_start());
  }

  Future<void> _start() async {
    // Evita duas sessões ao mesmo tempo (ex.: dois toques em "Tentar de novo").
    if (_starting || _engine != null) return;
    _starting = true;
    try {
      final outputs = await DeviceCueOutputs.create();
      if (!mounted) {
        await outputs.dispose();
        return;
      }
      // A partir daqui o dispose() da tela libera o player.
      _outputs = outputs;
      final info = await PackageInfo.fromPlatform();
      final engine = await MonitoringEngine.start(
        widget.settings,
        widget.info,
        EngineDeps(
          startImu: startImu,
          cueOutputs: outputs,
          store: AppDatabase.instance,
          appVersion: '${info.version}+${info.buildNumber}',
          platform: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        ),
      );
      if (!mounted) {
        await engine.stop();
        return;
      }
      _engine = engine;
      final warnings = <String>[];
      final missing = [if (!outputs.audioAvailable) 'som', if (!outputs.vibrationAvailable) 'vibração'];
      if (missing.isNotEmpty) warnings.add('Este celular não tem ${missing.join(' nem ')}.');
      try {
        await startBackgroundMonitoring();
      } catch (error) {
        // Sem o serviço, a tela acesa é o que mantém a coleta viva.
        debugPrint('Falha ao iniciar o serviço em primeiro plano: $error');
        unawaited(WakelockPlus.enable());
        warnings.add('Deixe o app aberto: com ele fechado, a medição pode parar.');
      }
      if (!mounted) return;
      setState(() => _warning = warnings.isEmpty ? null : warnings.join(' '));
      _lastProgressAt = DateTime.now();
      // No modo simples só o relógio em segundos muda: 1 atualização por segundo basta.
      _uiTimer = Timer.periodic(_research ? _uiRefresh : const Duration(seconds: 1), (_) {
        // Encerrando: as amostras param de propósito, não é sensor sem sinal.
        if (_stopping) return;
        final snap = engine.snapshot();
        final now = DateTime.now();
        if (snap.sampleCount != _lastCount) {
          _lastCount = snap.sampleCount;
          _lastProgressAt = now;
        }
        final stale = now.difference(_lastProgressAt) > _staleAfter;
        // Avisa sem precisar olhar a tela: o celular está no bolso.
        if (stale && !_stale) _outputs?.hapticPulse();
        setState(() {
          _snap = snap;
          if (_research) _samples = engine.recentSamples();
          _stale = stale;
        });
      });
    } catch (error) {
      debugPrint('Falha ao iniciar a sessão: $error');
      if (mounted) setState(() => _error = error);
    } finally {
      _starting = false;
    }
  }

  Future<void> _retry() async {
    if (_starting) return;
    final outputs = _outputs;
    _outputs = null;
    await outputs?.dispose();
    if (!mounted) return;
    setState(() => _error = null);
    await _start();
  }

  @override
  void dispose() {
    _uiTimer?.cancel();
    // Sair da tela por qualquer caminho encerra e grava a sessão.
    unawaited(_engine?.stop().catchError((Object e) => debugPrint('Falha ao encerrar a sessão: $e')));
    unawaited(_outputs?.dispose());
    unawaited(stopBackgroundMonitoring().catchError((Object e) => debugPrint('Falha ao parar o serviço: $e')));
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _stopping = true);
    final engine = _engine;
    try {
      await engine?.stop();
      if (!mounted) return;
      if (engine == null) {
        Navigator.of(context).pop();
      } else if (!_research) {
        // O participante volta para o início; o detalhe técnico é do pesquisador.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Caminhada salva.')));
      } else {
        unawaited(
          Navigator.of(
            context,
          ).pushReplacement(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: engine.session.id))),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _stopping = false);
      showError(context, 'Não foi possível encerrar a sessão. Tente de novo.', error);
    }
  }

  Future<void> _confirmFinish() async {
    final ok = await confirmDialog(
      context,
      title: 'Encerrar a coleta?',
      message: 'Os dados gravados até agora ficam salvos no histórico.',
      confirmLabel: 'Encerrar',
      cancelLabel: 'Continuar',
    );
    if (ok) await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Monitoramento')),
        body: ScreenBody(
          footer: AppButton(
            label: 'Voltar',
            variant: ButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          children: [
            ErrorPanel(
              title: 'Não foi possível iniciar a sessão',
              message:
                  'Não consegui ligar os sensores ou preparar a gravação. '
                  'Tente de novo; se continuar, feche e abra o app.',
              error: _error,
              onRetry: _retry,
            ),
          ],
        ),
      );
    }

    final status = MonitorStatus.from(
      state: snap == null || snap.sampleCount == 0 ? null : snap.state,
      cueActive: snap?.cueActive ?? false,
      sensorStale: _stale,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_stopping) unawaited(_confirmFinish());
      },
      child: _research ? _buildResearch(context, status) : _buildSimple(context, status),
    );
  }

  Widget _buildSimple(BuildContext context, MonitorStatus status) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Caminhada'), automaticallyImplyLeading: false),
      body: ScreenBody(
        footer: _stopping
            ? const AppButton(label: 'Salvando', loading: true, large: true, onPressed: null)
            : HoldButton(
                label: 'Segure para parar',
                holdingLabel: 'Continue segurando...',
                onConfirmed: () => unawaited(_finish()),
                onAccessibleTap: () => unawaited(_confirmFinish()),
              ),
        children: [
          StatusPanel(status: status.forParticipant(), simple: true),
          Text(
            'Tempo de caminhada: ${formatDuration(_snap?.elapsedMs ?? 0)}',
            style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w500, fontFeatures: tabular),
          ),
          Text(
            'Pode guardar o celular no bolso. Ele vibra e toca um ritmo se você travar.',
            style: TextStyle(color: p.textMuted, fontSize: 18, height: 1.45),
          ),
          if (_warning != null) Text(_warning!, style: TextStyle(color: p.text, fontSize: 18, height: 1.45)),
        ],
      ),
    );
  }

  Widget _buildResearch(BuildContext context, MonitorStatus status) {
    final p = Palette.of(context);
    final snap = _snap;
    final last = snap?.lastSample;
    List<double> acc(double Function(Vector3) f) => [for (final s in _samples) f(s.accelerometer)];
    List<double> gyro(double Function(Vector3) f) => [for (final s in _samples) f(s.gyroscope)];
    String triple(Vector3 v, String unit) => '${fmt(v.x)}  ${fmt(v.y)}  ${fmt(v.z)} $unit';

    return Scaffold(
      appBar: AppBar(title: const Text('Monitoramento'), automaticallyImplyLeading: false),
      body: ScreenBody(
        footer: AppButton(
          label: 'Encerrar sessão',
          variant: ButtonVariant.danger,
          loading: _stopping,
          onPressed: _confirmFinish,
        ),
        children: [
          StatusPanel(status: status, confidence: snap?.confidence),
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.border, width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _Metric('Duração', formatDuration(snap?.elapsedMs ?? 0)),
                  _Metric('Amostragem', fmt(snap?.measuredRateHz, 0, 'Hz')),
                  _Metric('Posição', widget.info.phonePlacement.label),
                ],
              ),
            ),
          ),
          if (_warning != null) Muted(_warning!),
          Section(
            title: 'Magnitude da aceleração',
            aside: Muted(last == null ? '-' : fmt(magnitude(last.accelerometer), 2, 'm/s²')),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: LineChart(unit: 'm/s²', series: [ChartSeries('|a|', p.chartMag, acc(magnitude))]),
              ),
            ],
          ),
          Section(
            title: 'Acelerômetro',
            aside: Muted(last == null ? '-' : triple(last.accelerometer, 'm/s²')),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: LineChart(
                  unit: 'm/s²',
                  series: [
                    ChartSeries('X', p.chartX, acc((v) => v.x)),
                    ChartSeries('Y', p.chartY, acc((v) => v.y)),
                    ChartSeries('Z', p.chartZ, acc((v) => v.z)),
                  ],
                ),
              ),
            ],
          ),
          Section(
            title: 'Giroscópio',
            aside: Muted(last == null ? '-' : triple(last.gyroscope, 'rad/s')),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: LineChart(
                  unit: 'rad/s',
                  minRange: 0.2,
                  series: [
                    ChartSeries('X', p.chartX, gyro((v) => v.x)),
                    ChartSeries('Y', p.chartY, gyro((v) => v.y)),
                    ChartSeries('Z', p.chartZ, gyro((v) => v.z)),
                  ],
                ),
              ),
            ],
          ),
          if (snap != null) _ResearchPanel(snap: snap, onSimulate: () => _engine?.simulateFog()),
          Muted('Sessão ${snap?.sessionId ?? 'iniciando...'}'),
        ],
      ),
    );
  }
}

class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, required this.status, this.confidence, this.simple = false});

  final MonitorStatus status;

  /// Confiança do detector; só aparece nos estados que vêm dele.
  final double? confidence;

  /// Modo simples: textos sem jargão, letra maior e sem confiança.
  final bool simple;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = Palette.of(context).statusColors(status);
    final title = simple ? status.plainTitle : status.title;
    final hint = simple ? status.plainHint : status.hint;
    final showConfidence =
        !simple && confidence != null && status != MonitorStatus.starting && status != MonitorStatus.noSignal;
    // O cue ativo é o momento que mais importa: texto e ícone maiores.
    final loud = simple || status == MonitorStatus.cueActive;
    return Semantics(
      liveRegion: true,
      label: '$title. $hint',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.all(loud ? 28 : 24),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(status.icon, size: loud ? 48 : 32, color: fg),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(color: fg, fontSize: loud ? 40 : 34, fontWeight: FontWeight.w700, letterSpacing: -0.5),
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(color: fg, fontSize: loud ? 22 : 16, height: 1.4),
            ),
            if (showConfidence) ...[
              const SizedBox(height: 12),
              Text(
                'Confiança ${fmt(confidence! * 100, 0)}%',
                style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600, fontFeatures: tabular),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: p.textMuted, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600, fontFeatures: tabular),
          ),
        ],
      ),
    );
  }
}

class _ResearchPanel extends StatelessWidget {
  const _ResearchPanel({required this.snap, required this.onSimulate});

  final MonitoringSnapshot snap;
  final VoidCallback onSimulate;

  @override
  Widget build(BuildContext context) {
    int count(SessionEventType t) => snap.eventCounts[t] ?? 0;
    return Section(
      title: 'Modo pesquisa',
      children: [
        KeyValueRow('Taxa real', fmt(snap.measuredRateHz, 1, 'Hz')),
        KeyValueRow('Amostras recebidas', '${snap.sampleCount}'),
        KeyValueRow('Buffer da janela', '${snap.windowBufferSize} amostras'),
        KeyValueRow('Janelas analisadas / puladas', '${snap.windowsAnalyzed} / ${snap.windowsSkipped}'),
        KeyValueRow('Tempo de inferência', fmt(snap.lastInferenceMs, 1, 'ms')),
        KeyValueRow('Latência de processamento', fmt(snap.processingLatencyMs, 0, 'ms')),
        KeyValueRow('Latência até o cue', fmt(snap.cueLatencyMs, 0, 'ms')),
        KeyValueRow('Confiança', fmt(snap.confidence, 3)),
        if (snap.detectorMetadata['freeze_index'] case final double fi) KeyValueRow('Freeze Index', fmt(fi, 2)),
        if (snap.detectorMetadata['total_power'] case final double power)
          KeyValueRow('Energia 0,5 a 8 Hz', fmt(power, 3, '(m/s²)²')),
        KeyValueRow('Estado', snap.state.code),
        KeyValueRow(
          'Eventos (possível / FoG / cues)',
          '${count(SessionEventType.fogPossible)} / ${count(SessionEventType.fogDetected)} / '
              '${count(SessionEventType.cueStarted)}',
        ),
        if (snap.detectorErrors > 0)
          KeyValueRow('Erros do detector', '${snap.detectorErrors}: ${snap.lastDetectorError ?? ''}'),
        KeyValueRow('Escritas pendentes', '${snap.pendingWrites}', last: snap.storageError == null),
        if (snap.storageError != null) KeyValueRow('Erro de gravação', snap.storageError!, last: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: AppButton(
            label: 'Simular FoG',
            variant: ButtonVariant.secondary,
            icon: LucideIcons.zap,
            onPressed: onSimulate,
          ),
        ),
      ],
    );
  }
}

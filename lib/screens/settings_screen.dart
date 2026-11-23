import 'dart:async';

import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../config/experiment.dart';
import '../cues/cue_engine.dart';
import '../services/cue_outputs.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// Campos com casas decimais; os demais são inteiros.
const _decimalKeys = {
  SettingKey.windowOverlap,
  SettingKey.fogThreshold,
  SettingKey.freezeIndexThreshold,
  SettingKey.powerThreshold,
};

const _detectorHelp = {
  DetectorName.freezeIndex:
      'Freeze Index: compara a energia do tremor (3 a 8 Hz) com a da caminhada (0,5 a 3 Hz). '
      'Os limiares são pontos de partida: calibre olhando os valores no modo pesquisa.',
  DetectorName.heuristic:
      'Heurístico: limiar no desvio padrão da magnitude. Dispara também com a caminhada comum; serve só de referência.',
  DetectorName.mock: 'Mock nunca detecta. Use "Simular FoG" para testar a pipeline.',
};

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Map<SettingKey, TextEditingController> _fields;
  late DetectorName _detector;
  late bool _haptic;
  late bool _audio;
  late bool _research;
  Map<SettingKey, String> _errors = {};
  bool _saving = false;
  CueEngine? _testCue;
  Future<DeviceCueOutputs>? _testOutputsFuture;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load(SettingsScope.of(context).settings);
  }

  void _load(ExperimentSettings s) {
    final values = numericValues(s);
    _fields = {for (final k in SettingKey.values) k: TextEditingController(text: '${values[k]}')};
    _detector = s.detector;
    _haptic = s.cue.hapticEnabled;
    _audio = s.cue.audioEnabled;
    _research = s.researchMode;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    _testCue?.stop();
    // Libera o player mesmo se ele ainda estiver sendo criado.
    unawaited(_testOutputsFuture?.then((o) => o.dispose()));
    super.dispose();
  }

  /// Lê os campos. Devolve null e preenche [_errors] se algo for inválido.
  ExperimentSettings? _build() {
    final errors = <SettingKey, String>{};
    final parsed = <SettingKey, num>{};
    for (final k in SettingKey.values) {
      final text = _fields[k]!.text.trim().replaceAll(',', '.');
      final value = _decimalKeys.contains(k) ? double.tryParse(text) : int.tryParse(text);
      if (value == null) {
        errors[k] = _decimalKeys.contains(k) ? 'Número inválido.' : 'Use um número inteiro.';
      } else {
        parsed[k] = value;
      }
    }
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return null;
    }
    int i(SettingKey k) => parsed[k]!.toInt();
    double d(SettingKey k) => parsed[k]!.toDouble();
    final s = ExperimentSettings(
      sampleRateHz: i(SettingKey.sampleRateHz),
      windowSizeMs: i(SettingKey.windowSizeMs),
      windowOverlap: d(SettingKey.windowOverlap),
      fogThreshold: d(SettingKey.fogThreshold),
      freezeIndexThreshold: d(SettingKey.freezeIndexThreshold),
      powerThreshold: d(SettingKey.powerThreshold),
      cueCooldownMs: i(SettingKey.cueCooldownMs),
      confirmWindows: i(SettingKey.confirmWindows),
      recoveryWindows: i(SettingKey.recoveryWindows),
      warmupSeconds: i(SettingKey.warmupSeconds),
      detector: _detector,
      researchMode: _research,
      cue: CueSettings(
        hapticEnabled: _haptic,
        audioEnabled: _audio,
        bpm: i(SettingKey.bpm),
        durationSeconds: i(SettingKey.durationSeconds),
      ),
    );
    final invalid = validateSettings(s);
    setState(() => _errors = invalid);
    return invalid.isEmpty ? s : null;
  }

  Future<void> _save() async {
    final s = _build();
    if (s == null) return;
    setState(() => _saving = true);
    try {
      await SettingsScope.of(context).update(s);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showError(context, 'Não foi possível salvar as configurações. Tente de novo.', error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reset() => setState(() {
    final values = numericValues(defaultSettings);
    for (final k in SettingKey.values) {
      _fields[k]!.text = '${values[k]}';
    }
    _detector = defaultSettings.detector;
    _haptic = defaultSettings.cue.hapticEnabled;
    _audio = defaultSettings.cue.audioEnabled;
    _research = defaultSettings.researchMode;
    _errors = {};
  });

  Future<void> _playTestCue() async {
    final s = _build();
    if (s == null) return;
    // Um único player por tela, mesmo com toques repetidos durante a criação.
    final outputs = await (_testOutputsFuture ??= DeviceCueOutputs.create());
    if (!mounted) return; // o dispose() já liberou o player
    _testCue?.stop();
    _testCue = CueEngine(outputs)..trigger(s.cue.copyWith(durationSeconds: 4), 0);
  }

  Widget _field(SettingKey key, String label, {String? hint}) {
    final limit = limits[key]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: _fields[key],
        keyboardType: TextInputType.numberWithOptions(decimal: _decimalKeys.contains(key)),
        decoration: InputDecoration(
          labelText: label,
          helperText: hint ?? '${limit.min} a ${limit.max}',
          errorText: _errors[key],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ScreenBody(
        footer: AppButton(label: 'Salvar', loading: _saving, onPressed: _save),
        children: [
          Section(
            title: 'Aquisição',
            children: [
              _field(SettingKey.sampleRateHz, 'Taxa de amostragem (Hz)'),
              _field(SettingKey.windowSizeMs, 'Tamanho da janela (ms)'),
              _field(SettingKey.windowOverlap, 'Sobreposição da janela', hint: 'Fração de 0 a 0.9. Ex.: 0.5 = 50%'),
            ],
          ),
          Section(
            title: 'Detecção',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SegmentedButton<DetectorName>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: DetectorName.freezeIndex, label: Text('Freeze Index')),
                    ButtonSegment(value: DetectorName.heuristic, label: Text('Heurístico')),
                    ButtonSegment(value: DetectorName.mock, label: Text('Mock')),
                  ],
                  selected: {_detector},
                  onSelectionChanged: (s) => setState(() => _detector = s.first),
                ),
              ),
              Muted(_detectorHelp[_detector]!),
              if (_detector == DetectorName.freezeIndex) ...[
                _field(SettingKey.freezeIndexThreshold, 'Limiar do Freeze Index'),
                _field(
                  SettingKey.powerThreshold,
                  'Energia mínima (m/s²)²',
                  hint:
                      'Abaixo disso a pessoa está parada. '
                      '${limits[SettingKey.powerThreshold]!.min} a ${limits[SettingKey.powerThreshold]!.max}',
                ),
              ],
              if (_detector == DetectorName.heuristic)
                _field(SettingKey.fogThreshold, 'Limiar do desvio padrão (m/s²)'),
              _field(SettingKey.confirmWindows, 'Janelas para confirmar FoG'),
              _field(SettingKey.recoveryWindows, 'Janelas para sair da recuperação'),
              _field(
                SettingKey.warmupSeconds,
                'Início sem detecção (s)',
                hint: 'Tempo para guardar o celular no bolso',
              ),
            ],
          ),
          Section(
            title: 'Cue sensorial',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Vibração', style: TextStyle(color: p.text)),
                value: _haptic,
                onChanged: (v) => setState(() => _haptic = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Metrônomo (áudio)', style: TextStyle(color: p.text)),
                value: _audio,
                onChanged: (v) => setState(() => _audio = v),
              ),
              _field(SettingKey.bpm, 'Ritmo (BPM)'),
              _field(SettingKey.durationSeconds, 'Duração do cue (s)'),
              _field(SettingKey.cueCooldownMs, 'Intervalo mínimo entre cues (ms)'),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: AppButton(
                  label: 'Testar cue por 4 s',
                  variant: ButtonVariant.secondary,
                  onPressed: _playTestCue,
                ),
              ),
            ],
          ),
          Section(
            title: 'Pesquisa',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Modo pesquisa', style: TextStyle(color: p.text)),
                subtitle: Text(
                  'Ligado: telas completas, com gráficos, métricas e histórico. '
                  'Desligado: modo simples para o participante, com textos claros e botões grandes.',
                  style: TextStyle(color: p.textMuted),
                ),
                value: _research,
                onChanged: (v) => setState(() => _research = v),
              ),
            ],
          ),
          AppButton(label: 'Restaurar padrões', variant: ButtonVariant.secondary, onPressed: _reset),
        ],
      ),
    );
  }
}

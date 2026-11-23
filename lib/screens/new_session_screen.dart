import 'package:flutter/material.dart';

import '../app_settings.dart';
import '../monitoring/monitoring_engine.dart';
import '../sessions/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'monitor_screen.dart';

final _participantPattern = RegExp(r'^[A-Za-z0-9_-]{0,32}$');
const _notesMax = 500;

class NewSessionScreen extends StatefulWidget {
  const NewSessionScreen({super.key});

  @override
  State<NewSessionScreen> createState() => _NewSessionScreenState();
}

class _NewSessionScreenState extends State<NewSessionScreen> {
  final _participant = TextEditingController();
  final _notes = TextEditingController();
  PhonePlacement _placement = PhonePlacement.pocket;

  @override
  void initState() {
    super.initState();
    _participant.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _participant.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? get _participantError => _participantPattern.hasMatch(_participant.text.trim())
      ? null
      : 'Use até 32 letras, números, "-" ou "_". Não use o nome real.';

  void _start() {
    final participant = _participant.text.trim();
    final notes = _notes.text.trim();
    // Lido agora: o builder da rota roda de novo depois que esta tela já saiu.
    final settings = SettingsScope.of(context).settings;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => MonitorScreen(
        settings: settings,
        info: SessionInfo(
          participantId: participant.isEmpty ? null : participant,
          phonePlacement: _placement,
          notes: notes.isEmpty ? null : notes,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nova sessão')),
      body: ScreenBody(
        footer: AppButton(label: 'Iniciar', onPressed: _participantError == null ? _start : null),
        children: [
          TextField(
            controller: _participant,
            maxLength: 32,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Participante (opcional)',
              hintText: 'P01',
              helperText: 'Código anônimo, por exemplo P01.',
              errorText: _participantError,
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Posição do celular', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<PhonePlacement>(
                showSelectedIcon: false,
                segments: [
                  for (final pl in PhonePlacement.values) ButtonSegment(value: pl, label: Text(pl.label)),
                ],
                selected: {_placement},
                onSelectionChanged: (s) => setState(() => _placement = s.first),
              ),
            ],
          ),
          TextField(
            controller: _notes,
            maxLength: _notesMax,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Observações',
              hintText: 'Condições do teste, percurso, calçado...',
              helperText: 'Não inclua nome nem dados que identifiquem o participante.',
              alignLabelWithHint: true,
            ),
          ),
          const Muted('A coleta começa ao tocar em Iniciar. Mantenha o app aberto durante a sessão: a tela fica ligada.'),
        ],
      ),
    );
  }
}

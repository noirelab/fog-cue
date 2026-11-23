import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/database.dart';
import '../services/export_service.dart';
import '../sessions/models.dart';
import '../ui/format.dart';
import '../ui/widgets.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late Future<(Session?, ({int samples, int events}))> _data = _load();

  Future<(Session?, ({int samples, int events}))> _load() =>
      (AppDatabase.instance.getSession(widget.sessionId), AppDatabase.instance.getCounts(widget.sessionId)).wait;
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await exportSession(widget.sessionId);
    } catch (error) {
      if (mounted) showError(context, 'Não foi possível exportar a sessão. Tente de novo.', error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir sessão?',
      message: 'Amostras, eventos e metadados desta sessão serão apagados do aparelho.',
      confirmLabel: 'Excluir',
      cancelLabel: 'Cancelar',
    );
    if (!ok) return;
    try {
      await AppDatabase.instance.deleteSession(widget.sessionId);
      // Cópias exportadas no cache também saem, para a exclusão ser completa.
      await clearExports();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showError(context, 'Não foi possível excluir a sessão. Tente de novo.', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sessão')),
      body: FutureBuilder(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return ScreenBody(
              children: [
                ErrorPanel(
                  title: 'Não foi possível carregar a sessão',
                  message: 'Os dados continuam gravados no aparelho. Tente carregar de novo.',
                  error: snap.error,
                  onRetry: () => setState(() => _data = _load()),
                ),
              ],
            );
          }
          final data = snap.data;
          if (data == null) return const SizedBox.shrink();
          final (session, counts) = data;
          if (session == null) return const ScreenBody(children: [Muted('Sessão não encontrada.')]);

          final m = session.metadata;
          final cue = m.cueSettings;
          final cueKinds = [if (cue.hapticEnabled) 'vibração', if (cue.audioEnabled) 'áudio'].join(' + ');
          final ended = session.endedAt;
          final notes = session.notes;
          return ScreenBody(
            children: [
              Section(
                title: 'Sessão',
                children: [
                  KeyValueRow('Identificador', session.id),
                  KeyValueRow('Início', formatDateTime(session.startedAt)),
                  KeyValueRow('Duração', ended == null ? 'interrompida' : formatDuration(ended - session.startedAt)),
                  KeyValueRow('Participante', session.participantId ?? '-'),
                  KeyValueRow('Posição', session.phonePlacement.label),
                  KeyValueRow('Amostras / eventos', '${counts.samples} / ${counts.events}', last: notes == null),
                  if (notes != null) KeyValueRow('Observações', notes, last: true),
                ],
              ),
              Section(
                title: 'Parâmetros do experimento',
                children: [
                  KeyValueRow('Amostragem', '${m.sampleRate} Hz'),
                  KeyValueRow('Janela / sobreposição', '${m.windowSize} ms / ${(m.windowOverlap * 100).round()}%'),
                  KeyValueRow('Detector', '${m.detectorName} ${m.detectorVersion}'),
                  KeyValueRow(
                    'Cue',
                    '${cueKinds.isEmpty ? 'desligado' : cueKinds}, ${cue.bpm} BPM, ${cue.durationSeconds} s',
                  ),
                  KeyValueRow('App / plataforma', '${m.appVersion} / ${m.platform}', last: true),
                ],
              ),
              AppButton(label: 'Exportar CSV e JSON', icon: LucideIcons.share, loading: _exporting, onPressed: _export),
              const Muted(
                'Gera três arquivos (amostras, eventos e metadados) e abre o compartilhamento do Android para você '
                'escolher onde salvar.',
              ),
              AppButton(
                label: 'Excluir sessão',
                variant: ButtonVariant.danger,
                icon: LucideIcons.trash2,
                onPressed: _delete,
              ),
            ],
          );
        },
      ),
    );
  }
}

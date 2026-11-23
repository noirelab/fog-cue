import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/database.dart';
import '../ui/format.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'session_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<SessionSummary>> _sessions = AppDatabase.instance.listSessions();

  Future<void> _open(String id) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionDetailScreen(sessionId: id)));
    // Recarrega ao voltar (a sessão pode ter sido excluída).
    if (mounted) setState(() => _sessions = AppDatabase.instance.listSessions());
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico')),
      body: FutureBuilder<List<SessionSummary>>(
        future: _sessions,
        builder: (context, snap) {
          if (snap.hasError) {
            return ScreenBody(
              children: [
                ErrorPanel(
                  title: 'Não foi possível carregar o histórico',
                  message: 'As sessões continuam gravadas no aparelho. Tente carregar de novo.',
                  error: snap.error,
                  onRetry: () => setState(() => _sessions = AppDatabase.instance.listSessions()),
                ),
              ],
            );
          }
          final sessions = snap.data;
          if (sessions == null) return const SizedBox.shrink();
          if (sessions.isEmpty) {
            return ScreenBody(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text(
                    'Nenhuma sessão ainda',
                    style: TextStyle(color: p.text, fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                ),
                const Muted('As sessões gravadas aparecem aqui, com opção de exportar CSV e JSON.'),
              ],
            );
          }
          return ScreenBody(
            children: [
              Section(
                children: [
                  for (var i = 0; i < sessions.length; i++)
                    _SessionRow(
                      summary: sessions[i],
                      last: i == sessions.length - 1,
                      onTap: () => _open(sessions[i].session.id),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.summary, required this.last, required this.onTap});

  final SessionSummary summary;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = summary.session;
    final ended = s.endedAt;
    final duration = ended == null ? 'interrompida' : formatDuration(ended - s.startedAt);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: last
            ? null
            : BoxDecoration(
                border: Border(bottom: BorderSide(color: p.border, width: 0.5)),
              ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDateTime(s.startedAt)}${s.participantId == null ? '' : '  ·  ${s.participantId}'}',
                    style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w500, fontFeatures: tabular),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.phonePlacement.label}, $duration, ${summary.sampleCount} amostras',
                    style: TextStyle(color: p.textMuted, fontSize: 14, fontFeatures: tabular),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

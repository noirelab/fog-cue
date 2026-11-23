import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../sessions/csv.dart';
import 'database.dart';

/// Gera os três arquivos da sessão na pasta temporária do app e abre a folha
/// de compartilhamento do sistema (salvar em Arquivos, Drive, e-mail...).
/// O app em si não envia nada para servidor: o usuário escolhe o destino.
Future<void> exportSession(String sessionId) async {
  final db = AppDatabase.instance;
  final session = await db.getSession(sessionId);
  if (session == null) throw StateError('Sessão $sessionId não encontrada');
  final samples = await db.getSamples(sessionId);
  final events = await db.getEvents(sessionId);

  // Só a exportação atual fica no cache; as anteriores são apagadas.
  await clearExports();
  final dir = await _exportsDir();
  await dir.create(recursive: true);
  final base = 'session_$sessionId';
  final contents = {
    '${base}_samples.csv': samplesToCsv(samples),
    '${base}_events.csv': eventsToCsv(events),
    '${base}_metadata.json': sessionToJson(session, samples: samples.length, events: events.length),
  };

  final files = <XFile>[];
  for (final entry in contents.entries) {
    final file = File(p.join(dir.path, entry.key));
    await file.writeAsString(entry.value);
    files.add(XFile(file.path, mimeType: entry.key.endsWith('.json') ? 'application/json' : 'text/csv'));
  }
  await SharePlus.instance.share(ShareParams(files: files, subject: 'FoG Cue: sessão $sessionId'));
}

Future<Directory> _exportsDir() async => Directory(p.join((await getTemporaryDirectory()).path, 'exports'));

/// Apaga as cópias exportadas que ficaram no cache do app.
Future<void> clearExports() async {
  final dir = await _exportsDir();
  if (await dir.exists()) await dir.delete(recursive: true);
}

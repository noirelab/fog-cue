import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../config/experiment.dart';
import '../fog/fog.dart';
import '../monitoring/monitoring_engine.dart';
import '../sessions/csv.dart';
import '../sessions/models.dart';

/// Armazenamento local em SQLite. Nada sai do aparelho.
///
/// Esquema: sessions (1 linha por sessão), samples (1 linha por amostra,
/// mesmas colunas do CSV), events, settings (chave/valor em JSON).
const _schema = [
  '''CREATE TABLE sessions (
    id TEXT PRIMARY KEY NOT NULL,
    participant_id TEXT,
    started_at REAL NOT NULL,
    ended_at REAL,
    phone_placement TEXT NOT NULL,
    notes TEXT,
    metadata TEXT NOT NULL
  )''',
  '''CREATE TABLE samples (
    session_id TEXT NOT NULL,
    timestamp REAL NOT NULL,
    acc_x REAL, acc_y REAL, acc_z REAL, acc_magnitude REAL,
    gyro_x REAL, gyro_y REAL, gyro_z REAL,
    fog_state TEXT NOT NULL,
    fog_confidence REAL,
    cue_triggered INTEGER NOT NULL
  )''',
  'CREATE INDEX samples_session ON samples (session_id, timestamp)',
  '''CREATE TABLE events (
    session_id TEXT NOT NULL,
    timestamp REAL NOT NULL,
    type TEXT NOT NULL,
    metadata TEXT
  )''',
  'CREATE INDEX events_session ON events (session_id, timestamp)',
  'CREATE TABLE settings (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
];

class SessionSummary {
  const SessionSummary(this.session, this.sampleCount);
  final Session session;
  final int sampleCount;
}

/// SQLite não guarda NaN: vira NULL na escrita e volta a NaN na leitura.
Object? _finiteOrNull(double v) => v.isFinite ? v : null;
double _toDouble(Object? v) => v is num ? v.toDouble() : double.nan;

Map<String, Object?> _decodeObject(Object? text) {
  if (text is! String) return const {};
  final decoded = jsonDecode(text);
  return decoded is Map<String, Object?> ? decoded : const {};
}

class AppDatabase implements SessionStore {
  AppDatabase._();

  static final instance = AppDatabase._();

  Future<Database>? _db;

  Future<Database> get _database => _db ??= _open();

  static Future<Database> _open() async => openDatabase(
        p.join(await getDatabasesPath(), 'fogcue.db'),
        version: 1,
        onCreate: (db, _) async {
          for (final sql in _schema) {
            await db.execute(sql);
          }
        },
      );

  // ---------- sessões ----------

  @override
  Future<void> createSession(Session s) async {
    final db = await _database;
    await db.insert('sessions', {
      'id': s.id,
      'participant_id': s.participantId,
      'started_at': s.startedAt,
      'ended_at': null,
      'phone_placement': s.phonePlacement.name,
      'notes': s.notes,
      'metadata': jsonEncode(jsonSafe(s.metadata.toJson())),
    });
  }

  @override
  Future<void> finishSession(String id, double endedAt) async {
    final db = await _database;
    await db.update('sessions', {'ended_at': endedAt}, where: 'id = ?', whereArgs: [id]);
  }

  Session _toSession(Map<String, Object?> r) => Session(
        id: jsonString(r, 'id', ''),
        participantId: r['participant_id'] is String ? r['participant_id'] as String : null,
        startedAt: _toDouble(r['started_at']),
        endedAt: r['ended_at'] is num ? _toDouble(r['ended_at']) : null,
        phonePlacement: PhonePlacement.values.asNameMap()[r['phone_placement']] ?? PhonePlacement.other,
        notes: r['notes'] is String ? r['notes'] as String : null,
        metadata: SessionMetadata.fromJson(_decodeObject(r['metadata'])),
      );

  Future<List<SessionSummary>> listSessions() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT s.*, (SELECT COUNT(*) FROM samples WHERE session_id = s.id) AS sample_count '
      'FROM sessions s ORDER BY started_at DESC',
    );
    return [for (final r in rows) SessionSummary(_toSession(r), jsonInt(r, 'sample_count', 0))];
  }

  Future<Session?> getSession(String id) async {
    final db = await _database;
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _toSession(rows.first);
  }

  Future<void> deleteSession(String id) async {
    final db = await _database;
    await db.transaction((txn) async {
      for (final table in ['samples', 'events']) {
        await txn.delete(table, where: 'session_id = ?', whereArgs: [id]);
      }
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<({int samples, int events})> getCounts(String id) async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM samples WHERE session_id = ?) AS samples, '
      '(SELECT COUNT(*) FROM events WHERE session_id = ?) AS events',
      [id, id],
    );
    final r = rows.first;
    return (samples: jsonInt(r, 'samples', 0), events: jsonInt(r, 'events', 0));
  }

  // ---------- amostras e eventos (escrita em lote, uma transação) ----------

  @override
  Future<void> insertSamples(String sessionId, List<SampleRecord> rows) async {
    final db = await _database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final r in rows) {
        batch.insert('samples', {
          'session_id': sessionId,
          'timestamp': r.timestamp,
          'acc_x': _finiteOrNull(r.accX),
          'acc_y': _finiteOrNull(r.accY),
          'acc_z': _finiteOrNull(r.accZ),
          'acc_magnitude': _finiteOrNull(r.accMagnitude),
          'gyro_x': _finiteOrNull(r.gyroX),
          'gyro_y': _finiteOrNull(r.gyroY),
          'gyro_z': _finiteOrNull(r.gyroZ),
          'fog_state': r.fogState.code,
          'fog_confidence': _finiteOrNull(r.fogConfidence),
          'cue_triggered': r.cueTriggered ? 1 : 0,
        });
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> insertEvents(String sessionId, List<SessionEvent> events) async {
    final db = await _database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final e in events) {
        batch.insert('events', {
          'session_id': sessionId,
          'timestamp': e.timestamp,
          'type': e.type.code,
          'metadata': jsonEncode(jsonSafe(e.metadata)),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<SampleRecord>> getSamples(String sessionId) async {
    final db = await _database;
    final rows = await db.query('samples', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'timestamp');
    final states = {for (final s in FogState.values) s.code: s};
    return [
      for (final r in rows)
        SampleRecord(
          timestamp: _toDouble(r['timestamp']),
          accX: _toDouble(r['acc_x']),
          accY: _toDouble(r['acc_y']),
          accZ: _toDouble(r['acc_z']),
          accMagnitude: _toDouble(r['acc_magnitude']),
          gyroX: _toDouble(r['gyro_x']),
          gyroY: _toDouble(r['gyro_y']),
          gyroZ: _toDouble(r['gyro_z']),
          fogState: states[r['fog_state']] ?? FogState.normal,
          fogConfidence: _toDouble(r['fog_confidence']),
          cueTriggered: r['cue_triggered'] == 1,
        ),
    ];
  }

  Future<List<SessionEvent>> getEvents(String sessionId) async {
    final db = await _database;
    final rows = await db.query('events', where: 'session_id = ?', whereArgs: [sessionId], orderBy: 'timestamp');
    return [
      for (final r in rows)
        if (SessionEventType.fromCode(jsonString(r, 'type', '')) case final type?)
          SessionEvent(timestamp: _toDouble(r['timestamp']), type: type, metadata: _decodeObject(r['metadata'])),
    ];
  }

  // ---------- configurações ----------

  Future<ExperimentSettings> loadSettings() async {
    final db = await _database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: ['experiment']);
    if (rows.isEmpty) return defaultSettings;
    try {
      return ExperimentSettings.fromJson(jsonDecode(jsonString(rows.first, 'value', '')));
    } on FormatException {
      return defaultSettings;
    }
  }

  Future<void> saveSettings(ExperimentSettings settings) async {
    final db = await _database;
    await db.insert(
      'settings',
      {'key': 'experiment', 'value': jsonEncode(settings.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

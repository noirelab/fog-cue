import 'dart:convert';

import 'models.dart';

/// Serialização para formatos abertos, lidos direto por pandas:
///
///   pd.read_csv("..._samples.csv")
///   pd.read_csv("..._events.csv")
///   json.load(open("..._metadata.json"))
///
/// CSV com vírgula, ponto decimal, cabeçalho na primeira linha, sem linhas
/// de comentário. Valores ausentes (NaN) viram campo vazio, que o pandas lê
/// como NaN.

String _cell(Object? value) {
  if (value == null) return '';
  if (value is double) return value.isFinite ? value.toString() : '';
  if (value is num) return value.toString();
  final text = value is String ? value : jsonEncode(jsonSafe(value));
  return RegExp(r'[",\n\r]').hasMatch(text) ? '"${text.replaceAll('"', '""')}"' : text;
}

String samplesToCsv(Iterable<SampleRecord> rows) {
  final out = StringBuffer()..writeln(sampleColumns.join(','));
  for (final row in rows) {
    out.writeln(row.toRow().map(_cell).join(','));
  }
  return out.toString();
}

/// A coluna metadata é um JSON em texto: json.loads em Python.
String eventsToCsv(Iterable<SessionEvent> events) {
  final out = StringBuffer()..writeln('timestamp,type,metadata');
  for (final e in events) {
    out.writeln([_cell(e.timestamp), _cell(e.type.code), _cell(e.metadata)].join(','));
  }
  return out.toString();
}

String sessionToJson(Session session, {required int samples, required int events}) =>
    const JsonEncoder.withIndent('  ').convert(jsonSafe({
      'format': 'fog-cue-session',
      'formatVersion': 1,
      'units': {'timestamp': 'ms (Unix epoch)', 'accelerometer': 'm/s^2', 'gyroscope': 'rad/s'},
      ...session.toJson(),
      'counts': {'samples': samples, 'events': events},
    }));

/// JSON não aceita NaN nem infinito: viram null.
Object? jsonSafe(Object? value) => switch (value) {
      final double d when !d.isFinite => null,
      final Map<String, Object?> m => {for (final e in m.entries) e.key: jsonSafe(e.value)},
      final List<Object?> l => [for (final v in l) jsonSafe(v)],
      _ => value,
    };

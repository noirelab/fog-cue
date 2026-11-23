import 'models.dart';

/// Destino da escrita. Em produção é o SQLite (services/database.dart).
abstract interface class SessionSink {
  Future<void> insertSamples(String sessionId, List<SampleRecord> rows);
  Future<void> insertEvents(String sessionId, List<SessionEvent> events);
}

/// Acumula amostras e eventos em memória e grava em lotes, para não fazer
/// uma transação por amostra (50 por segundo). As escritas são serializadas:
/// um flush só começa quando o anterior termina. Se uma escrita falhar, as
/// linhas voltam para o buffer e são tentadas de novo no próximo flush.
class SessionLogger {
  SessionLogger(this.sessionId, this._sink, {this.maxBuffered = 250});

  final String sessionId;
  final SessionSink _sink;
  final int maxBuffered;

  List<SampleRecord> _samples = [];
  List<SessionEvent> _events = [];
  Future<void> _chain = Future.value();
  int _written = 0;
  Object? lastError;

  int get pending => _samples.length + _events.length;
  int get writtenSamples => _written;

  void logSample(SampleRecord row) {
    _samples.add(row);
    if (_samples.length == maxBuffered) flush();
  }

  void logEvent(SessionEvent event) => _events.add(event);

  Future<void> flush() {
    // O lote é separado agora (síncrono); a escrita espera a anterior terminar.
    final samples = _samples;
    final events = _events;
    _samples = [];
    _events = [];
    _chain = _chain.then((_) => _write(samples, events));
    return _chain;
  }

  Future<void> _write(List<SampleRecord> samples, List<SessionEvent> events) async {
    try {
      if (events.isNotEmpty) await _sink.insertEvents(sessionId, events);
    } catch (error) {
      lastError = error;
      _events = [...events, ..._events];
    }
    try {
      if (samples.isNotEmpty) await _sink.insertSamples(sessionId, samples);
      _written += samples.length;
    } catch (error) {
      lastError = error;
      _samples = [...samples, ..._samples];
    }
  }
}

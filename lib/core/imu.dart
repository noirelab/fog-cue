import 'dart:math' as math;

class Vector3 {
  const Vector3(this.x, this.y, this.z);

  static const nan = Vector3(double.nan, double.nan, double.nan);

  final double x;
  final double y;
  final double z;
}

/// Norma euclidiana: sqrt(x² + y² + z²). Em repouso, o acelerômetro dá ~9.81 m/s².
double magnitude(Vector3 v) => math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);

/// Uma amostra fundida de IMU.
///
/// - [timestamp]: milissegundos desde a época Unix (com fração).
/// - [accelerometer]: m/s², inclui a gravidade.
/// - [gyroscope]: rad/s.
class ImuSample {
  const ImuSample({required this.timestamp, required this.accelerometer, required this.gyroscope});

  final double timestamp;
  final Vector3 accelerometer;
  final Vector3 gyroscope;
}

/// Janela temporal de amostras entregue ao detector.
class SignalWindow {
  const SignalWindow({required this.startTimestamp, required this.endTimestamp, required this.samples});

  final double startTimestamp;
  final double endTimestamp;
  final List<ImuSample> samples;
}

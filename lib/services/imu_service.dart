import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import '../core/imu.dart';

typedef ImuAvailability = ({bool accelerometer, bool gyroscope});

/// O sensors_plus não tem consulta de disponibilidade: consideramos o sensor
/// disponível se ele entrega um evento em até 2 s.
Future<ImuAvailability> checkImuAvailability() async {
  Future<bool> emits(Stream<Object> stream) async {
    try {
      await stream.first.timeout(const Duration(seconds: 2));
      return true;
    } catch (_) {
      return false;
    }
  }

  final results = await Future.wait([emits(accelerometerEventStream()), emits(gyroscopeEventStream())]);
  return (accelerometer: results[0], gyroscope: results[1]);
}

/// Assina acelerômetro e giroscópio na mesma frequência e entrega amostras
/// fundidas. Devolve a função que encerra a captura.
///
/// Fusão: o acelerômetro dita o ritmo. Cada evento dele gera uma amostra com
/// a leitura mais recente do giroscópio (retenção de ordem zero). Os dois
/// sensores não são sincronizados pelo sistema, então a defasagem entre eles
/// fica em até 1 período (20 ms a 50 Hz). Antes da primeira leitura do
/// giroscópio, os valores dele são NaN (campo vazio no CSV).
///
/// Relógio: no Android, o sensors_plus converte o tempo do evento do sensor
/// para a escala do relógio do sistema. Os intervalos entre amostras vêm do
/// sensor (precisos) e os valores são comparáveis com DateTime.now().
void Function() startImu(int sampleRateHz, void Function(ImuSample sample) onSample) {
  final period = Duration(microseconds: (1e6 / sampleRateHz).round());
  var gyro = Vector3.nan;

  // Erros de stream (sensor ausente) não derrubam a sessão: o giroscópio
  // fica NaN e, sem acelerômetro, a taxa medida aparece como zero na tela.
  final gyroSub = gyroscopeEventStream(samplingPeriod: period).listen(
    (e) => gyro = Vector3(e.x, e.y, e.z),
    onError: (Object _) {},
  );
  final accSub = accelerometerEventStream(samplingPeriod: period).listen(
    (e) => onSample(ImuSample(
      timestamp: e.timestamp.microsecondsSinceEpoch / 1000.0,
      accelerometer: Vector3(e.x, e.y, e.z),
      gyroscope: gyro,
    )),
    onError: (Object _) {},
  );

  return () {
    unawaited(accSub.cancel());
    unawaited(gyroSub.cancel());
  };
}

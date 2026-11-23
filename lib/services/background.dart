import 'package:flutter/services.dart';

/// Serviço em primeiro plano do Android (MonitoringService.kt): notificação
/// fixa e CPU acordada, para a coleta e os cues seguirem com a tela apagada.
const _channel = MethodChannel('fog_cue/monitoring');

Future<void> startBackgroundMonitoring() => _channel.invokeMethod<void>('start');

Future<void> stopBackgroundMonitoring() => _channel.invokeMethod<void>('stop');

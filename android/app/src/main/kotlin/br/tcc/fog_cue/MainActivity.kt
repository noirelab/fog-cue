package br.tcc.fog_cue

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fog_cue/monitoring").setMethodCallHandler { call, result ->
            val intent = Intent(this, MonitoringService::class.java)
            when (call.method) {
                "start" -> {
                    askNotificationPermission()
                    MonitoringService.stopRequested = false
                    startForegroundService(intent)
                    result.success(null)
                }
                "stop" -> {
                    // Se o serviço ainda não subiu, ele mesmo se encerra logo
                    // depois do startForeground (ver MonitoringService).
                    MonitoringService.stopRequested = true
                    if (MonitoringService.running) stopService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // Sem a permissão o serviço roda igual, só a notificação não aparece.
    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }
}

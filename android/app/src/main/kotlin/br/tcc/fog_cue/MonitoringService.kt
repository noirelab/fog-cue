package br.tcc.fog_cue

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Serviço em primeiro plano que mantém o processo com prioridade alta e a CPU
 * acordada durante a sessão. A coleta e os cues continuam no Dart; este
 * serviço só impede o Android de estrangular o app com a tela apagada.
 */
class MonitoringService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Monitoramento", NotificationManager.IMPORTANCE_LOW)
        )
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("FoG Cue está monitorando")
            .setContentText("Toque para abrir")
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Teto de 12 h só como rede de segurança: o normal é soltar no onDestroy.
        // Readquire se o anterior expirou.
        if (wakeLock?.isHeld != true) {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "fogcue:monitoring")
                .apply { acquire(12 * 60 * 60 * 1000L) }
        }
        running = true
        // Parada pedida antes de o serviço subir: só agora, depois do
        // startForeground, é seguro encerrar sem o Android derrubar o app.
        if (stopRequested) stopSelf()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "monitoring"
        private const val NOTIFICATION_ID = 1

        // Lidos e escritos só na thread principal (MainActivity e ciclo de vida do serviço).
        var running = false
            private set
        var stopRequested = false
    }
}

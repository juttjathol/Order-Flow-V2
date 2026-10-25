package com.jathol.orderflow

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class ShopKeepAliveService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Order Flow"
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: "Shop server running"
        ensureChannel()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setContentIntent(open)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(NOTIF_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
            } else {
                startForeground(NOTIF_ID, notification)
            }
        } catch (e: Exception) {
            // Android 12+: starting a foreground service is denied when the app is
            // in the background (ForegroundServiceStartNotAllowedException
            // / SecurityException). Never crash the shop — just stop quietly;
            // the next foreground start will bring the keep-alive back.
            stopSelf()
            return START_NOT_STICKY
        }
        acquireWake()
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWake()
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val mgr = getSystemService(NotificationManager::class.java) ?: return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Shop server",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.setShowBadge(false)
        mgr.createNotificationChannel(channel)
    }

    private fun acquireWake() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(PowerManager::class.java) ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "jathol:shop").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    private fun releaseWake() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    companion object {
        private const val CHANNEL_ID = "jathol_shop_server"
        private const val NOTIF_ID = 8787
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        fun start(context: Context, title: String, text: String) {
            val intent = Intent(context, ShopKeepAliveService::class.java)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            try {
                ContextCompat.startForegroundService(context, intent)
            } catch (e: Exception) {
                // IllegalStateException when called from the background on
                // Android 12+ — a keep-alive is optional, a crash is not.
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ShopKeepAliveService::class.java))
        }
    }
}

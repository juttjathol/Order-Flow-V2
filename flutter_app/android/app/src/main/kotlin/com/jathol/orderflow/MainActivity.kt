package com.jathol.orderflow

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var cameraWait: MethodChannel.Result? = null

    private val camPerm = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val pending = cameraWait
        cameraWait = null
        try {
            pending?.success(granted == true)
        } catch (_: Exception) {
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        maybeAskNotifications()
                        val title = call.argument<String>("title") ?: "Order Flow"
                        val text = call.argument<String>("text") ?: "Shop server running"
                        ShopKeepAliveService.start(this, title, text)
                        result.success(true)
                    }
                    "stop" -> {
                        ShopKeepAliveService.stop(this)
                        result.success(true)
                    }
                    "askCamera" -> askCamera(result)
                    "alert" -> {
                        maybeAskNotifications()
                        val title = call.argument<String>("title") ?: "Ready to serve"
                        val text = call.argument<String>("text") ?: ""
                        postAlert(title, text)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PRINTER)
            .setMethodCallHandler(ShopPrinter(this))
    }

    private fun cameraGranted(): Boolean {
        return checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }

    private fun askCamera(result: MethodChannel.Result) {
        if (cameraGranted()) {
            result.success(true)
            return
        }
        val old = cameraWait
        cameraWait = result
        if (old != null) {
            try {
                old.success(false)
            } catch (_: Exception) {
            }
        }
        camPerm.launch(Manifest.permission.CAMERA)
    }

    private fun postAlert(title: String, text: String) {
        val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(
                ALERT_CH,
                "Kitchen ready",
                NotificationManager.IMPORTANCE_HIGH,
            )
            ch.enableVibration(true)
            ch.vibrationPattern = longArrayOf(0, 400, 200, 400, 200, 400)
            val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ch.setSound(
                sound,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            mgr.createNotificationChannel(ch)
        }
        try {
            val vib = if (Build.VERSION.SDK_INT >= 31) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (Build.VERSION.SDK_INT >= 26) {
                vib.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 400, 200, 400, 200, 400), -1))
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(longArrayOf(0, 400, 200, 400, 200, 400), -1)
            }
        } catch (_: Exception) {
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(this, ALERT_CH)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE)
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            NotificationManagerCompat.from(this).notify((System.currentTimeMillis() % 100000).toInt(), n)
        }
    }

    private fun maybeAskNotifications() {
        if (Build.VERSION.SDK_INT < 33) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            8787,
        )
    }

    companion object {
        private const val CHANNEL = "jathol/shop_keepalive"
        private const val PRINTER = "jathol/printer"
        private const val ALERT_CH = "jathol_ready"
    }
}

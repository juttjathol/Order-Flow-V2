package com.jathol.orderflow

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class ShopPrinter(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {
    private val spp: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bonded" -> {
                if (!ensureConnectPermission(result)) return
                try {
                    result.success(bondedList())
                } catch (e: SecurityException) {
                    result.error("bt_permission", "Bluetooth permission needed", null)
                } catch (e: Exception) {
                    result.error("bt_list", e.message, null)
                }
            }
            "print" -> {
                if (!ensureConnectPermission(result)) return
                val address = call.argument<String>("address") ?: ""
                val bytes = call.argument<ByteArray>("bytes")
                if (address.isEmpty() || bytes == null) {
                    result.error("bad_args", "address and bytes required", null)
                    return
                }
                Thread {
                    try {
                        write(address, bytes)
                        activity.runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        activity.runOnUiThread { result.error("bt_print", e.message, null) }
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    private fun adapter(): BluetoothAdapter? {
        val mgr = activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return mgr?.adapter ?: BluetoothAdapter.getDefaultAdapter()
    }

    private fun ensureConnectPermission(result: MethodChannel.Result): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val ok = activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        if (ok) return true
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT),
            9101,
        )
        result.error("bt_permission", "Bluetooth permission needed", null)
        return false
    }

    private fun bondedList(): List<Map<String, String>> {
        val ad = adapter() ?: return emptyList()
        if (Build.VERSION.SDK_INT >= 31) {
            val ok = activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
                PackageManager.PERMISSION_GRANTED
            if (!ok) throw SecurityException("BLUETOOTH_CONNECT")
        }
        return ad.bondedDevices.orEmpty().map { d ->
            mapOf(
                "name" to (d.name ?: "Printer"),
                "address" to (d.address ?: ""),
            )
        }
    }

    private fun write(address: String, bytes: ByteArray) {
        val ad = adapter() ?: throw IllegalStateException("Bluetooth unavailable")
        if (!ad.isEnabled) throw IllegalStateException("Bluetooth is off")
        val device = ad.getRemoteDevice(address)
        val socket = device.createRfcommSocketToServiceRecord(spp)
        try {
            ad.cancelDiscovery()
            socket.connect()
            val out = socket.outputStream
            out.write(bytes)
            out.flush()
        } finally {
            try {
                socket.close()
            } catch (_: Exception) {
            }
        }
    }
}

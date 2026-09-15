package com.jathol.orderflow

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.LinkedHashMap
import java.util.LinkedHashSet
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * "Reachable by any paired Bluetooth printer" (v1.1.68).
 *
 * Two transports behind one `print` call:
 *
 *  - Classic SPP/RFCOMM (the language most 58/80mm receipt printers speak,
 *    incl. clone boards that never answer an SDP query and refuse
 *    authenticated links). The connect ladder, learned from the wild:
 *      1. insecure RFCOMM on the SPP UUID
 *      2. insecure RFCOMM on every UUID the device advertised when bonded
 *      3. secure RFCOMM (some stacks demand it)
 *      4. raw RFCOMM channels 1 then 2 via reflection — skips SDP entirely
 *    The whole ladder runs twice with a short backoff: a printer still
 *    holding a dropped link from another app usually accepts the second round.
 *
 *  - BLE GATT for LE-only printers: connect, discover, take the first
 *    writable characteristic (common printer services preferred), write
 *    MTU-sized chunks — with per-chunk write responses when the
 *    characteristic supports them, otherwise paced no-response writes.
 *
 * 'auto' decides by device type and falls through: LE-typed devices go
 * GATT-first; everything else takes the RFCOMM ladder and then GATT.
 * No name, model or vendor list ever gates a printer.
 */
@SuppressLint("MissingPermission")
class ShopPrinter(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {

    companion object {
        private val SPP_UUID: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private val PREFERRED_BLE_SERVICES = listOf(
            "0000ff00", "0000ffe0", "0000fff0", "0000ae01",
            "49535343", "6e400001", "e7810a71", "0000ffe1",
        )
    }

    @Volatile
    private var chunkLatch: CountDownLatch? = null

    // v1.1.69 — hold the RFCOMM link open between jobs, like a real POS
    // does. Clone printers serve exactly one connection and take seconds
    // to release a dropped one: per-job connect/close made every second
    // print (and the sheet's Test button) fail with "could not reach".
    private val connLock = Any()
    private var heldSocket: BluetoothSocket? = null
    private var heldAddr = ""


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
            "ble_scan" -> bleScan(result)
            "forget" -> {
                // Release the printer so OTHER apps can reach it again
                // (we are the current owner while the link is held).
                val address = call.argument<String>("address") ?: ""
                Thread {
                    synchronized(connLock) {
                        if (heldSocket != null && (address.isEmpty() || heldAddr == address)) {
                            try { heldSocket?.close() } catch (_: Exception) {}
                            heldSocket = null
                        }
                    }
                    activity.runOnUiThread { result.success(true) }
                }.start()
            }
            "print" -> {
                if (!ensureConnectPermission(result)) return
                val address = call.argument<String>("address") ?: ""
                val bytes = call.argument<ByteArray>("bytes")
                val transport = call.argument<String>("transport") ?: "auto"
                if (address.isEmpty() || bytes == null || bytes.isEmpty()) {
                    result.error("bad_args", "address and bytes required", null)
                    return
                }
                Thread {
                    val notes = StringBuilder()
                    try {
                        val ad = adapter() ?: throw IllegalStateException("Bluetooth unavailable")
                        if (!ad.isEnabled) throw IllegalStateException("Bluetooth is off")
                        val device = ad.getRemoteDevice(address)
                        var ok = false
                        synchronized(connLock) {
                            if (transport != "ble") ok = tryHeld(device, address, bytes, notes) ||
                                writeSpp(device, bytes, notes)
                            if (!ok && transport != "spp") ok = writeBle(device, bytes, notes)
                        }
                        if (!ok) {
                            val why = notes.toString().ifEmpty { "printer refused every attempt" }
                            throw IllegalStateException(why.trim().take(300))
                        }
                        activity.runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        val msg = ((e.message ?: "failed") +
                            if (notes.isNotEmpty() && !e.message.orEmpty().contains(notes))
                                " — ${notes.toString().trim().take(220)}" else "").take(420)
                        activity.runOnUiThread { result.error("bt_print", msg, null) }
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
        if (activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
        ) return true
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
                "name" to (try { d.name } catch (_: SecurityException) { null } ?: "Printer"),
                "address" to (d.address ?: ""),
                "type" to d.type.toString(),
            )
        }
    }

    // ── Held-connection fast path ──────────────────────────────────────

    private fun tryHeld(
        device: BluetoothDevice,
        address: String,
        bytes: ByteArray,
        notes: StringBuilder,
    ): Boolean {
        val hs = heldSocket ?: return false
        if (heldAddr != address ||
            !hs.isConnected ||
            device.bondState != BluetoothDevice.BOND_BONDED
        ) {
            try { hs.close() } catch (_: Exception) {}
            heldSocket = null
            return false
        }
        return try {
            drain(hs, bytes)
            true
        } catch (e: Exception) {
            // The printer (or another app) dropped our link since the last
            // job — release it and let the full ladder reconnect.
            notes.append("stale link (" + e.javaClass.simpleName + "); ")
            try { hs.close() } catch (_: Exception) {}
            heldSocket = null
            false
        }
    }

    // ── Classic SPP ladder ─────────────────────────────────────────────

    private fun writeSpp(device: BluetoothDevice, bytes: ByteArray, notes: StringBuilder): Boolean {
        val ad = adapter() ?: return false
        if (device.bondState != BluetoothDevice.BOND_BONDED) {
            notes.append("pair the printer in Bluetooth settings first; ")
            return false
        }
        val uuids = LinkedHashSet<UUID>().apply {
            add(SPP_UUID)
            try {
                device.uuids?.forEach { pu -> pu.uuid?.let { add(it) } }
            } catch (_: Exception) {
            }
        }
        val tried = LinkedHashSet<String>()
        for (round in 1..2) {
            try {
                ad.cancelDiscovery()
            } catch (_: Exception) {
            }
            for (insecure in booleanArrayOf(true, false)) {
                for (u in uuids) {
                    val key = "${if (insecure) "i" else "s"}:$u"
                    if (!tried.add(key)) continue
                    if (sppConnectWrite(device, u, insecure, bytes, notes)) return true
                }
            }
            for (ch in intArrayOf(1, 2)) {
                if (!tried.add("raw:$ch")) continue
                if (sppRawChannel(device, ch, bytes, notes)) return true
            }
            if (round == 1) Thread.sleep(650)
        }
        return false
    }

    private fun sppConnectWrite(
        device: BluetoothDevice,
        uuid: UUID,
        insecure: Boolean,
        bytes: ByteArray,
        notes: StringBuilder,
    ): Boolean {
        var socket: BluetoothSocket? = null
        return try {
            socket = if (insecure) device.createInsecureRfcommSocketToServiceRecord(uuid)
            else device.createRfcommSocketToServiceRecord(uuid)
            socket.connect()
            drain(socket, bytes)
            heldSocket = socket
            heldAddr = device.address
            true
        } catch (e: Exception) {
            notes.append("${if (insecure) "insec" else "sec"} ${shortUuid(uuid)} ${simpleReason(e)}; ")
            try { socket?.close() } catch (_: Exception) {}
            false
        }
    }

    private fun sppRawChannel(
        device: BluetoothDevice,
        channel: Int,
        bytes: ByteArray,
        notes: StringBuilder,
    ): Boolean {
        var socket: BluetoothSocket? = null
        return try {
            val m = device.javaClass.getMethod(
                "createInsecureRfcommSocket", Integer.TYPE,
            )
            socket = m.invoke(device, channel) as BluetoothSocket
            socket.connect()
            drain(socket, bytes)
            heldSocket = socket
            heldAddr = device.address
            true
        } catch (e: Exception) {
            notes.append("raw$channel ${simpleReason(e)}; ")
            try { socket?.close() } catch (_: Exception) {}
            false
        }
    }

    private fun drain(socket: BluetoothSocket, bytes: ByteArray) {
        val out = socket.outputStream
        var off = 0
        while (off < bytes.size) {
            val n = minOf(1024, bytes.size - off)
            out.write(bytes, off, n)
            off += n
        }
        out.flush()
        // Tail guard: closing the instant flush returns can truncate the
        // last bytes on small printer firmwares.
        Thread.sleep(140)
    }

    // ── BLE GATT path ──────────────────────────────────────────────────

    private fun writeBle(device: BluetoothDevice, bytes: ByteArray, notes: StringBuilder): Boolean {
        var gatt: BluetoothGatt? = null
        var mtu = 23
        val connected = CountDownLatch(1)
        val ready = CountDownLatch(1)
        val target = arrayOfNulls<BluetoothGattCharacteristic>(1)
        val cb = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothGatt.STATE_CONNECTED) {
                    try {
                        g.requestMtu(185)
                    } catch (_: Exception) {
                    }
                    // Some stacks never fire onMtuChanged; discovery must not
                    // depend on it. Idempotent even if it runs twice.
                    try {
                        g.discoverServices()
                    } catch (_: Exception) {
                    }
                    connected.countDown()
                } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                    connected.countDown()
                    ready.countDown()
                }
            }

            override fun onMtuChanged(g: BluetoothGatt, newMtu: Int, state: Int) {
                if (newMtu in 23..517) mtu = newMtu
                try {
                    g.discoverServices()
                } catch (_: Exception) {
                    ready.countDown()
                }
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                target[0] = pickWriteChar(g)
                ready.countDown()
            }

            override fun onCharacteristicWrite(
                g: BluetoothGatt,
                c: BluetoothGattCharacteristic,
                st: Int,
            ) {
                chunkLatch?.countDown()
            }
        }
        return try {
            gatt = device.connectGatt(activity, false, cb, BluetoothDevice.TRANSPORT_LE)
            if (!connected.await(12, TimeUnit.SECONDS)) {
                notes.append("ble connect timeout; ")
                return false
            }
            if (!ready.await(9, TimeUnit.SECONDS)) {
                notes.append("ble discover timeout; ")
                return false
            }
            val ch = target[0] ?: run {
                notes.append("ble no writable characteristic; ")
                return false
            }
            val g = gatt ?: run {
                notes.append("ble gatt lost; ")
                return false
            }
            val chunk = (mtu - 3).coerceIn(20, 182)
            val withResp =
                (ch.properties and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0
            ch.writeType = if (withResp) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            var off = 0
            while (off < bytes.size) {
                val n = minOf(chunk, bytes.size - off)
                ch.value = bytes.copyOfRange(off, off + n)
                off += n
                if (withResp) {
                    val latch = CountDownLatch(1)
                    chunkLatch = latch
                    if (!g.writeCharacteristic(ch)) {
                        notes.append("ble write rejected; ")
                        return false
                    }
                    if (!latch.await(4, TimeUnit.SECONDS)) {
                        notes.append("ble write ack timeout; ")
                        return false
                    }
                } else {
                    if (!g.writeCharacteristic(ch)) {
                        notes.append("ble write rejected; ")
                        return false
                    }
                    Thread.sleep(12)
                }
            }
            Thread.sleep(120)
            true
        } catch (e: Exception) {
            notes.append("ble ${simpleReason(e)}; ")
            false
        } finally {
            chunkLatch = null
            try { gatt?.disconnect() } catch (_: Exception) {}
            try { gatt?.close() } catch (_: Exception) {}
        }
    }

    private fun pickWriteChar(g: BluetoothGatt): BluetoothGattCharacteristic? {
        val services = g.services ?: return null
        for (p in PREFERRED_BLE_SERVICES) {
            for (svc in services) {
                if (svc.uuid.toString().lowercase().startsWith(p)) {
                    writableIn(svc)?.let { return it }
                }
            }
        }
        for (svc in services) {
            writableIn(svc)?.let { return it }
        }
        return null
    }

    private fun writableIn(svc: BluetoothGattService): BluetoothGattCharacteristic? {
        val mask = BluetoothGattCharacteristic.PROPERTY_WRITE or
            BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
        for (c in svc.characteristics) {
            if (c.properties and mask != 0) return c
        }
        return null
    }

    // ── BLE discovery for the picker ───────────────────────────────────

    private fun bleScan(result: MethodChannel.Result) {
        val ad = adapter()
        if (ad == null || !ad.isEnabled) {
            result.error("bt_off", "Bluetooth is off", null)
            return
        }
        if (Build.VERSION.SDK_INT >= 31) {
            if (activity.checkSelfPermission(Manifest.permission.BLUETOOTH_SCAN) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    activity, arrayOf(Manifest.permission.BLUETOOTH_SCAN), 9102,
                )
                result.error("bt_permission", "Bluetooth permission needed", null)
                return
            }
        } else if (Build.VERSION.SDK_INT >= 23) {
            if (activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    activity, arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), 9103,
                )
                result.error("bt_permission", "Bluetooth permission needed", null)
                return
            }
        }
        val scanner = ad.bluetoothLeScanner
        if (scanner == null) {
            result.success(emptyList<Map<String, String>>())
            return
        }
        val found = LinkedHashMap<String, Map<String, String>>()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, r: ScanResult) {
                try {
                    val d = r.device
                    val name = try { d.name } catch (_: SecurityException) { null }
                    val addr = d.address ?: return
                    if (!found.containsKey(addr)) {
                        found[addr] = mapOf(
                            "name" to (name ?: addr),
                            "address" to addr,
                        )
                    }
                } catch (_: Exception) {
                }
            }
        }
        try {
            scanner.startScan(cb)
        } catch (e: Exception) {
            result.error("bt_scan", simpleReason(e), null)
            return
        }
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                scanner.stopScan(cb)
            } catch (_: Exception) {
            }
            result.success(found.values.toList())
        }, 5200)
    }

    private fun shortUuid(u: UUID): String = u.toString().substring(0, 8)

    private fun simpleReason(e: Exception): String {
        val m = e.message ?: e.javaClass.simpleName
        return m.replace(Regex("\\s+"), " ").take(90)
    }
}

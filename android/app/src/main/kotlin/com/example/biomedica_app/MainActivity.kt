package com.example.biomedica_app

import android.appwidget.AppWidgetManager
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity(),
    DataClient.OnDataChangedListener,
    MessageClient.OnMessageReceivedListener {
    private var wearableEventSink: EventChannel.EventSink? = null
    private var latestWearableReading: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Wearable.getDataClient(this)
            .addListener(
                this,
                Uri.parse("wear://*/biomedica/"),
                DataClient.FILTER_PREFIX,
            )
            .addOnFailureListener { error ->
                Log.e("BioMedicaWear", "Could not listen for watch data.", error)
            }
        Wearable.getMessageClient(this)
            .addListener(this)
            .addOnFailureListener { error ->
                Log.e("BioMedicaWear", "Could not listen for watch captures.", error)
            }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.biomedica/wearable_events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                wearableEventSink = events
                latestWearableReading?.let { events?.success(it) }
                loadPendingCaptures()
            }

            override fun onCancel(arguments: Any?) {
                wearableEventSink = null
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.biomedica/wearable",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "latest" -> result.success(latestWearableReading)
                "acknowledgeCapture" -> {
                    val captureId = call.argument<String>("captureId")
                    if (captureId.isNullOrBlank()) {
                        result.error(
                            "invalid_capture_id",
                            "Se requiere el identificador de captura.",
                            null,
                        )
                    } else {
                        Wearable.getDataClient(this)
                            .deleteDataItems(
                                Uri.parse("wear://*/biomedica/captures/$captureId"),
                                DataClient.FILTER_PREFIX,
                            )
                            .addOnSuccessListener { result.success(null) }
                            .addOnFailureListener { error ->
                                result.error(
                                    "capture_acknowledgement_failed",
                                    "No se pudo confirmar la captura recibida.",
                                    error.localizedMessage,
                                )
                            }
                    }
                }
                "connectedNodes" -> Wearable.getNodeClient(this).connectedNodes
                    .addOnSuccessListener { nodes ->
                        result.success(
                            nodes.map { node ->
                                mapOf(
                                    "id" to node.id,
                                    "displayName" to node.displayName,
                                    "isNearby" to node.isNearby,
                                )
                            },
                        )
                    }
                    .addOnFailureListener { error ->
                        result.error(
                            "wearable_nodes_failed",
                            "No se pudieron consultar los relojes conectados.",
                            error.localizedMessage,
                        )
                    }
                "openGalaxyWearable" -> {
                    val intent = packageManager.getLaunchIntentForPackage(
                        "com.samsung.android.app.watchmanager",
                    )
                    if (intent == null) {
                        result.success(false)
                    } else {
                        startActivity(intent)
                        result.success(true)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.biomedica/health_widget",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    val values = call.arguments as? Map<*, *>
                    if (values == null) {
                        result.error("invalid_arguments", "Expected widget values.", null)
                    } else {
                        HealthWidgetProvider.update(this, values)
                        result.success(null)
                    }
                }
                "pin" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                        !AppWidgetManager.getInstance(this).isRequestPinAppWidgetSupported
                    ) {
                        result.success(false)
                    } else {
                        val provider = ComponentName(this, HealthWidgetProvider::class.java)
                        result.success(
                            AppWidgetManager.getInstance(this)
                                .requestPinAppWidget(provider, null, null),
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.biomedica/health_connect",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSettings" -> try {
                    startActivity(
                        Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"),
                    )
                    result.success(null)
                } catch (error: ActivityNotFoundException) {
                    result.error(
                        "health_connect_settings_unavailable",
                        "No se encontró la pantalla de configuración de Health Connect.",
                        error.localizedMessage,
                    )
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        try {
            for (event in dataEvents) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val reading = readingFromDataItem(event.dataItem) ?: continue
                latestWearableReading = reading
                runOnUiThread { wearableEventSink?.success(reading) }
            }
        } finally {
            dataEvents.release()
        }
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        if (messageEvent.path != "/biomedica/capture") return
        try {
            val payload = JSONObject(String(messageEvent.data, Charsets.UTF_8))
            val reading = mutableMapOf<String, Any>(
                "captureRequested" to true,
                "captureId" to payload.getString("captureId"),
                "updatedAt" to payload.getLong("updatedAt"),
                "source" to payload.getString("source"),
                "deviceName" to payload.getString("deviceName"),
                "heartRate" to payload.getInt("heartRate"),
            )
            payload.optString("sensorReadingsJson")
                .takeIf(String::isNotBlank)
                ?.let { reading["sensorReadingsJson"] = it }
            payload.optString("availableSensorsJson")
                .takeIf(String::isNotBlank)
                ?.let { reading["availableSensorsJson"] = it }
            latestWearableReading = reading
            runOnUiThread { wearableEventSink?.success(reading) }
        } catch (error: Exception) {
            Log.e("BioMedicaWear", "Received an invalid watch capture.", error)
        }
    }

    private fun loadPendingCaptures() {
        Wearable.getDataClient(this)
            .getDataItems(
                Uri.parse("wear://*/biomedica/captures/"),
                DataClient.FILTER_PREFIX,
            )
            .addOnSuccessListener { items ->
                try {
                    for (item in items) {
                        val reading = readingFromDataItem(item) ?: continue
                        latestWearableReading = reading
                        wearableEventSink?.success(reading)
                    }
                } finally {
                    items.release()
                }
            }
            .addOnFailureListener { error ->
                Log.e("BioMedicaWear", "Could not load queued watch captures.", error)
            }
        }

    private fun readingFromDataItem(
        dataItem: com.google.android.gms.wearable.DataItem,
    ): Map<String, Any>? {
        val path = dataItem.uri.path.orEmpty()
        val isCapture = path.startsWith("/biomedica/captures/")
        if (path != "/biomedica/telemetry" && !isCapture) return null

        val data = DataMapItem.fromDataItem(dataItem).dataMap
        val reading = mutableMapOf<String, Any>(
            "updatedAt" to data.getLong("updatedAt"),
            "source" to data.getString("source").orEmpty(),
            "deviceName" to data.getString("deviceName").orEmpty(),
        )
        if (data.containsKey("heartRate")) {
            reading["heartRate"] = data.getInt("heartRate")
        }
        if (data.containsKey("spo2")) {
            reading["spo2"] = data.getInt("spo2")
        }
        if (data.containsKey("temperature")) {
            reading["temperature"] = data.getDouble("temperature")
        }
        data.getString("sensorReadingsJson")
            ?.takeIf(String::isNotBlank)
            ?.let { reading["sensorReadingsJson"] = it }
        data.getString("availableSensorsJson")
            ?.takeIf(String::isNotBlank)
            ?.let { reading["availableSensorsJson"] = it }
        if (isCapture || data.getBoolean("captureRequested", false)) {
            reading["captureRequested"] = true
            reading["captureId"] = data.getString("captureId")
                ?: path.substringAfterLast('/')
        }
        return reading
    }

    override fun onDestroy() {
        Wearable.getDataClient(this).removeListener(this)
        Wearable.getMessageClient(this).removeListener(this)
        super.onDestroy()
    }
}

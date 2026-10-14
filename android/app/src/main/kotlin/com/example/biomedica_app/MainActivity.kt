package com.example.biomedica_app

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.net.Uri
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable

class MainActivity : FlutterActivity(), DataClient.OnDataChangedListener {
    private var wearableEventSink: EventChannel.EventSink? = null
    private var latestWearableReading: Map<String, Any>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Wearable.getDataClient(this)
            .addListener(
                this,
                Uri.parse("wear://*/biomedica/telemetry"),
                DataClient.FILTER_PREFIX,
            )
            .addOnFailureListener { error ->
                Log.e("BioMedicaWear", "Could not listen for watch data.", error)
            }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.biomedica/wearable_events",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                wearableEventSink = events
                latestWearableReading?.let { events?.success(it) }
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
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        try {
            for (event in dataEvents) {
                if (event.type != DataEvent.TYPE_CHANGED ||
                    event.dataItem.uri.path != "/biomedica/telemetry"
                ) {
                    continue
                }

                val data = DataMapItem.fromDataItem(event.dataItem).dataMap
                val reading = mapOf(
                    "heartRate" to data.getInt("heartRate"),
                    "spo2" to data.getInt("spo2"),
                    "temperature" to data.getDouble("temperature"),
                    "updatedAt" to data.getLong("updatedAt"),
                    "source" to data.getString("source").orEmpty(),
                )
                latestWearableReading = reading
                runOnUiThread { wearableEventSink?.success(reading) }
            }
        } finally {
            dataEvents.release()
        }
    }

    override fun onDestroy() {
        Wearable.getDataClient(this).removeListener(this)
        super.onDestroy()
    }
}

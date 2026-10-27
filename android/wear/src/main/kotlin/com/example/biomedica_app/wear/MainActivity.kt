package com.example.biomedica_app.wear

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Bundle
import android.os.Build
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.util.Locale
import kotlin.math.roundToInt

class MainActivity : Activity(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var heartRateSensor: Sensor? = null
    private lateinit var connectionStatus: TextView
    private lateinit var sensorStatus: TextView
    private lateinit var heartRateValue: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildScreen()
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        heartRateSensor = sensorManager.getDefaultSensor(Sensor.TYPE_HEART_RATE)
        updatePhoneConnection()
        if (heartRateSensor == null) {
            sensorStatus.text = "Este reloj no ofrece sensor de pulso."
        } else if (checkSelfPermission(Manifest.permission.BODY_SENSORS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.BODY_SENSORS),
                REQUEST_BODY_SENSORS,
            )
        } else {
            startHeartRateSensor()
        }
    }

    override fun onResume() {
        super.onResume()
        if (::sensorManager.isInitialized &&
            checkSelfPermission(Manifest.permission.BODY_SENSORS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            startHeartRateSensor()
        }
    }

    override fun onPause() {
        if (::sensorManager.isInitialized) sensorManager.unregisterListener(this)
        super.onPause()
    }

    override fun onDestroy() {
        if (::sensorManager.isInitialized) sensorManager.unregisterListener(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BODY_SENSORS) return
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startHeartRateSensor()
        } else {
            sensorStatus.text = "Permite el acceso al sensor para medir el pulso."
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type != Sensor.TYPE_HEART_RATE) return
        val value = event.values.firstOrNull()?.roundToInt() ?: return
        if (value !in MIN_HEART_RATE..MAX_HEART_RATE) return
        heartRateValue.text = "$value BPM"
        sensorStatus.text = "Lectura actual del sensor del reloj"
        publishReading(value)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun startHeartRateSensor() {
        val sensor = heartRateSensor
        if (sensor == null) {
            sensorStatus.text = "Este reloj no ofrece sensor de pulso."
            return
        }
        sensorStatus.text = "Esperando lectura del sensor..."
        sensorManager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_NORMAL)
    }

    private fun buildScreen() {
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(24, 20, 24, 20)
            background = rounded(Color.rgb(244, 247, 252), 32)
        }

        content.addView(label("BioMedica", 19, Color.rgb(16, 38, 77), true))
        content.addView(
            label("MEDICIÓN DEL RELOJ", 10, Color.rgb(104, 122, 152), true),
        )
        content.addView(spacer(12))
        connectionStatus = label("Buscando teléfono...", 11, BLUE, true)
        content.addView(connectionStatus)
        content.addView(spacer(12))

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(18, 14, 18, 14)
            background = rounded(Color.WHITE, 24)
        }
        heartRateValue = label("-- BPM", 25, Color.rgb(209, 74, 84), true)
        card.addView(heartRateValue)
        content.addView(card, centeredParams())
        content.addView(spacer(12))
        sensorStatus = label(
            "Esperando permiso y sensor...",
            10,
            Color.rgb(104, 122, 152),
            false,
        )
        content.addView(sensorStatus)
        content.addView(spacer(8))
        content.addView(
            label(
                "Solo se transmite la frecuencia cardiaca recibida del sensor. "
                    + "No es un diagnóstico.",
                10,
                Color.rgb(104, 122, 152),
                false,
            ),
        )

        setContentView(content)
    }

    private fun publishReading(heartRate: Int) {
        val request = PutDataMapRequest.create("/biomedica/telemetry").apply {
            dataMap.putInt("heartRate", heartRate)
            dataMap.putLong("updatedAt", System.currentTimeMillis())
            dataMap.putString("source", "wear_os_sensor")
            dataMap.putString("deviceName", "${Build.MANUFACTURER} ${Build.MODEL}")
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(this).putDataItem(request)
            .addOnFailureListener { error ->
                connectionStatus.text = "Error al sincronizar: ${error.localizedMessage}"
                connectionStatus.setTextColor(Color.rgb(209, 74, 84))
            }
    }

    private fun updatePhoneConnection() {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                val phoneConnected = nodes.isNotEmpty()
                connectionStatus.text =
                    if (phoneConnected) "Teléfono conectado" else "Vincula el reloj al teléfono"
                connectionStatus.setTextColor(
                    if (phoneConnected) Color.rgb(19, 132, 90) else BLUE,
                )
            }
            .addOnFailureListener { error ->
                connectionStatus.text = "No disponible: ${error.localizedMessage}"
                connectionStatus.setTextColor(Color.rgb(209, 74, 84))
            }
    }

    private fun label(
        text: String,
        size: Int,
        color: Int,
        bold: Boolean,
    ) = TextView(this).apply {
        this.text = text
        textSize = size.toFloat()
        setTextColor(color)
        gravity = Gravity.CENTER
        if (bold) setTypeface(typeface, Typeface.BOLD)
    }

    private fun spacer(height: Int) = android.view.View(this).apply {
        layoutParams = LinearLayout.LayoutParams(1, height)
    }

    private fun centeredParams() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    )

    private fun rounded(color: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
    }

    companion object {
        private const val BLUE = -15239160
        private const val REQUEST_BODY_SENSORS = 100
        private const val MIN_HEART_RATE = 30
        private const val MAX_HEART_RATE = 220
    }
}

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
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID
import kotlin.math.roundToInt

class MainActivity : Activity(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private val availableSensors = mutableListOf<Sensor>()
    private val registeredSensorTypes = mutableSetOf<Int>()
    private val latestSensorValues = mutableMapOf<Int, List<Double>>()
    private val latestSensorEventTimestamps = mutableMapOf<Int, Long>()
    private val stepDetectorListener = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent?) {
            val triggerEvent = event ?: return
            latestSensorValues[triggerEvent.sensor.type] =
                triggerEvent.values.map(Float::toDouble)
            latestSensorEventTimestamps[triggerEvent.sensor.type] =
                triggerEvent.timestamp
            if (!sensorManager.requestTriggerSensor(this, triggerEvent.sensor)) {
                registeredSensorTypes.remove(triggerEvent.sensor.type)
                sensorStatus.text =
                    "La detección de pasos dejó de estar disponible."
            }
            publishReading()
        }
    }
    private val uiHandler = Handler(Looper.getMainLooper())
    private lateinit var connectionStatus: TextView
    private lateinit var sensorStatus: TextView
    private lateinit var captureButton: TextView
    private var latestHeartRate: Int? = null
    private var lastPublishedElapsedMs = 0L
    private var capturePending = false
    private var captureStartedAtNanos = 0L
    private val captureTimeout = Runnable {
        if (capturePending) {
            capturePending = false
            captureButton.isEnabled = true
            captureButton.text = "Tomar medición"
            sensorStatus.text =
                "No se obtuvo una lectura. Ajusta el reloj y vuelve a intentar."
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildScreen()
        sensorManager = getSystemService(SENSOR_SERVICE) as SensorManager
        discoverSensors()
        requestMissingPermissions()
        startSensors()
    }

    override fun onResume() {
        super.onResume()
        updatePhoneConnection()
        if (::sensorManager.isInitialized) startSensors()
    }

    override fun onPause() {
        if (::sensorManager.isInitialized) {
            sensorManager.unregisterListener(this)
            cancelStepDetector()
            registeredSensorTypes.clear()
        }
        super.onPause()
    }

    override fun onDestroy() {
        uiHandler.removeCallbacks(captureTimeout)
        if (::sensorManager.isInitialized) {
            sensorManager.unregisterListener(this)
            cancelStepDetector()
        }
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_SENSOR_PERMISSIONS) return
        startSensors()
    }

    override fun onSensorChanged(event: SensorEvent?) {
        val sensorEvent = event ?: return
        val type = sensorEvent.sensor.type
        val values = sensorEvent.values.map(Float::toDouble)
        latestSensorValues[type] = values
        latestSensorEventTimestamps[type] = sensorEvent.timestamp
        if (type == Sensor.TYPE_HEART_RATE) {
            val value = values.firstOrNull()?.roundToInt()
            if (value != null && value in MIN_HEART_RATE..MAX_HEART_RATE) {
                latestHeartRate = value
                if (capturePending &&
                    sensorEvent.timestamp >= captureStartedAtNanos
                ) {
                    capturePending = false
                    uiHandler.removeCallbacks(captureTimeout)
                    sendCapture(value)
                }
            }
        }

        val now = SystemClock.elapsedRealtime()
        if (now - lastPublishedElapsedMs >= LIVE_SYNC_INTERVAL_MS) {
            lastPublishedElapsedMs = now
            publishReading()
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun discoverSensors() {
        val discovered = sensorManager.getSensorList(Sensor.TYPE_ALL)
            .filter { isSupportedPublicSensor(it.type) }
            .distinctBy(Sensor::getType)
            .mapNotNull { sensorManager.getDefaultSensor(it.type) ?: it }
        availableSensors.clear()
        availableSensors.addAll(discovered)
    }

    private fun requestMissingPermissions() {
        val permissions = buildList {
            if (availableSensors.any { it.type == Sensor.TYPE_HEART_RATE } &&
                checkSelfPermission(heartRatePermission()) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                add(heartRatePermission())
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                availableSensors.any {
                    it.type == Sensor.TYPE_STEP_COUNTER ||
                        it.type == Sensor.TYPE_STEP_DETECTOR
                } &&
                checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) !=
                PackageManager.PERMISSION_GRANTED
            ) {
                add(Manifest.permission.ACTIVITY_RECOGNITION)
            }
        }
        if (permissions.isNotEmpty()) {
            requestPermissions(
                permissions.toTypedArray(),
                REQUEST_SENSOR_PERMISSIONS,
            )
        }
    }

    private fun startSensors() {
        if (!::sensorManager.isInitialized) return
        for (sensor in availableSensors) {
            if (sensor.type in registeredSensorTypes ||
                !hasSensorPermission(sensor.type)
            ) {
                continue
            }
            if (sensor.reportingMode == Sensor.REPORTING_MODE_SPECIAL_TRIGGER) {
                if (sensor.type == Sensor.TYPE_STEP_DETECTOR &&
                    sensorManager.requestTriggerSensor(stepDetectorListener, sensor)
                ) {
                    registeredSensorTypes.add(sensor.type)
                }
                continue
            }
            if (sensor.reportingMode == Sensor.REPORTING_MODE_ONE_SHOT) continue
            if (sensorManager.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_NORMAL,
                )
            ) {
                registeredSensorTypes.add(sensor.type)
            }
        }

        sensorStatus.text = when {
            Sensor.TYPE_HEART_RATE !in availableSensors.map(Sensor::getType) ->
                "Este reloj no expone un sensor de pulso compatible."
            Sensor.TYPE_HEART_RATE !in registeredSensorTypes ->
                "Permite el acceso al sensor para poder medir."
            else -> "Listo para medir. Mantén el reloj ajustado y quédate quieto."
        }
    }

    private fun cancelStepDetector() {
        val stepDetector = availableSensors.firstOrNull {
            it.type == Sensor.TYPE_STEP_DETECTOR
        } ?: return
        sensorManager.cancelTriggerSensor(stepDetectorListener, stepDetector)
    }

    private fun hasSensorPermission(type: Int): Boolean = when (type) {
        Sensor.TYPE_HEART_RATE ->
            checkSelfPermission(heartRatePermission()) ==
                PackageManager.PERMISSION_GRANTED
        Sensor.TYPE_STEP_COUNTER ->
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
                PackageManager.PERMISSION_GRANTED
        Sensor.TYPE_STEP_DETECTOR ->
            Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
                checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
                PackageManager.PERMISSION_GRANTED
        else -> true
    }

    private fun heartRatePermission(): String =
        if (Build.VERSION.SDK_INT >= 36) {
            "android.permission.health.READ_HEART_RATE"
        } else {
            Manifest.permission.BODY_SENSORS
        }

    private fun isSupportedPublicSensor(type: Int): Boolean = when (type) {
        Sensor.TYPE_HEART_RATE,
        Sensor.TYPE_STEP_COUNTER,
        Sensor.TYPE_STEP_DETECTOR,
        Sensor.TYPE_PRESSURE,
        Sensor.TYPE_ACCELEROMETER,
        Sensor.TYPE_GYROSCOPE,
        Sensor.TYPE_GYROSCOPE_UNCALIBRATED,
        Sensor.TYPE_MAGNETIC_FIELD,
        Sensor.TYPE_MAGNETIC_FIELD_UNCALIBRATED,
        Sensor.TYPE_LIGHT,
        Sensor.TYPE_AMBIENT_TEMPERATURE,
        Sensor.TYPE_PROXIMITY,
        Sensor.TYPE_RELATIVE_HUMIDITY,
        Sensor.TYPE_GRAVITY,
        Sensor.TYPE_LINEAR_ACCELERATION,
        Sensor.TYPE_ROTATION_VECTOR,
        Sensor.TYPE_GAME_ROTATION_VECTOR,
        Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR -> true
        else -> false
    }

    private fun sensorKey(type: Int): String = when (type) {
        Sensor.TYPE_HEART_RATE -> "heart_rate"
        Sensor.TYPE_STEP_COUNTER -> "step_counter"
        Sensor.TYPE_STEP_DETECTOR -> "step_detector"
        Sensor.TYPE_PRESSURE -> "atmospheric_pressure"
        Sensor.TYPE_ACCELEROMETER -> "accelerometer"
        Sensor.TYPE_GYROSCOPE -> "gyroscope"
        Sensor.TYPE_GYROSCOPE_UNCALIBRATED -> "gyroscope_uncalibrated"
        Sensor.TYPE_MAGNETIC_FIELD -> "magnetic_field"
        Sensor.TYPE_MAGNETIC_FIELD_UNCALIBRATED -> "magnetic_field_uncalibrated"
        Sensor.TYPE_LIGHT -> "ambient_light"
        Sensor.TYPE_AMBIENT_TEMPERATURE -> "ambient_temperature"
        Sensor.TYPE_PROXIMITY -> "proximity"
        Sensor.TYPE_RELATIVE_HUMIDITY -> "relative_humidity"
        Sensor.TYPE_GRAVITY -> "gravity"
        Sensor.TYPE_LINEAR_ACCELERATION -> "linear_acceleration"
        Sensor.TYPE_ROTATION_VECTOR -> "rotation_vector"
        Sensor.TYPE_GAME_ROTATION_VECTOR -> "game_rotation_vector"
        Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR -> "geomagnetic_rotation_vector"
        else -> "android_sensor_$type"
    }

    private fun sensorLabel(sensor: Sensor): String = when (sensor.type) {
        Sensor.TYPE_HEART_RATE -> "Frecuencia cardiaca"
        Sensor.TYPE_STEP_COUNTER -> "Pasos acumulados"
        Sensor.TYPE_STEP_DETECTOR -> "Detección de pasos"
        Sensor.TYPE_PRESSURE -> "Presión atmosférica"
        Sensor.TYPE_ACCELEROMETER -> "Acelerómetro"
        Sensor.TYPE_GYROSCOPE -> "Giroscopio"
        Sensor.TYPE_GYROSCOPE_UNCALIBRATED -> "Giroscopio sin calibrar"
        Sensor.TYPE_MAGNETIC_FIELD -> "Campo magnético"
        Sensor.TYPE_MAGNETIC_FIELD_UNCALIBRATED -> "Campo magnético sin calibrar"
        Sensor.TYPE_LIGHT -> "Luz ambiental"
        Sensor.TYPE_AMBIENT_TEMPERATURE -> "Temperatura ambiental"
        Sensor.TYPE_PROXIMITY -> "Proximidad"
        Sensor.TYPE_RELATIVE_HUMIDITY -> "Humedad ambiental"
        Sensor.TYPE_GRAVITY -> "Gravedad"
        Sensor.TYPE_LINEAR_ACCELERATION -> "Aceleración lineal"
        Sensor.TYPE_ROTATION_VECTOR -> "Vector de rotación"
        Sensor.TYPE_GAME_ROTATION_VECTOR -> "Vector de rotación de movimiento"
        Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR -> "Vector geomagnético"
        else -> sensor.name.ifBlank { "Sensor Android ${sensor.type}" }
    }

    private fun sensorUnit(type: Int): String = when (type) {
        Sensor.TYPE_HEART_RATE -> "BPM"
        Sensor.TYPE_STEP_COUNTER, Sensor.TYPE_STEP_DETECTOR -> "pasos"
        Sensor.TYPE_PRESSURE -> "hPa"
        Sensor.TYPE_ACCELEROMETER, Sensor.TYPE_GRAVITY,
        Sensor.TYPE_LINEAR_ACCELERATION -> "m/s²"
        Sensor.TYPE_GYROSCOPE, Sensor.TYPE_GYROSCOPE_UNCALIBRATED -> "rad/s"
        Sensor.TYPE_MAGNETIC_FIELD_UNCALIBRATED -> "µT"
        Sensor.TYPE_MAGNETIC_FIELD -> "µT"
        Sensor.TYPE_LIGHT -> "lx"
        Sensor.TYPE_AMBIENT_TEMPERATURE -> "°C ambiente"
        Sensor.TYPE_PROXIMITY -> "cm"
        Sensor.TYPE_RELATIVE_HUMIDITY -> "%"
        Sensor.TYPE_ROTATION_VECTOR,
        Sensor.TYPE_GAME_ROTATION_VECTOR,
        Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR -> "componentes"
        else -> "valor del sensor"
    }

    private fun sensorReadingsJson(): String = JSONObject().apply {
        for (sensor in availableSensors) {
            val values = latestSensorValues[sensor.type] ?: continue
            val eventTimestamp = latestSensorEventTimestamps[sensor.type] ?: continue
            val ageMillis =
                (SystemClock.elapsedRealtimeNanos() - eventTimestamp)
                    .coerceAtLeast(0L) / NANOS_PER_MILLISECOND
            put(
                sensorKey(sensor.type),
                JSONObject()
                    .put("label", sensorLabel(sensor))
                    .put("unit", sensorUnit(sensor.type))
                    .put("values", JSONArray(values))
                    .put("observedAt", System.currentTimeMillis() - ageMillis),
            )
        }
    }.toString()

    private fun availableSensorsJson(): String = JSONArray().apply {
        for (sensor in availableSensors) {
            put(
                JSONObject()
                    .put("key", sensorKey(sensor.type))
                    .put("label", sensorLabel(sensor))
                    .put("unit", sensorUnit(sensor.type))
                    .put("permissionRequired", !hasSensorPermission(sensor.type))
                    .put("collecting", sensor.type in registeredSensorTypes),
            )
        }
    }.toString()

    private fun currentDeviceName(): String =
        "${Build.MANUFACTURER} ${Build.MODEL}"

    private fun currentUpdatedAt(): Long = System.currentTimeMillis()

    private fun publishReading() {
        val request = PutDataMapRequest.create("/biomedica/telemetry").apply {
            dataMap.putInt("heartRate", latestHeartRate ?: 0)
            dataMap.putLong("updatedAt", currentUpdatedAt())
            dataMap.putString("source", "wear_os_sensor")
            dataMap.putString("deviceName", currentDeviceName())
            dataMap.putString("sensorReadingsJson", sensorReadingsJson())
            dataMap.putString("availableSensorsJson", availableSensorsJson())
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(this).putDataItem(request)
            .addOnFailureListener { error ->
                connectionStatus.text = "Error al sincronizar: ${error.localizedMessage}"
                connectionStatus.setTextColor(Color.rgb(209, 74, 84))
            }
    }

    private fun buildScreen() {
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(20), dp(22), dp(20), dp(20))
        }

        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val brandIcon = ImageView(this).apply {
            setImageResource(R.drawable.biomedica_launcher)
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = rounded(Color.WHITE, dp(14))
            contentDescription = "BioMedica"
        }
        header.addView(
            brandIcon,
            LinearLayout.LayoutParams(dp(42), dp(42)),
        )
        val brandText = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(10), 0, 0, 0)
            addView(label("BioMedica", 18, Color.WHITE, true))
            addView(label("MONITOREO PERSONAL", 8, LIGHT_BLUE, true))
        }
        header.addView(
            brandText,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        content.addView(header, centeredParams())
        content.addView(spacer(dp(22)))

        val connectionCard = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = rounded(DARK_CARD, dp(16))
        }
        val connectionDot = android.view.View(this).apply {
            background = rounded(Color.rgb(19, 132, 90), dp(20))
        }
        connectionCard.addView(
            connectionDot,
            LinearLayout.LayoutParams(dp(8), dp(8)),
        )
        connectionStatus = label("Buscando teléfono...", 10, Color.WHITE, true)
        connectionStatus.gravity = Gravity.START or Gravity.CENTER_VERTICAL
        connectionCard.addView(
            connectionStatus,
            LinearLayout.LayoutParams(
                0,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                1f,
            ),
        )
        content.addView(connectionCard, centeredParams())
        content.addView(spacer(dp(28)))

        val heartIcon = label("♥", 38, Color.rgb(255, 115, 132), true)
        content.addView(heartIcon, centeredParams())
        content.addView(spacer(dp(8)))
        content.addView(
            label("Toma una lectura confiable", 17, Color.WHITE, true),
            centeredParams(),
        )
        content.addView(spacer(dp(7)))
        content.addView(
            label(
                "Ajusta el reloj a tu muñeca y permanece quieto durante la medición.",
                10,
                LIGHT_BLUE,
                false,
            ),
            centeredParams(),
        )
        content.addView(spacer(dp(24)))

        captureButton = label(
            "TOMAR MEDICIÓN",
            12,
            Color.rgb(16, 38, 77),
            true,
        ).apply {
            background = rounded(Color.WHITE, dp(20))
            contentDescription = "Tomar medición y enviarla a BioMedica en el teléfono"
            isClickable = true
            isFocusable = true
            setPadding(dp(18), dp(15), dp(18), dp(15))
            setOnClickListener { beginCapture() }
        }
        content.addView(captureButton, centeredParams())
        content.addView(spacer(dp(14)))
        sensorStatus = label(
            "La lectura se enviará y guardará automáticamente en tu móvil.",
            10,
            LIGHT_BLUE,
            false,
        )
        content.addView(sensorStatus)
        content.addView(spacer(dp(16)))
        content.addView(
            label(
                "La interpretación se realiza en la app móvil. BioMedica no sustituye la valoración de un profesional.",
                9,
                LIGHT_BLUE,
                false,
            ),
        )

        setContentView(
            ScrollView(this).apply {
                isFillViewport = true
                setBackgroundColor(NAVY)
                addView(content)
            },
        )
    }

    private fun beginCapture() {
        if (capturePending) return
        if (Sensor.TYPE_HEART_RATE !in registeredSensorTypes) {
            sensorStatus.text =
                "Permite el acceso al sensor de pulso y vuelve a intentar."
            return
        }

        capturePending = true
        captureStartedAtNanos = SystemClock.elapsedRealtimeNanos()
        captureButton.isEnabled = false
        captureButton.text = "MIDIENDO..."
        sensorStatus.text = "Quédate quieto. Esperando una lectura nueva..."
        uiHandler.postDelayed(captureTimeout, CAPTURE_TIMEOUT_MS)
    }

    private fun sendCapture(heartRate: Int) {
        captureButton.text = "ENVIANDO..."
        sensorStatus.text = "Enviando la medición al teléfono..."
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                val phone = nodes.firstOrNull()
                if (phone == null) {
                    finishCapture("Vincula el reloj con un teléfono Android.")
                    return@addOnSuccessListener
                }

                val captureId = UUID.randomUUID().toString()
                val updatedAt = System.currentTimeMillis()
                val deviceName = currentDeviceName()
                val payload = JSONObject()
                    .put("captureId", captureId)
                    .put("captureRequested", true)
                    .put("heartRate", heartRate)
                    .put("updatedAt", updatedAt)
                    .put("source", "wear_os_sensor")
                    .put("deviceName", deviceName)
                    .put("sensorReadingsJson", sensorReadingsJson())
                    .put("availableSensorsJson", availableSensorsJson())
                    .toString()
                val request = PutDataMapRequest.create("$CAPTURE_PATH/$captureId").apply {
                    dataMap.putString("captureId", captureId)
                    dataMap.putBoolean("captureRequested", true)
                    dataMap.putInt("heartRate", heartRate)
                    dataMap.putLong("updatedAt", updatedAt)
                    dataMap.putString("source", "wear_os_sensor")
                    dataMap.putString("deviceName", deviceName)
                    dataMap.putString("sensorReadingsJson", sensorReadingsJson())
                    dataMap.putString("availableSensorsJson", availableSensorsJson())
                }.asPutDataRequest().setUrgent()

                Wearable.getDataClient(this).putDataItem(request)
                    .addOnSuccessListener {
                        Wearable.getMessageClient(this)
                            .sendMessage(
                                phone.id,
                                CAPTURE_MESSAGE_PATH,
                                payload.toByteArray(Charsets.UTF_8),
                            )
                            .addOnSuccessListener {
                                finishCapture(
                                    "Enviada. BioMedica la guardará e interpretará en el teléfono.",
                                )
                            }
                            .addOnFailureListener {
                                finishCapture(
                                    "Lectura en cola. Abre BioMedica en el teléfono para guardarla.",
                                )
                            }
                    }
                    .addOnFailureListener { error ->
                        finishCapture(
                            "No se pudo enviar: ${error.localizedMessage}",
                        )
                    }
            }
            .addOnFailureListener { error ->
                finishCapture(
                    "No se pudo comprobar el teléfono: ${error.localizedMessage}",
                )
            }
    }

    private fun finishCapture(message: String) {
        capturePending = false
        uiHandler.removeCallbacks(captureTimeout)
        captureButton.isEnabled = true
        captureButton.text = "TOMAR MEDICIÓN"
        sensorStatus.text = message
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

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).roundToInt()

    private fun rounded(color: Int, radius: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radius.toFloat()
    }

    companion object {
        private const val BLUE = -15239160
        private const val NAVY = -15722480
        private const val DARK_CARD = -14506454
        private const val LIGHT_BLUE = -4534043
        private const val CAPTURE_PATH = "/biomedica/captures"
        private const val CAPTURE_MESSAGE_PATH = "/biomedica/capture"
        private const val LIVE_SYNC_INTERVAL_MS = 8_000L
        private const val CAPTURE_TIMEOUT_MS = 20_000L
        private const val REQUEST_SENSOR_PERMISSIONS = 100
        private const val MIN_HEART_RATE = 30
        private const val MAX_HEART_RATE = 220
        private const val NANOS_PER_MILLISECOND = 1_000_000L
    }
}

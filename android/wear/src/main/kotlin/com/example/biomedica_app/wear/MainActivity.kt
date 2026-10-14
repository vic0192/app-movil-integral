package com.example.biomedica_app.wear

import android.app.Activity
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import java.util.Locale

class MainActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var readingIndex = 0
    private var phoneConnected = false
    private lateinit var connectionStatus: TextView
    private lateinit var heartRateValue: TextView
    private lateinit var oxygenValue: TextView
    private lateinit var temperatureValue: TextView

    private val demoHeartRates = intArrayOf(72, 75, 71, 78, 76, 73, 77, 74)
    private val demoOxygen = intArrayOf(98, 97, 99, 98, 96, 98, 97, 99)
    private val demoTemperatures =
        doubleArrayOf(36.6, 36.5, 36.7, 36.6, 36.8, 36.5, 36.6, 36.7)

    private val publishTask = object : Runnable {
        override fun run() {
            publishReading()
            handler.postDelayed(this, 3_000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildScreen()
        updatePhoneConnection()
        handler.post(publishTask)
    }

    override fun onDestroy() {
        handler.removeCallbacks(publishTask)
        super.onDestroy()
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
            label(
                "BIOWATCH · DATOS DE MUESTRA",
                10,
                Color.rgb(104, 122, 152),
                true,
            ),
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
        oxygenValue = label("-- % SpO₂", 16, Color.rgb(24, 138, 145), true)
        temperatureValue = label("-- °C", 16, BLUE, true)
        card.addView(heartRateValue)
        card.addView(spacer(5))
        card.addView(oxygenValue)
        card.addView(spacer(5))
        card.addView(temperatureValue)
        content.addView(card, centeredParams())
        content.addView(spacer(12))
        content.addView(
            label(
                "Mantén esta pantalla abierta para enviar datos al teléfono.",
                10,
                Color.rgb(104, 122, 152),
                false,
            ),
        )

        setContentView(content)
    }

    private fun publishReading() {
        val index = readingIndex % demoHeartRates.size
        val heartRate = demoHeartRates[index]
        val oxygen = demoOxygen[index]
        val temperature = demoTemperatures[index]
        heartRateValue.text = "$heartRate BPM"
        oxygenValue.text = "$oxygen % SpO₂"
        temperatureValue.text =
            String.format(Locale.getDefault(), "%.1f °C", temperature)
        readingIndex++
        updatePhoneConnection()

        val request = PutDataMapRequest.create("/biomedica/telemetry").apply {
            dataMap.putInt("heartRate", heartRate)
            dataMap.putInt("spo2", oxygen)
            dataMap.putDouble("temperature", temperature)
            dataMap.putLong("updatedAt", System.currentTimeMillis())
            dataMap.putString("source", "BioWatch Wear OS demo")
        }.asPutDataRequest().setUrgent()

        Wearable.getDataClient(this).putDataItem(request)
            .addOnFailureListener { error ->
                connectionStatus.text = "Error al enviar: ${error.localizedMessage}"
                connectionStatus.setTextColor(Color.rgb(209, 74, 84))
            }
    }

    private fun updatePhoneConnection() {
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                phoneConnected = nodes.isNotEmpty()
                connectionStatus.text =
                    if (phoneConnected) "Teléfono conectado" else "Vincula el reloj al teléfono"
                connectionStatus.setTextColor(
                    if (phoneConnected) Color.rgb(19, 132, 90) else BLUE,
                )
            }
            .addOnFailureListener { error ->
                connectionStatus.text =
                    "No disponible: ${error.localizedMessage}"
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
    }
}

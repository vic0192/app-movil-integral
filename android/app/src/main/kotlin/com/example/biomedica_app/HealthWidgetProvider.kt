package com.example.biomedica_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class HealthWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { appWidgetId ->
            appWidgetManager.updateAppWidget(appWidgetId, buildViews(context))
        }
    }

    companion object {
        private const val PREFERENCES = "biomedica_health_widget"
        private const val KEY_HEART_RATE = "heartRate"
        private const val KEY_SPO2 = "spo2"
        private const val KEY_TEMPERATURE = "temperature"
        private const val KEY_UPDATED_AT = "updatedAt"
        private const val KEY_IS_DEMO = "isDemo"

        fun update(context: Context, values: Map<*, *>) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            preferences.edit()
                .putString(KEY_HEART_RATE, values[KEY_HEART_RATE]?.toString().orEmpty())
                .putString(KEY_SPO2, values[KEY_SPO2]?.toString().orEmpty())
                .putString(KEY_TEMPERATURE, values[KEY_TEMPERATURE]?.toString().orEmpty())
                .putString(KEY_UPDATED_AT, values[KEY_UPDATED_AT]?.toString().orEmpty())
                .putBoolean(KEY_IS_DEMO, values[KEY_IS_DEMO] as? Boolean ?: true)
                .apply()

            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, HealthWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { appWidgetId ->
                manager.updateAppWidget(appWidgetId, buildViews(context))
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.health_widget)
            val hasHeartRate = preferences.getString(KEY_HEART_RATE, null).orEmpty().isNotBlank()
            val hasSpo2 = preferences.getString(KEY_SPO2, null).orEmpty().isNotBlank()
            val hasTemperature =
                preferences.getString(KEY_TEMPERATURE, null).orEmpty().isNotBlank()
            val isDemo = preferences.getBoolean(KEY_IS_DEMO, true)

            views.setTextViewText(
                R.id.widget_heart_rate,
                preferences.getString(KEY_HEART_RATE, null)?.takeIf { it.isNotBlank() } ?: "—",
            )
            views.setTextViewText(
                R.id.widget_spo2,
                preferences.getString(KEY_SPO2, null)?.takeIf { it.isNotBlank() } ?: "—",
            )
            views.setTextViewText(
                R.id.widget_temperature,
                preferences.getString(KEY_TEMPERATURE, null)?.takeIf { it.isNotBlank() } ?: "—",
            )
            views.setTextViewText(
                R.id.widget_status,
                if (isDemo) "DATOS DE DEMOSTRACIÓN" else "ÚLTIMAS LECTURAS",
            )
            val updatedAt = preferences.getString(KEY_UPDATED_AT, null).orEmpty()
            views.setTextViewText(
                R.id.widget_updated,
                if (updatedAt.isBlank()) "Abre BioMedica para sincronizar" else "Actualizado $updatedAt",
            )
            views.setTextViewText(
                R.id.widget_description,
                when {
                    hasHeartRate || hasSpo2 || hasTemperature -> "Resumen de signos vitales"
                    else -> "Sin lecturas sincronizadas"
                },
            )

            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }
            return views
        }
    }
}

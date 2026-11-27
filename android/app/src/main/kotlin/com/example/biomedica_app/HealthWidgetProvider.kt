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
        private const val KEY_BLOOD_PRESSURE = "bloodPressure"
        private const val KEY_UPDATED_AT = "updatedAt"
        const val EXTRA_URGENT_CALL_REQUEST =
            "com.biomedica.health_widget.URGENT_CALL_REQUEST"

        fun update(context: Context, values: Map<*, *>) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            preferences.edit()
                .putString(KEY_HEART_RATE, values[KEY_HEART_RATE]?.toString().orEmpty())
                .putString(KEY_SPO2, values[KEY_SPO2]?.toString().orEmpty())
                .putString(KEY_BLOOD_PRESSURE, values[KEY_BLOOD_PRESSURE]?.toString().orEmpty())
                .putString(KEY_UPDATED_AT, values[KEY_UPDATED_AT]?.toString().orEmpty())
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
            val hasBloodPressure =
                preferences.getString(KEY_BLOOD_PRESSURE, null).orEmpty().isNotBlank()

            views.setTextViewText(
                R.id.widget_heart_rate,
                preferences.getString(KEY_HEART_RATE, null)?.takeIf { it.isNotBlank() } ?: "—",
            )
            views.setTextViewText(
                R.id.widget_spo2,
                preferences.getString(KEY_SPO2, null)?.takeIf { it.isNotBlank() } ?: "—",
            )
            views.setTextViewText(
                R.id.widget_blood_pressure,
                preferences.getString(KEY_BLOOD_PRESSURE, null)?.takeIf { it.isNotBlank() } ?: "—",
            )
            views.setTextViewText(
                R.id.widget_status,
                if (hasHeartRate || hasSpo2 || hasBloodPressure) {
                    "ÚLTIMAS LECTURAS"
                } else {
                    "SIN LECTURAS"
                },
            )
            val updatedAt = preferences.getString(KEY_UPDATED_AT, null).orEmpty()
            views.setTextViewText(
                R.id.widget_updated,
                if (updatedAt.isBlank()) "Sin mediciones registradas" else "Actualizado $updatedAt",
            )
            views.setTextViewText(
                R.id.widget_description,
                when {
                    hasHeartRate || hasSpo2 || hasBloodPressure -> "Resumen de signos vitales"
                    else -> "Sin lecturas sincronizadas"
                },
            )

            val urgentCallIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra(EXTRA_URGENT_CALL_REQUEST, true)
            }
            val urgentCallPendingIntent = PendingIntent.getActivity(
                context,
                1,
                urgentCallIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(
                R.id.widget_urgent_call,
                urgentCallPendingIntent,
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

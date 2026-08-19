package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Band-battery widget — the Android sibling of OpenStrapBatteryWidget.swift.
 *
 * Battery is a live BLE value only the app knows (not part of /today), so this
 * never refreshes over the network: it renders the snapshot the app last wrote
 * (WidgetService.pushBattery → batt_pct / batt_charging / batt_name / batt_at)
 * while the band was connected. It says so in words until we have ever seen the
 * band, and the reading is muted once it's > 24 h old — we genuinely don't know the current
 * level if we haven't talked to the band. updatePeriodMillis re-renders every
 * ~6 h so the staleness flip happens without the app's help (it moves at most
 * once a day; see widget_band_battery_info.xml).
 */
class OpenStrapBatteryWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id, widgetData)
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        prefs: SharedPreferences,
    ) {
        val w = StrapWidgets
        val pal = w.pal(prefs)

        val pct = w.readInt(prefs, "batt_pct", -1)
        val charging = prefs.getBoolean("batt_charging", false)
        val at = w.readLong(prefs, "batt_at", 0)
        val rawName = (prefs.getString("batt_name", "") ?: "").trim()
        val name = rawName.ifEmpty { "Band" }
        val stale = at > 0L && (System.currentTimeMillis() / 1000 - at) > 86_400L
        // "charging" is a fact about the moment the app last wrote, so it goes
        // stale with the level it came with — the ⚡ used to sit there for days
        // after the band came off the puck. Mirrors BatteryEntry.chargingNow in
        // OpenStrapBatteryWidget.swift; keep the two in step.
        val chargingNow = charging && !stale

        // Colour rules mirror BatteryEntry.color: blue while charging, coral when
        // low, deep-coral when critical, green otherwise — muted with no/old data.
        val color = when {
            pct < 0 || stale -> pal.inkMuted
            chargingNow -> w.BLUE
            pct <= 10 -> w.RED
            pct <= 25 -> w.ORANGE
            else -> w.GREEN
        }
        // -1 = never seen the band: track only, and the word instead of a dash
        // over a ring at empty, which reads as "the band is at 0%".
        // -1 = never seen the band: track only, an empty centre, and the reason
        // on the caption line. A dash over a ring at empty reads as "0%".
        val t = if (pct >= 0) (pct / 100.0).coerceIn(0.0, 1.0) else -1.0
        val valueText = if (pct >= 0) "$pct%" else ""
        // Dimming alone does not SAY anything — a reading we can no longer
        // vouch for names itself, exactly as it does on iOS.
        val caption = when {
            pct < 0 -> "Not connected yet"
            stale -> "$name · last known"
            charging -> "⚡ $name"
            else -> name
        }

        val views = RemoteViews(context.packageName, R.layout.widget_band_battery)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.openAppIntent(context))
        views.setImageViewBitmap(
            R.id.ring_batt,
            w.ringBitmap(context, 64, 8f, pal.track, color, t),
        )
        views.setTextViewText(R.id.val_batt, valueText)
        views.setTextColor(R.id.val_batt, if (stale) pal.inkMuted else pal.ink)
        views.setTextViewText(R.id.name_batt, caption)
        views.setTextColor(R.id.name_batt, pal.inkMuted)
        manager.updateAppWidget(id, views)
    }
}

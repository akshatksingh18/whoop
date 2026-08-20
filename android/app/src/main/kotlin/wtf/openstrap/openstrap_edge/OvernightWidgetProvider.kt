package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The two things the band actually MEASURED while you slept — the Android
 * sibling of OpenStrapOvernightWidget.swift.
 *
 * It exists because the rebuilt home screen has three rings and HRV is not one
 * of them, so OpenStrapWidgetProvider dropped the HRV ring it used to carry.
 * This is where that number went, and it is a better home for it: HRV means
 * nothing against a population and everything against your own baseline.
 *
 * HRV IS DRAWN AGAINST YOUR OWN BASELINE AND NOTHING ELSE. Full ring at or
 * above it; with no baseline there is no denominator, so there is no arc. It
 * carries the Health domain accent and no colour judgement — a "0.8 x baseline
 * is amber" cut-off was invented on this surface once and appears in no
 * analytics output.
 */
class OvernightWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val w = StrapWidgets
        val pal = w.pal(widgetData)

        val views = if (!w.fresh(widgetData)) {
            RemoteViews(context.packageName, R.layout.widget_openstrap_nodata).apply {
                setTextColor(R.id.nodata_title, pal.ink)
                setTextColor(R.id.nodata_body, pal.inkMuted)
            }
        } else {
            val hrv = w.readInt(widgetData, "hrv", -1)
            val base = w.readInt(widgetData, "hrv_baseline", -1)
            val rhr = w.readInt(widgetData, "rhr", -1)
            val frac = if (hrv >= 0 && base > 0) {
                (hrv.toDouble() / base).coerceAtMost(1.0)
            } else {
                -1.0
            }
            RemoteViews(context.packageName, R.layout.widget_overnight).apply {
                setImageViewBitmap(
                    R.id.dial_hrv,
                    w.dialBitmap(
                        context, 38, 5.5f, pal.track,
                        if (hrv >= 0) pal.good else pal.inkMuted, frac,
                        R.drawable.ic_widget_hrv,
                    ),
                )
                setTextColor(R.id.cap_hrv, pal.inkMuted)
                setTextColor(R.id.cap_rhr, pal.inkMuted)
                // The absence is a WORD, in the sentence colour. Never a dash,
                // and never a zero — a zero RMSSD is a claim about a heart.
                setTextViewText(R.id.val_hrv, if (hrv >= 0) "$hrv ms" else "Not measured")
                setTextColor(R.id.val_hrv, if (hrv >= 0) pal.good else pal.ink2)
                setTextViewText(R.id.sub_hrv, if (base > 0) "base $base ms" else "")
                setTextColor(R.id.sub_hrv, pal.inkMuted)
                setTextViewText(R.id.val_rhr, if (rhr >= 0) "$rhr bpm" else "Not measured")
                setTextColor(R.id.val_rhr, if (rhr >= 0) pal.ink else pal.ink2)
                // Why, when there is a why — the held-over night's reason
                // first, then the night's own, and nothing when neither said.
                // A reason is never written here.
                val why = (widgetData.getString("overnight_why", "") ?: "")
                    .ifEmpty { w.ring(widgetData, "sleep").why }
                val foot = if (hrv < 0 && rhr < 0) why else ""
                setViewVisibility(R.id.foot, if (foot.isEmpty()) View.GONE else View.VISIBLE)
                setTextViewText(R.id.foot, foot)
                setTextColor(R.id.foot, pal.inkMuted)
            }
        }
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.openAppIntent(context))
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }
}

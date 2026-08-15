package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen metrics widget — the Android sibling of OpenStrapWidget.swift
 * (Readiness headline + the Strain · Sleep · HRV rings, Ember on Paper).
 *
 * Renders the snapshot WidgetService.push() writes through home_widget; the app
 * broadcasts an update after every sync (this provider name is already wired in
 * widget_service.dart). Unlike iOS there is no self-refresh fetch of /today —
 * updatePeriodMillis just re-renders the cached snapshot so the theme/staleness
 * stay honest when the app hasn't run for a while.
 *
 * Two layouts, like the iOS families: a 2×2 ring grid (small) and a readiness
 * row over the triple rings (medium). On Android 12+ the launcher picks by live
 * size (RemoteViews size map); below that we choose from the widget's min width.
 */
class OpenStrapWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) render(context, appWidgetManager, id, widgetData)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        render(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun render(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        prefs: SharedPreferences,
    ) {
        val views: RemoteViews = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            RemoteViews(
                mapOf(
                    SizeF(110f, 110f) to build(context, prefs, small = true),
                    SizeF(250f, 110f) to build(context, prefs, small = false),
                ),
            )
        } else {
            val minW = manager.getAppWidgetOptions(id)
                .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            build(context, prefs, small = minW in 1..249)
        }
        manager.updateAppWidget(id, views)
    }

    private fun build(context: Context, prefs: SharedPreferences, small: Boolean): RemoteViews {
        val w = StrapWidgets
        val pal = w.pal(prefs)

        // `has_data` alone was never enough: it is frozen when the app pushes,
        // so a phone that stops syncing keeps a week-old readiness on the home
        // screen looking exactly like this morning's. StrapWidgets.fresh() ages
        // `updated_at` here, on every render.
        if (!w.fresh(prefs)) return buildNoData(context, pal)

        // Snapshot (sentinels: -1 = no data — mirrors OpenStrapEntry).
        val readiness = w.readInt(prefs, "readiness", -1)
        val strain = w.readDouble(prefs, "strain", -1.0)
        val sleepMin = w.readInt(prefs, "sleep_min", -1)
        // -1 = none. The Dart writer uses the same sentinel; the ring below
        // already gates on needMin > 0, so an unknown need leaves it empty
        // instead of filling against a fabricated 8h denominator.
        val needMin = w.readInt(prefs, "sleep_need_min", -1)
        val hrv = w.readInt(prefs, "hrv", -1)
        val hrvBaseline = w.readInt(prefs, "hrv_baseline", -1)

        // Ring fractions — negative means "nothing measured", so ringBitmap
        // draws the track alone rather than an arc pinned at empty (which reads
        // as a real value of zero).
        val readinessT = if (readiness >= 0) readiness / 100.0 else -1.0
        val tier = w.readInt(prefs, "readiness_tier", -1)
        val readinessArc = w.readinessArc(tier)
        val readinessColor = w.readinessColor(tier, pal)
        // 0-21 is the headline scale strainScore maps TRIMP onto
        // (analytics/lib/src/onehz/clinical/load_trimp.dart:104-122).
        val strainT = if (strain >= 0) (strain / 21.0).coerceAtMost(1.0) else -1.0
        val sleepT = if (sleepMin >= 0 && needMin > 0) {
            (sleepMin.toDouble() / needMin).coerceAtMost(1.0)
        } else {
            -1.0
        }
        // HRV against YOUR OWN baseline: a full ring is at or above it. There
        // is no population scale for RMSSD, so with no baseline there is no
        // denominator and the arc is not drawn. This used to divide by a
        // hard-coded 100 (and by 1.5 x baseline), neither of which exists
        // anywhere in the pipeline.
        val hrvT = if (hrv >= 0 && hrvBaseline > 0) {
            (hrv.toDouble() / hrvBaseline).coerceAtMost(1.0)
        } else {
            -1.0
        }
        // HRV carries its domain accent and no colour judgement: a "0.8 x
        // baseline is amber" cut-off was invented here and appears in no
        // analytics output.
        val hrvColor = if (hrv >= 0) w.GREEN else w.N400

        // "" = no measurement. A bare dash is the one rendering the phone's
        // grammar forbids outright.
        val strainText = if (strain >= 0) String.format("%.1f", strain) else ""
        val readinessText = if (readiness >= 0) "$readiness" else ""
        val hrvText = if (hrv >= 0) "$hrv" else ""

        val layout = if (small) R.layout.widget_openstrap_small else R.layout.widget_openstrap
        val ringDp = if (small) 40 else 56
        val strokeDp = if (small) 5f else 7f

        val views = RemoteViews(context.packageName, layout)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.openAppIntent(context))

        // Readiness leads the row; its VALUE carries the readiness colour (the
        // iOS headline treatment, compressed into a cell).
        views.setImageViewBitmap(
            R.id.ring_readiness,
            w.ringBitmap(context, ringDp, strokeDp, pal.track, readinessArc, readinessT),
        )
        views.setTextViewText(R.id.val_readiness, readinessText)
        views.setTextColor(R.id.val_readiness, readinessColor)
        views.setTextColor(R.id.cap_readiness, pal.inkMuted)

        fun metric(ring: Int, value: Int, cap: Int, bmpColor: Int, t: Double, text: String) {
            views.setImageViewBitmap(
                ring,
                w.ringBitmap(context, ringDp, strokeDp, pal.track, bmpColor, t),
            )
            views.setTextViewText(value, text)
            views.setTextColor(value, pal.ink)
            views.setTextColor(cap, pal.inkMuted)
        }
        metric(R.id.ring_strain, R.id.val_strain, R.id.cap_strain, w.PURPLE, strainT, strainText)
        metric(R.id.ring_sleep, R.id.val_sleep, R.id.cap_sleep, w.BLUE, sleepT, w.hm(sleepMin))
        metric(R.id.ring_hrv, R.id.val_hrv, R.id.cap_hrv, hrvColor, hrvT, hrvText)
        return views
    }

    private fun buildNoData(context: Context, pal: StrapWidgets.Pal): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_openstrap_nodata)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, StrapWidgets.openAppIntent(context))
        views.setTextColor(R.id.nodata_title, pal.ink)
        views.setTextColor(R.id.nodata_body, pal.inkMuted)
        return views
    }
}

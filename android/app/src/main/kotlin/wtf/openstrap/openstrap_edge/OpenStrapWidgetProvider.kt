package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen metrics widget — the Android sibling of OpenStrapWidget.swift.
 *
 * IT IS THE SAME THREE RINGS AS HOME: Recovery · Strain · Sleep, in that order,
 * the icon inside the dial and the number under it. It used to be four rings
 * (Ready · Strain · Sleep · HRV) with the number inside, which was the previous
 * design system's home screen; HRV stopped being one of Home's rings in the
 * rebuild and lives on OvernightWidgetProvider instead.
 *
 * Renders the snapshot WidgetService.push() writes through home_widget; the app
 * broadcasts an update after every derive and every foreground. There is no
 * network on this side — updatePeriodMillis only re-renders the cached snapshot
 * so the theme and the staleness rule stay honest when the app hasn't run.
 *
 * Two layouts, like the iOS families: three rows (2x2) and three columns (4x2),
 * sharing every id so there is one render path. On Android 12+ the launcher
 * picks by live size; below that we choose from the widget's min width.
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

    /** One ring's three views and the icon that goes in its dial. */
    private class Slot(
        val key: String,
        val label: String,
        val iconRes: Int,
        val dial: Int,
        val cap: Int,
        val value: Int,
        val sub: Int,
    )

    private val slots = listOf(
        Slot("recovery", "RECOVERY", R.drawable.ic_widget_recovery,
            R.id.dial_recovery, R.id.cap_recovery, R.id.val_recovery, R.id.sub_recovery),
        Slot("strain", "STRAIN", R.drawable.ic_widget_strain,
            R.id.dial_strain, R.id.cap_strain, R.id.val_strain, R.id.sub_strain),
        Slot("sleep", "SLEEP", R.drawable.ic_widget_sleep,
            R.id.dial_sleep, R.id.cap_sleep, R.id.val_sleep, R.id.sub_sleep),
    )

    private fun build(context: Context, prefs: SharedPreferences, small: Boolean): RemoteViews {
        val w = StrapWidgets
        val pal = w.pal(prefs)

        // `has_data` alone was never enough: it is frozen when the app pushes,
        // so a phone that stops syncing keeps a week-old readiness on the home
        // screen looking exactly like this morning's. StrapWidgets.fresh() ages
        // `updated_at` here, on every render.
        if (!w.fresh(prefs)) return buildNoData(context, pal)

        val layout = if (small) R.layout.widget_openstrap_small else R.layout.widget_openstrap
        val dialDp = if (small) 30 else 44
        val strokeDp = if (small) 4.5f else 6f
        val views = RemoteViews(context.packageName, layout)
        views.setInt(R.id.widget_root, "setBackgroundResource", pal.bgRes)
        views.setOnClickPendingIntent(R.id.widget_root, w.openAppIntent(context))

        // Recovery wears its band's colour (from the published tier — the
        // cut-offs are never re-derived here), the other two their domain accent.
        val tier = w.readInt(prefs, "readiness_tier", -1)
        var gap: Pair<String, String>? = null

        for (slot in slots) {
            val r = w.ring(prefs, slot.key)
            val accent = when (slot.key) {
                "recovery" -> w.tierColor(tier, pal)
                "strain" -> pal.move
                else -> pal.sleep
            }
            val tint = r.color(accent, pal)
            views.setImageViewBitmap(
                slot.dial,
                w.dialBitmap(context, dialDp, strokeDp, pal.track, tint, r.frac, slot.iconRes),
            )
            views.setTextViewText(slot.cap, slot.label)
            views.setTextColor(slot.cap, pal.inkMuted)
            // The absence takes the SENTENCE colour rather than the numeral
            // one, because it is a sentence: "No sleep" in full-weight ink
            // would read as a score.
            views.setTextViewText(slot.value, r.value)
            views.setTextColor(slot.value, if (r.measured) pal.ink else pal.ink2)
            if (!small) {
                views.setTextViewText(slot.sub, r.sub)
                views.setTextColor(slot.sub, pal.inkMuted)
            }
            if (gap == null && r.why.isNotEmpty()) gap = slot.label to r.why
        }

        // The first ring that is missing and said why. One line is what a
        // widget can afford; the rest is one tap away in the app.
        if (!small) {
            val g = gap
            if (g == null) {
                views.setViewVisibility(R.id.gap_row, View.GONE)
            } else {
                views.setViewVisibility(R.id.gap_row, View.VISIBLE)
                views.setTextViewText(R.id.gap_row, "${g.first} · ${g.second}")
                views.setTextColor(R.id.gap_row, pal.inkMuted)
            }
        }
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

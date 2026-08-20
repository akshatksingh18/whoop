package wtf.openstrap.openstrap_edge

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Last night, on its own — the Android sibling of OpenStrapSleepWidget.swift.
 *
 * The one number people look for before they open anything. It is the trio's
 * sleep ring at full size plus the figure that does not fit in a third of a
 * card: efficiency.
 *
 * Everything it renders is resolved by WidgetService.push, including whether
 * there is a need to measure the night against at all — a night with no LEARNED
 * need draws an open track and says so rather than filling against a hardcoded
 * 8 h that is not this user's.
 */
class SleepWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val w = StrapWidgets
        val pal = w.pal(widgetData)
        val fresh = w.fresh(widgetData)

        val views = if (!fresh) {
            RemoteViews(context.packageName, R.layout.widget_openstrap_nodata).apply {
                setTextColor(R.id.nodata_title, pal.ink)
                setTextColor(R.id.nodata_body, pal.inkMuted)
            }
        } else {
            val r = w.ring(widgetData, "sleep")
            val eff = w.readInt(widgetData, "sleep_efficiency", -1)
            RemoteViews(context.packageName, R.layout.widget_sleep).apply {
                setImageViewBitmap(
                    R.id.dial_sleep,
                    w.dialBitmap(
                        context, 52, 7f, pal.track, r.color(pal.sleep, pal), r.frac,
                        R.drawable.ic_widget_sleep,
                    ),
                )
                setTextColor(R.id.cap_sleep, pal.inkMuted)
                setTextViewText(R.id.val_sleep, r.value)
                setTextColor(R.id.val_sleep, if (r.measured) pal.ink else pal.ink2)
                setTextViewText(R.id.sub_sleep, r.sub)
                setTextColor(R.id.sub_sleep, pal.inkMuted)
                // Efficiency when the night has one, the reason when it does
                // not, and nothing at all when there is neither — never a dash.
                val foot = when {
                    r.measured && eff >= 0 -> "$eff% efficient"
                    !r.measured -> r.why
                    else -> ""
                }
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

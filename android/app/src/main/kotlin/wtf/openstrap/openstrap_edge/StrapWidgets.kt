package wtf.openstrap.openstrap_edge

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF

/**
 * Shared bits for the home-screen widgets (see OpenStrapWidgetProvider /
 * OpenStrapBatteryWidgetProvider) — the Ember-on-Paper palette, readers for the
 * home_widget snapshot, and the arc-ring renderer.
 *
 * The palette and all value/colour rules mirror the Swift widgets under
 * ios/OpenStrapWidget exactly, so the two platforms read as the same product. Rings are
 * pre-rendered as bitmaps because RemoteViews can't draw arcs.
 */
internal object StrapWidgets {

    // ── Ember on Paper / Char (mirrors Pal in OpenStrapWidget.swift) ─────────
    class Pal(val bgRes: Int, val ink: Int, val inkMuted: Int, val track: Int)

    private val LIGHT = Pal(
        R.drawable.widget_bg_paper, 0xFF1A1714.toInt(),
        0xFFA59C90.toInt(), 0xFFECE7DF.toInt(),
    )
    private val DARK = Pal(
        R.drawable.widget_bg_char, 0xFFF1ECE3.toInt(),
        0xFF7E7466.toInt(), 0xFF2A251F.toInt(),
    )

    const val CORAL = 0xFFFF5A36.toInt()
    const val CORAL_DEEP = 0xFFE8431F.toInt()
    const val GOOD = 0xFF2BB673.toInt()
    const val WARN = 0xFFF5A623.toInt()
    const val BAD = 0xFFE5484D.toInt()
    const val SLEEP_BLUE = 0xFF7CA8F0.toInt()

    /**
     * Readiness tier -> colour. The THRESHOLDS are not here: Dart publishes
     * `readiness_tier` (see `readinessBand` in lib/ui2/screens/home_screen.dart)
     * so the phone, the widget, the watch and Siri cannot disagree about what a
     * score of 65 means. Never re-derive a band from the raw number.
     */
    fun readinessColor(tier: Int, pal: Pal): Int = when (tier) {
        3, 2 -> GOOD
        1 -> WARN
        0 -> BAD
        else -> pal.inkMuted
    }

    /// The app mirrors its in-app appearance into `theme_dark` (see
    /// WidgetService.setThemeDark) — same source of truth as the iOS widgets.
    fun pal(prefs: SharedPreferences): Pal =
        if (prefs.getBoolean("theme_dark", false)) DARK else LIGHT

    // ── home_widget snapshot readers ─────────────────────────────────────────
    // home_widget's Android store isn't type-stable across Dart types: Dart ints
    // arrive as Int, but Dart doubles are stored as RAW LONG BITS
    // (putLong(doubleToRawLongBits)) — see HomeWidgetPlugin.saveWidgetData. Read
    // through `all[key]` and coerce, so a type drift never crashes a widget.

    fun readInt(prefs: SharedPreferences, key: String, def: Int): Int =
        when (val v = prefs.all[key]) {
            is Int -> v
            is Long -> v.toInt()
            is Float -> v.toInt()
            else -> def
        }

    fun readDouble(prefs: SharedPreferences, key: String, def: Double): Double =
        when (val v = prefs.all[key]) {
            is Long -> Double.fromBits(v) // Dart double → raw bits (see above)
            is Float -> v.toDouble()
            is Int -> v.toDouble()
            else -> def
        }

    // ── formatting ───────────────────────────────────────────────────────────
    /** "45m" / "7h 05m" — the phone's own `hm()` (lib/ui2/screens/home_screen.dart),
     *  so the same night reads identically on the phone, the widget and iOS.
     *  Empty for "no measurement": never a bare dash. */
    fun hm(min: Int): String {
        if (min < 0) return ""
        if (min < 60) return "${min}m"
        return String.format("%dh %02dm", min / 60, min % 60)
    }

    // ── ring renderer ────────────────────────────────────────────────────────
    /** Track circle + progress arc from 12 o'clock, round caps — the iOS Ring. */
    fun ringBitmap(
        context: Context,
        sizeDp: Int,
        strokeDp: Float,
        trackColor: Int,
        color: Int,
        t: Double,
    ): Bitmap {
        val density = context.resources.displayMetrics.density
        val px = (sizeDp * density).toInt().coerceAtLeast(1)
        val stroke = strokeDp * density
        val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
        }
        val inset = stroke / 2f
        val rect = RectF(inset, inset, px - inset, px - inset)
        paint.color = trackColor
        canvas.drawArc(rect, 0f, 360f, false, paint)
        val frac = t.coerceIn(0.0, 1.0)
        if (frac > 0) {
            paint.color = color
            canvas.drawArc(rect, -90f, (360.0 * frac).toFloat(), false, paint)
        }
        return bmp
    }

    /** Tap anywhere on a widget → open the app. */
    fun openAppIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

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
 * OpenStrapBatteryWidgetProvider) — the palette, readers for the home_widget
 * snapshot, the freshness rule, and the arc-ring renderer.
 *
 * The palette and all value/colour rules mirror the Swift widgets under
 * ios/OpenStrapWidget exactly, so the two platforms read as the same product.
 * Both now spend lib/ui2/theme.dart's tokens rather than the retired
 * lib/theme/tokens.dart ones. Rings are pre-rendered as bitmaps because
 * RemoteViews can't draw arcs.
 */
internal object StrapWidgets {

    // ── lib/ui2/theme.dart (mirrors Pal in OpenStrapWidget.swift) ───────────
    // A widget is a card, so surfaces are `P.card` over a `P.track` ring track
    // and `P.ink3` captions. `onGood`/`onWarn`/`onBad`/`onNone` are the tier
    // accents as TEXT — `P.on()`'s output, which nudges an accent toward the
    // page ink until it clears WCAG AA on the worst surface it can land on.
    // Arcs are non-text UI and spend the raw `C.*` pigment below.
    class Pal(
        val bgRes: Int,
        val ink: Int,
        val inkMuted: Int,
        val track: Int,
        val onGood: Int,
        val onWarn: Int,
        val onBad: Int,
        val onNone: Int,
    )

    private val LIGHT = Pal(
        R.drawable.widget_bg_paper, 0xFF0F172A.toInt(),
        0xFF627188.toInt(), 0xFFE2E8F0.toInt(),
        0xFF1A7948.toInt(), 0xFFA5521D.toInt(), 0xFFB9393E.toInt(), 0xFF606B80.toInt(),
    )
    private val DARK = Pal(
        R.drawable.widget_bg_char, 0xFFF1F5F9.toInt(),
        0xFF7F8DA0.toInt(), 0xFF232D3B.toInt(),
        0xFF22C55E.toInt(), 0xFFF87F2A.toInt(), 0xFFEF7373.toInt(), 0xFF97A6BA.toInt(),
    )

    // Raw pigment — `C` in lib/ui2/theme.dart. Arcs and fills only.
    const val GREEN = 0xFF22C55E.toInt()
    const val ORANGE = 0xFFF97316.toInt()
    const val RED = 0xFFEF4444.toInt()
    const val BLUE = 0xFF3B82F6.toInt()      // sleep
    const val PURPLE = 0xFF8B5CF6.toInt()    // strain / movement
    const val N400 = 0xFF94A3B8.toInt()

    /**
     * How old the snapshot may be before the widget stops presenting it as
     * today's answer. `has_data` is a bool frozen when Dart pushed it, so on a
     * phone that stops syncing it stays true forever and a week-old readiness
     * sits on the home screen looking like this morning's; the age of
     * `updated_at` is what actually answers the question, and RemoteViews are
     * rebuilt on every broadcast so this is genuinely a render-time check.
     *
     * 26 h = one whole missed wake cycle plus grace. Same value and reasoning as
     * `kStaleAfter` in ios/OpenStrapWidget/OpenStrapWidget.swift.
     */
    private const val STALE_AFTER_SEC = 26L * 3600

    /** Is the published snapshot still today's answer? */
    fun fresh(prefs: SharedPreferences): Boolean {
        if (!prefs.getBoolean("has_data", false)) return false
        val at = readLong(prefs, "updated_at", 0)
        // An unknown timestamp is not a claim of staleness (matching
        // WidgetService.isStale); a snapshot never pushed has has_data false.
        if (at <= 0L) return true
        return System.currentTimeMillis() / 1000 - at <= STALE_AFTER_SEC
    }

    /**
     * Readiness tier -> arc pigment. The THRESHOLDS are not here: Dart publishes
     * `readiness_tier` (see `readinessBand` in lib/ui2/screens/home_screen.dart)
     * so the phone, the widget, the watch and Siri cannot disagree about what a
     * score of 65 means. Never re-derive a band from the raw number.
     */
    fun readinessArc(tier: Int): Int = when (tier) {
        3, 2 -> GREEN
        1 -> ORANGE
        0 -> RED
        else -> N400
    }

    /** The same tier, solved for TEXT. */
    fun readinessColor(tier: Int, pal: Pal): Int = when (tier) {
        3, 2 -> pal.onGood
        1 -> pal.onWarn
        0 -> pal.onBad
        else -> pal.onNone
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

    /** Epoch seconds. Read as Long: coerced through Int these overflow negative
     *  in 2038, and a negative timestamp reads as infinitely stale. */
    fun readLong(prefs: SharedPreferences, key: String, def: Long): Long =
        when (val v = prefs.all[key]) {
            is Long -> v
            is Int -> v.toLong()
            is Float -> v.toLong()
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

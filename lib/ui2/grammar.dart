// THE UX GRAMMAR
//
// Every card has a job. Cards are not decoration, and a screen that reaches
// for a card without being able to name which of the seven it is has not
// finished thinking.
//
//   A · Signal      one number, glanceable, lives in grids
//   B · Progress    something moving toward a goal
//   C · Trend       something changing over time
//   D · Insight     something the system noticed
//   E · Action      something the user should do
//   F · Status      something absent or uncertain
//   G · Deep dive   a gateway into serious data
//
// Plus the non-card primitives (rows, inline metrics, sections) and the
// widgets that encode the behavioural rules — Recommendation, GoalTrajectory,
// Observation, Consistency.
//
// Three rules the components enforce so screens cannot break them:
//
//   • ABSENCE IS A STATUS, NOT A DASH. There is no "empty" variant of Signal
//     or Trend. A metric with no value renders `StatusCard(what, why, fix:)`.
//     The audit found 102 bare `—` with no reason attached; the fix is that
//     the component that would draw one does not exist.
//   • CONFIDENCE IS `ConfDots`. Three dots, never a percentage, never a
//     banner. `Conf.of(metric)` is the one mapping from the analytics tier, so
//     screens don't each invent their own.
//   • EVERY TAP TARGET IS ≥ 44 pt. Not by convention — `Pressable` is the only
//     gesture primitive in lib/ui2 (the tokens test enforces that), and it
//     applies the minimum itself. No call site can opt out.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/metric.dart';
import 'charts.dart';
import 'theme.dart';

/// ── CONFIDENCE ────────────────────────────────────────────────────────────
///
/// Three states, matching what the analytics package actually emits. `AUTH`
/// exists but is reserved for user-stated facts (a manual sleep override), and
/// a user-stated fact is high confidence — it does not need a fourth dot.
enum Conf { high, estimated, none }

extension ConfX on Conf {
  int get dots => const [3, 2, 0][index];
  String get label =>
      const ['High confidence', 'Estimated', 'Not measured'][index];
  Color get tint => const [C.green, C.yellow, C.n400][index];

  /// The single mapping from the analytics tier. `RELATIVE` is `estimated`:
  /// the number is real and the trend is meaningful, but the absolute value
  /// is not — which is exactly what two dots mean.
  static Conf of(Metric? m) {
    if (m == null || m.isEmpty) return Conf.none;
    switch (m.tier) {
      case MetricTier.authoritative:
      case MetricTier.high:
        return Conf.high;
      case MetricTier.estimate:
      case MetricTier.relative:
        return Conf.estimated;
      case MetricTier.unknown:
        return m.confidence >= .8 ? Conf.high : Conf.estimated;
    }
  }
}

/// Confidence as a texture. Three dots, filled to the confidence level.
class ConfDots extends StatelessWidget {
  final Conf c;
  final double size;
  const ConfDots(this.c, {super.key, this.size = 5});

  @override
  Widget build(BuildContext ctx) {
    final p = P.of(ctx);
    return Semantics(
      label: c.label,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < c.dots ? p.on(c.tint) : const Color(0x00000000),
              border:
                  i < c.dots ? null : Border.all(color: p.line, width: 1.2),
            ),
          ),
      ]),
    );
  }
}

/// ── PRESSABLE ── the only gesture primitive in lib/ui2 ────────────────────
///
/// Guarantees a 44 pt minimum hit area regardless of how small the visual is,
/// and gates its own press feedback through [motion]. Everything tappable in
/// this library — cards, links, tabs, buttons — is built on it.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// Screen-reader label. Required for anything whose child is not plain text
  /// (an icon-only control), optional otherwise.
  final String? semanticLabel;

  /// Set false for a control that is genuinely inline in a text run, where a
  /// 44 pt box would blow the line height apart. The hit area is still
  /// expanded — via the parent's slop — but the layout box is not.
  final bool expand;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.expand = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext c) {
    Widget out = widget.child;
    if (widget.expand) {
      out = ConstrainedBox(
        constraints: const BoxConstraints(minWidth: S.tap, minHeight: S.tap),
        // widthFactor/heightFactor pin the Align to its child's size. Without
        // them Align fills every pixel it is offered, which turned each card
        // into a greedy box that ate the whole scroll view — caught by the
        // first golden, and invisible in any layout with a bounded parent.
        child: Align(
            alignment: Alignment.center,
            widthFactor: 1,
            heightFactor: 1,
            child: out),
      );
    }
    if (widget.onTap == null) {
      return widget.semanticLabel == null
          ? out
          : Semantics(label: widget.semanticLabel, child: out);
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? .975 : 1,
          duration: motion(c, Motion.fast),
          child: out,
        ),
      ),
    );
  }
}

/// The base card surface. Elevation, not outline.
class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsets pad;
  final VoidCallback? onTap;
  final Color? color;
  final int elevation;
  final String? semanticLabel;

  const Surface({
    super.key,
    required this.child,
    this.pad = const EdgeInsets.all(S.x4),
    this.onTap,
    this.color,
    this.elevation = 1,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: Container(
        width: double.infinity,
        padding: pad,
        decoration: BoxDecoration(
          color: color ?? p.card,
          borderRadius: R.rLg,
          boxShadow: p.el(elevation),
        ),
        child: child,
      ),
    );
  }
}

/// Full-width section. Whitespace separates concepts, not borders.
class Section extends StatelessWidget {
  final String title;
  final String? action;
  final Widget child;
  final VoidCallback? onAction;

  const Section(this.title, this.child,
      {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(S.x1, S.x5, S.x1, S.x2),
        child: Row(children: [
          Expanded(child: Text(title, style: F.head.copyWith(color: p.ink))),
          if (action != null)
            Flexible(
                child: Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x2),
                child: Text(
                  action!,
                  style: F.cap.copyWith(
                      color: p.on(C.blue), fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )),
        ]),
      ),
      child,
    ]);
  }
}

// ══════════════════ A · SIGNAL ══════════════════
/// One number. Glanceable. Lives in grids.
class SignalCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value, unit, sub;
  final Conf conf;
  final VoidCallback? onTap;

  const SignalCard(this.icon, this.color, this.label, this.value,
      {super.key,
      this.unit = '',
      this.sub = '',
      this.conf = Conf.high,
      this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: '$label, $value $unit'.trim(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: p.on(color)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(label,
                style: F.cap.copyWith(color: p.ink2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: S.x3),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(value,
                    style: F.n24.copyWith(color: p.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: S.x1),
                Text(unit, style: F.cap.copyWith(color: p.ink3)),
              ],
            ]),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: S.x1),
          Text(sub,
              style: F.over.copyWith(color: p.ink3),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}

// ══════════════════ B · PROGRESS ══════════════════
/// Something moving toward a goal. Current → target.
class ProgressCard extends StatelessWidget {
  final String label, value, target;
  final double frac;
  final Color color;
  final IconData? icon;

  const ProgressCard(
      this.label, this.value, this.target, this.frac, this.color,
      {super.key, this.icon});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: p.on(color)),
          const SizedBox(width: S.x2),
        ],
        Expanded(child: Text(label, style: F.cap.copyWith(color: p.ink2))),
        Text(value,
            style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        const SizedBox(width: S.x2),
        Text(target, style: F.cap.copyWith(color: p.ink3)),
      ]),
      const SizedBox(height: S.x2),
      _Bar(frac: frac, color: color),
    ]);
  }
}

/// The one progress bar. Everything with a fraction uses it.
class _Bar extends StatelessWidget {
  final double frac;
  final Color color;
  const _Bar({required this.frac, required this.color});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return ClipRRect(
      borderRadius: R.rPill,
      child: LinearProgressIndicator(
        value: frac.clamp(0, 1),
        minHeight: 8,
        backgroundColor: p.track,
        valueColor: AlwaysStoppedAnimation(p.on(color)),
      ),
    );
  }
}

// ══════════════════ C · TREND ══════════════════
/// Something changing. Value → context → direction → confidence.
class TrendCard extends StatelessWidget {
  final String label, value, unit, delta, window;
  final bool up, good;
  final List<double> series;
  final Color color;
  final Conf conf;
  final VoidCallback? onTap;

  const TrendCard(this.label, this.value, this.unit, this.delta, this.window,
      this.series, this.color,
      {super.key,
      this.up = false,
      this.good = true,
      this.conf = Conf.high,
      this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final dir = p.on(good ? C.green : C.orange);
    return Surface(
      onTap: onTap,
      semanticLabel: '$label, $value $unit, $delta $window'.trim(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: F.cap.copyWith(color: p.ink2))),
          ConfDots(conf),
        ]),
        const SizedBox(height: S.x2),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: F.n34.copyWith(color: p.ink)),
              const SizedBox(width: S.x1),
              Expanded(child: Text(unit, style: F.cap.copyWith(color: p.ink3))),
              Icon(up ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight,
                  size: 14, color: dir),
              const SizedBox(width: S.x1),
              Text(delta,
                  style: F.cap.copyWith(color: dir, fontWeight: FontWeight.w600)),
            ]),
        const SizedBox(height: S.x1),
        Text(window, style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x4),
        SizedBox(
          height: 64,
          child: CustomPaint(
            size: Size.infinite,
            painter: LineChart(series, p.on(color), dotInk: p.card),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════ D · INSIGHT ══════════════════
/// Something the system noticed. Recommendation → reason → action.
class InsightCard extends StatelessWidget {
  final String headline, reason, action;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const InsightCard(this.headline, this.reason,
      {super.key,
      this.action = '',
      this.icon = LucideIcons.sparkles,
      this.color = C.blue,
      this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = p.on(color);
    return Surface(
      onTap: onTap,
      color: p.wash(color, strength: .65),
      elevation: 0,
      semanticLabel: '$headline. $reason',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: p.wash(color), borderRadius: R.rSm),
            child: Icon(icon, size: 16, color: ink),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(headline,
                  style:
                      F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: S.x1),
              Text(reason, style: F.cap.copyWith(color: p.ink2, height: 1.5)),
            ]),
          ),
        ]),
        if (action.isNotEmpty) ...[
          const SizedBox(height: S.x2),
          Padding(
            padding: const EdgeInsets.only(left: S.x10 + S.x1),
            child: _Cta(action, ink),
          ),
        ],
      ]),
    );
  }
}

/// The "do the thing →" affordance. Always a label plus an arrow, never an
/// arrow alone.
class _Cta extends StatelessWidget {
  final String label;
  final Color color;
  const _Cta(this.label, this.color);

  @override
  Widget build(BuildContext c) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(label,
              style: F.cap.copyWith(color: color, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: S.x1),
        Icon(LucideIcons.arrowRight, size: 13, color: color),
      ]);
}

// ══════════════════ E · ACTION ══════════════════
/// Something the user should do.
class ActionCard extends StatelessWidget {
  final String title, meta, cta;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const ActionCard(this.title, this.meta, this.cta, this.icon, this.color,
      {super.key, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: '$title. $meta. $cta',
      child: Row(children: [
        Container(
          width: S.tap,
          height: S.tap,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.wash(color), borderRadius: R.rMd),
          child: Icon(icon, size: 20, color: p.on(color)),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style:
                    F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            Text(meta, style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x3),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
          decoration:
              BoxDecoration(color: p.fill(color), borderRadius: R.rSm),
          child: Text(cta,
              style: F.cap
                  .copyWith(color: p.inkOnFill, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ══════════════════ F · STATUS ══════════════════
/// Something unavailable or uncertain. WHAT is missing → WHY → WHAT FIXES IT.
///
/// This is the only correct rendering of an absent metric anywhere in the app.
/// Never an error, never a bare dash, never a zero.
class StatusCard extends StatelessWidget {
  final String what, why, fix;
  final IconData icon;
  final VoidCallback? onFix;

  const StatusCard(this.what, this.why,
      {super.key,
      this.fix = '',
      this.icon = LucideIcons.circleHelp,
      this.onFix});

  /// Build straight from a baseline-gated abstention — turns the analytics
  /// `need_baseline:have=H,need=N` note into the honest three-part copy
  /// instead of a dash. Returns null when [m] actually has a value.
  static StatusCard? forMetric(String what, Metric? m,
      {String unit = 'nights', String why = '', VoidCallback? onFix}) {
    if (m != null && !m.isEmpty) return null;
    final need = needMessageFromNote(m?.note, unit: unit);
    return StatusCard(
      what,
      why.isNotEmpty
          ? why
          : (need != null
              ? 'Not enough history yet to know what normal looks like for you.'
              : 'No measurement covering this period.'),
      fix: need ?? '',
      onFix: onFix,
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      elevation: 0,
      color: p.card2,
      onTap: onFix,
      semanticLabel: '$what. $why. $fix'.trim(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: p.ink3),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(what,
                style:
                    F.body.copyWith(color: p.ink2, fontWeight: FontWeight.w600)),
          ),
          const ConfDots(Conf.none),
        ]),
        const SizedBox(height: S.x2),
        Text(why, style: F.cap.copyWith(color: p.ink3, height: 1.5)),
        if (fix.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          _Cta(fix, p.on(C.blue)),
        ],
      ]),
    );
  }
}

// ══════════════════ G · DEEP DIVE ══════════════════
/// A gateway into serious data.
class DeepDiveCard extends StatelessWidget {
  final String label, value, unit, cta;
  final Widget? preview;
  final Color color;
  final VoidCallback? onTap;

  const DeepDiveCard(this.label, this.value, this.unit, this.cta, this.color,
      {super.key, this.preview, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: '$label, $value $unit. $cta',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(label, style: F.cap.copyWith(color: p.ink2))),
              Text(value, style: F.n24.copyWith(color: p.ink)),
              const SizedBox(width: S.x1),
              Text(unit, style: F.cap.copyWith(color: p.ink3)),
            ]),
        if (preview != null) ...[
          const SizedBox(height: S.x3),
          preview!,
        ],
        const SizedBox(height: S.x3),
        _Cta(cta, p.on(color)),
      ]),
    );
  }
}

// ══════════════════ ROWS — for lists, not cards ══════════════════
/// A metric in a list: name → value → trend → confidence.
class MetricRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name, sub, value, unit;
  final List<double> spark;
  final Conf conf;
  final String? status;
  final VoidCallback? onTap;

  const MetricRow(this.icon, this.color, this.name, this.value,
      {super.key,
      this.sub = '',
      this.unit = '',
      this.spark = const [],
      this.conf = Conf.high,
      this.status,
      this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$name, $value $unit. ${conf.label}'.trim(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(children: [
          Icon(icon, size: 18, color: p.on(color)),
          const SizedBox(width: S.x3),
          Expanded(
            flex: 3,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  style: F.body.copyWith(color: p.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (sub.isNotEmpty)
                Text(sub, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
          Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(value,
                    style: F.body
                        .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(unit, style: F.over.copyWith(color: p.ink3)),
                ],
              ]),
          const SizedBox(width: S.x3),
          SizedBox(
            width: 52,
            height: 22,
            child: status != null
                ? Align(
                    alignment: Alignment.centerRight,
                    child: Text(status!,
                        style: F.over.copyWith(color: p.on(C.green))))
                : (spark.isEmpty
                    ? const ConfDots(Conf.none)
                    : CustomPaint(
                        painter: LineChart(spark, p.on(color), fill: false))),
          ),
        ]),
      ),
    );
  }
}

/// Related numbers that belong on one line, not in four cards.
class InlineMetrics extends StatelessWidget {
  final List<(String, String, Color)> items;
  const InlineMetrics(this.items, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(
      children: [
        for (final e in items)
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.$1, style: F.over.copyWith(color: p.ink3)),
              const SizedBox(height: S.x1),
              Text(e.$2,
                  style: F.n17.copyWith(color: p.on(e.$3)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
      ],
    );
  }
}

// ══════════════════ BEHAVIOURAL RULES ══════════════════

/// Recommendation → reason → action. Never a recommendation on its own; an
/// instruction the user cannot audit is an instruction they stop trusting.
class Recommendation extends StatelessWidget {
  final String rec, reason, action;
  final Color color;
  final VoidCallback? onTap;

  const Recommendation(this.rec, this.reason, this.action,
      {super.key, this.color = C.green, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$rec. $reason. $action',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rec, style: F.t2.copyWith(color: p.ink)),
        const SizedBox(height: S.x2),
        Text(reason, style: F.body.copyWith(color: p.ink2, height: 1.5)),
        const SizedBox(height: S.x3),
        Row(children: [
          Flexible(
            child: Text(action,
                style: F.body
                    .copyWith(color: p.on(color), fontWeight: FontWeight.w600),
                maxLines: 2),
          ),
          const SizedBox(width: S.x1),
          Icon(LucideIcons.arrowRight, size: 15, color: p.on(color)),
        ]),
      ]),
    );
  }
}

/// Current → target → the rate that connects them.
class GoalTrajectory extends StatelessWidget {
  final String label, current, target, rate;
  final double frac;
  final Color color;

  /// Which way the rate points. Purely presentational — the caller knows
  /// whether its own metric going down is good news.
  final bool rateDown;

  const GoalTrajectory(
      this.label, this.current, this.target, this.rate, this.frac, this.color,
      {super.key, this.rateDown = true});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = p.on(color);
    return Surface(
      semanticLabel: '$label, $current toward $target. $rate',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(height: S.x3),
        // Wrap, not Row: at large text scales the goal label drops to its own
        // line rather than pushing the number off the card. A truncated
        // measurement is worse than a taller card.
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: S.x3,
          runSpacing: S.x1,
          children: [
            Text(current, style: F.n34.copyWith(color: p.ink)),
            Text('Goal $target', style: F.cap.copyWith(color: p.ink3)),
          ],
        ),
        const SizedBox(height: S.x3),
        _Bar(frac: frac, color: color),
        const SizedBox(height: S.x2),
        Row(children: [
          Icon(rateDown ? LucideIcons.trendingDown : LucideIcons.trendingUp,
              size: 14, color: ink),
          const SizedBox(width: S.x1),
          Flexible(child: Text(rate, style: F.cap.copyWith(color: ink))),
        ]),
      ]),
    );
  }
}

/// A health observation that may deserve a clinician. Not gamification, not a
/// diagnosis — a statement of what was measured and what it might be worth.
class Observation extends StatelessWidget {
  final String headline, detail, advice;
  final VoidCallback? onTap;

  const Observation(this.headline, this.detail, this.advice,
      {super.key, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = p.on(C.orange);
    return Pressable(
      onTap: onTap,
      semanticLabel: 'Health observation. $headline. $detail. $advice',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: R.rLg,
          border: Border(left: BorderSide(color: ink, width: 3)),
          boxShadow: p.el(1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(LucideIcons.stethoscope, size: 15, color: ink),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text('HEALTH OBSERVATION',
                  style: F.over.copyWith(color: ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: S.x3),
          Text(headline,
              style: F.body.copyWith(
                  color: p.ink, fontWeight: FontWeight.w600, height: 1.45)),
          const SizedBox(height: S.x2),
          Text(detail, style: F.cap.copyWith(color: p.ink2, height: 1.5)),
          const SizedBox(height: S.x2),
          Text(advice, style: F.cap.copyWith(color: p.ink3, height: 1.5)),
          if (onTap != null) ...[
            const SizedBox(height: S.x3),
            _Cta('View data', ink),
          ],
        ]),
      ),
    );
  }
}

/// Consistency, never a streak. "18 of 24 days" cannot reset to zero, so a
/// missed day costs a day rather than costing everything.
class Consistency extends StatelessWidget {
  final int have, of;
  final String label;
  final Color color;

  const Consistency(this.have, this.of, this.label, this.color, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = of <= 0 ? 0 : of;
    return Semantics(
      label: '$have of $n days. $label',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: S.x1,
          children: [
            Text('$have', style: F.n24.copyWith(color: p.ink)),
            Text('of $n days', style: F.cap.copyWith(color: p.ink3)),
          ],
        ),
        const SizedBox(height: S.x2),
        Row(children: [
          for (var i = 0; i < n; i++)
            Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == n - 1 ? 0 : 2),
                height: 6,
                decoration: BoxDecoration(
                  color: i < have ? p.on(color) : p.track,
                  borderRadius: const BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: S.x2),
        Text(label, style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
  }
}

// ══════════════════ CHROME ══════════════════

/// Contextual sub-navigation inside a domain. Never a bottom tab — the bottom
/// bar has five destinations and will not grow a sixth.
class SubTabs extends StatelessWidget {
  final List<String> items;
  final int index;
  final ValueChanged<int> onTap;
  final Color color;

  const SubTabs(this.items, this.index, this.onTap,
      {super.key, this.color = C.green});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      height: MediaQuery.textScalerOf(c).scale(S.tap),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: S.x2),
        itemBuilder: (_, i) {
          final on = i == index;
          return Pressable(
            onTap: () => onTap(i),
            expand: false,
            child: AnimatedContainer(
              duration: motion(c, Motion.base),
              constraints: const BoxConstraints(minWidth: S.tap),
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? p.wash(color) : const Color(0x00000000),
                borderRadius: R.rPill,
              ),
              child: Text(
                items[i],
                style: F.cap.copyWith(
                  color: on ? p.on(color) : p.ink3,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ScreenTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const ScreenTitle(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x1, S.x2, S.x1, S.x3),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: F.t1.copyWith(color: p.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        ?trailing,
      ]),
    );
  }
}

/// A small labelled chip. Status, tag, category.
class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const Pill(this.text, this.color, {super.key, this.icon});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = p.on(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: 5),
      decoration: BoxDecoration(color: p.wash(color), borderRadius: R.rPill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: ink),
          const SizedBox(width: S.x1),
        ],
        Flexible(
          child: Text(text,
              style: F.cap.copyWith(color: ink, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

/// The primary commitment button. [soft] is the secondary form.
class BigButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool soft;
  final VoidCallback? onTap;

  const BigButton(this.label,
      {super.key,
      this.icon,
      this.color = C.green,
      this.soft = false,
      this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = soft ? p.on(color) : p.inkOnFill;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        // A minimum, never a fixed height — at accessibility text sizes the
        // label is taller than 52 and a fixed box would clip it.
        constraints: const BoxConstraints(minHeight: 52),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
            horizontal: S.x4, vertical: S.x3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: soft ? p.wash(color) : p.fill(color),
          borderRadius: R.rMd,
          boxShadow: soft ? null : p.el(2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: S.x2),
          ],
          Flexible(
            child: Text(label,
                style: F.head.copyWith(color: ink),
                textAlign: TextAlign.center,
                maxLines: 2),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════ CHART FRAME ══════════════════
/// Everything a chart needs in order to be read: what it is, what it is
/// measured in, what the heights mean, what the colours mean, and what the
/// horizontal axis covers.
///
/// A painter draws a shape. The shape is only information once something says
/// `bpm` next to it and puts a `56` beside a gridline, and until this existed
/// lib/ui2 drew forty charts and printed neither. The rules it enforces:
///
///   • THE UNIT IS ALWAYS IN THE HEADER. Not in a caption under the card, not
///     implied by the metric name. [unit] is required, and there is no variant
///     without it.
///   • THE LABELS AND THE CURVE SHARE ONE [AxisSpec]. Pass the same instance to
///     [yAxis] and to the painter (`LineChart(d, colour, axis: spec)`). The
///     frame prints [AxisSpec.format] at each gridline and the painter maps
///     values through [AxisSpec.t], so they cannot disagree. A painter left to
///     auto-scale is a chart whose gridlines are decoration.
///   • ABSENCE IS NOT AN EMPTY AXIS. Pass [empty] — normally `const NoData()` —
///     when there is no series. The frame keeps the title and the unit and
///     drops the axis entirely, because an axis with nothing on it reads as a
///     measurement of zero.
///   • MORE THAN ONE COLOUR MEANS A [legend]. `Hypnogram.legend`,
///     `ZoneBar.legend`, `Spectrum.legend` and `IntervalLadder.legend` are
///     derived from the painters' own palettes — pass those rather than
///     retyping them, so a recolour can never orphan its key.
///
/// [xLabels] are laid out first-flush-left, last-flush-right and the rest
/// centred, on cells that line up with the data: with three labels they mark
/// the start, middle and end of what is actually drawn. They must describe the
/// range on screen — a fixed `['30 days ago', '15', 'Today']` under a
/// seven-day window is worse than no labels at all.
class ChartFrame extends StatelessWidget {
  final String title;

  /// `bpm`, `ms`, `min`, `°`. Always rendered.
  final String unit;

  /// The painter, normally a `CustomPaint(size: Size.infinite, painter: …)`.
  final Widget child;

  /// Plot height in logical pixels. Text scale does not stretch it; the tick
  /// labels thin themselves instead (see the note in `build`).
  final double height;

  final AxisSpec? yAxis;
  final List<String> xLabels;
  final List<(String, Color)> legend;
  final String? footnote;

  /// Confidence for the series, shown as [ConfDots] in the header. Null means
  /// the question doesn't apply (a count, a user-entered value).
  final Conf? conf;

  /// Non-null means THERE IS NO DATA: rendered in place of the plot, axis and
  /// x-labels. `const NoData()` is the house form.
  final Widget? empty;

  const ChartFrame({
    super.key,
    required this.title,
    required this.unit,
    required this.child,
    this.height = 120,
    this.yAxis,
    this.xLabels = const [],
    this.legend = const [],
    this.footnote,
    this.conf,
    this.empty,
  });

  /// Width and height of [s] as it will actually be laid out — including the
  /// user's text scale. Estimating this from a character count is how axis
  /// gutters end up clipping `7h 30m` at 2× on exactly the devices whose
  /// owners chose 2× because they need it.
  static Size _measure(String s, TextStyle st, TextScaler sc, TextDirection d) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: st),
      textDirection: d,
      textScaler: sc,
      maxLines: 1,
    )..layout();
    return tp.size;
  }

  Widget _header(P p, bool stacked) {
    final name = Text(title,
        style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis);
    final measure = Text(unit, style: F.over.copyWith(color: p.ink3));
    if (!stacked) {
      // Centred, not baseline-aligned: ConfDots has no baseline to align to.
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: name),
        const SizedBox(width: S.x2),
        measure,
        if (conf != null) ...[const SizedBox(width: S.x2), ConfDots(conf!)],
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: name),
        if (conf != null) ...[const SizedBox(width: S.x2), ConfDots(conf!)],
      ]),
      measure,
    ]);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final scaler = MediaQuery.textScalerOf(c);
    final dir = Directionality.of(c);
    // ink3 is the muted token that is *solved* to 4.5:1 on every surface — the
    // axis is the smallest type on the card, so it gets the floor, not a
    // lighter grey chosen by eye.
    final tick = F.over.copyWith(color: p.ink3);

    final a = empty == null ? yAxis : null;
    var labels = const <String>[];
    var gutter = 0.0, lineH = 0.0;
    if (a != null) {
      lineH = _measure('0', tick, scaler, dir).height;
      // At 2× text a 120 pt plot fits three labels; a 60 pt one fits two. Thin
      // the LABELS rather than the axis — min and max are unchanged, so the
      // curve keeps the exact scale the caller pinned and the remaining
      // gridlines still sit on real values.
      final fits = (height / (lineH * 1.35)).floor();
      final n = a.ticks.clamp(2, fits < 2 ? 2 : fits);
      labels = [
        for (final v in AxisSpec(
                min: a.min, max: a.max, ticks: n, format: a.format)
            .tickValues)
          a.format(v)
      ];
      for (final s in labels) {
        final w = _measure(s, tick, scaler, dir).width;
        if (w > gutter) gutter = w;
      }
    }
    final inset = a == null ? 0.0 : gutter + S.x2;

    return Semantics(
      container: true,
      label: [
        title,
        'measured in $unit',
        if (conf != null) conf!.label,
        ?footnote,
      ].join('. '),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── header: what it is, and what it is measured in ──
        // Title and unit share a line until the text scale makes that a
        // choice between truncating the title and dropping the unit — at
        // which point the unit moves under it. Neither is ever dropped.
        _header(p, scaler.scale(1) > 1.3),
        const SizedBox(height: S.x3),

        // ── plot, or the honest absence of one ──
        if (empty != null)
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Center(child: empty),
          )
        else
          SizedBox(
            height: height,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (a != null) ...[
                SizedBox(
                  width: gutter,
                  child: Stack(children: [
                    for (var i = 0; i < labels.length; i++)
                      Positioned(
                        left: 0,
                        right: 0,
                        // Centred on its gridline, then clamped inside the
                        // plot so the top and bottom labels are not half cut.
                        top: (i / (labels.length - 1) * height - lineH / 2)
                            .clamp(0.0, (height - lineH).clamp(0.0, height)),
                        child: Text(labels[i],
                            style: tick,
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            softWrap: false),
                      ),
                  ]),
                ),
                const SizedBox(width: S.x2),
              ],
              Expanded(
                child: Stack(children: [
                  if (a != null)
                    Positioned.fill(
                        child: CustomPaint(
                            painter: _Gridlines(labels.length, p.line))),
                  Positioned.fill(child: child),
                ]),
              ),
            ]),
          ),

        // ── x axis ──
        if (empty == null && xLabels.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: S.x1, left: inset),
            child: Row(children: [
              for (var i = 0; i < xLabels.length; i++)
                Expanded(
                  child: Text(
                    xLabels[i],
                    style: tick,
                    textAlign: i == 0
                        ? TextAlign.start
                        : i == xLabels.length - 1
                            ? TextAlign.end
                            : TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ]),
          ),

        // ── legend ──
        if (legend.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: S.x3),
            child: Wrap(spacing: S.x3, runSpacing: S.x1, children: [
              for (final (label, colour) in legend)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colour,
                      // The swatch is the mark's real colour so the two match,
                      // and a pale mark still needs an edge to be findable.
                      border: Border.all(color: p.line, width: .5),
                    ),
                  ),
                  const SizedBox(width: S.x1),
                  Text(label, style: tick),
                ]),
            ]),
          ),

        if (footnote != null)
          Padding(
            padding: const EdgeInsets.only(top: S.x2),
            child: Text(footnote!, style: F.cap.copyWith(color: p.ink3)),
          ),
      ]),
    );
  }
}

/// The horizontal rules behind a plot, at the same fractions [ChartFrame]
/// prints its labels — one count, passed to both, so they cannot drift.
class _Gridlines extends CustomPainter {
  final int n;
  final Color color;
  const _Gridlines(this.n, this.color);

  @override
  void paint(Canvas cv, Size s) {
    if (n < 2 || s.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var i = 0; i < n; i++) {
      // Inset half a stroke so the first and last rules are drawn, not clipped.
      final y = (i / (n - 1) * s.height).clamp(.5, s.height - .5);
      cv.drawLine(Offset(0, y), Offset(s.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _Gridlines o) => o.n != n || o.color != color;
}

/// The body of an empty [ChartFrame]. Says what is missing in words.
///
/// This is not a replacement for [StatusCard] — a metric that has no value
/// still renders one, with its why and its fix. This is the smaller case: the
/// number exists, the SERIES behind the picture does not.
class NoData extends StatelessWidget {
  final String message;
  const NoData({super.key, this.message = 'No data yet'});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(LucideIcons.chartLine, size: 15, color: p.ink3),
      const SizedBox(width: S.x2),
      Flexible(
        child: Text(message,
            style: F.cap.copyWith(color: p.ink3), textAlign: TextAlign.center),
      ),
    ]);
  }
}

/// The pushed-screen header. Back → title → one optional action.
class NavBar extends StatelessWidget {
  final String title;
  final String sub;
  final Widget? trailing;
  final VoidCallback? onBack;

  const NavBar(this.title, {super.key, this.sub = '', this.trailing, this.onBack});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(children: [
        Pressable(
          onTap: onBack ?? () => Navigator.maybePop(c),
          semanticLabel: 'Back',
          child: Icon(LucideIcons.chevronLeft, size: 24, color: p.ink),
        ),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(title,
                style: F.head.copyWith(color: p.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (sub.isNotEmpty)
              Text(sub,
                  style: F.over.copyWith(color: p.ink3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ]),
        ),
        SizedBox(
          width: S.tap,
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ]),
    );
  }
}

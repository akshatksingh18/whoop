// CYCLE — the domain that was fully built in the data layer and dark in the UI.
//
// Three rules shape every line of it:
//
//   1. Everything on this screen is COUNTED from days you logged. The phase,
//      the prediction and the fertile window are arithmetic over your own
//      dates — no threshold, no population norm, no diagnosis. The one thing
//      the repo derives from a sensor (`ovulation_est`, a temperature
//      coverline) is deliberately NOT rendered: it compares an ADC-count
//      threshold against a z-score series, a live unit mismatch.
//   2. A prediction states its evidence and never hardens into a promise. It
//      is "expected around", with the number of cycles it was counted from on
//      the same row, and it disappears entirely below two logged starts
//      because a mean of one gap is not a mean.
//   3. The biometric overlay is descriptive and comparative to YOU. Resting
//      heart rate across the current cycle, drawn from `day_result`, with no
//      claim about what it means.
//
// Tracking is off until the user turns it on, and the switch lives here rather
// than in a settings screen — the toggle and the thing it toggles are one tap
// apart.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import '../onboarding/profile_setup.dart' show formatDay;

/// What the user may attach to a day. A short, plain, non-diagnostic list —
/// these are observations, not symptoms of anything the app claims to know.
const kCycleSymptoms = <String>[
  'cramps',
  'headache',
  'bloating',
  'fatigue',
  'low mood',
  'acne',
  'tender breasts',
  'nausea',
];

class CycleData {
  final bool enabled;
  final String phase;
  final int? cycleDay;
  final num? daysUntilNext, meanLength;
  final String? predictedNext, fertileStart, fertileEnd;

  /// `{date, kind}`, oldest first.
  final List<Map<String, dynamic>> logs;

  /// `{date, cycle_day, resting_hr, hrv_rmssd, skin_temp_idx}` — 120 days of
  /// derived days, so most rows fall outside the current cycle.
  final List<Map<String, dynamic>> overlay;

  final Map<String, List<String>> symptoms;

  const CycleData({
    this.enabled = false,
    this.phase = 'unknown',
    this.cycleDay,
    this.daysUntilNext,
    this.meanLength,
    this.predictedNext,
    this.fertileStart,
    this.fertileEnd,
    this.logs = const [],
    this.overlay = const [],
    this.symptoms = const {},
  });

  /// Logged period starts. Two of them is one measured gap, which is the floor
  /// for a mean length and therefore for every prediction on the screen.
  int get starts => logs.where((l) => l['kind'] == 'start').length;

  static Future<CycleData> load(AppState app) async {
    final repo = app.repo;
    if (repo == null) return const CycleData();
    final c = await repo.getCycle();
    if (c['enabled'] != true) return const CycleData();
    return CycleData(
      enabled: true,
      phase: (c['phase'] ?? 'unknown').toString(),
      cycleDay: (c['cycle_day'] as num?)?.round(),
      daysUntilNext: c['days_until_next'] as num?,
      meanLength: c['mean_length'] as num?,
      predictedNext: c['predicted_next'] as String?,
      fertileStart: c['fertile_start'] as String?,
      fertileEnd: c['fertile_end'] as String?,
      logs: [
        for (final l in (c['logs'] as List? ?? const []))
          if (l is Map) l.cast<String, dynamic>(),
      ],
      overlay: [
        for (final o in (c['overlay'] as List? ?? const []))
          if (o is Map) o.cast<String, dynamic>(),
      ],
      symptoms: await repo.getCycleSymptoms(),
    );
  }
}

/// The Wellness sub-tab. Renders a `Column`, so it drops straight into the
/// screen's own `ListView` the way the other four tabs do.
class CycleTab extends StatefulWidget {
  final CycleData? data;
  const CycleTab({super.key, this.data});

  @override
  State<CycleTab> createState() => _CycleTabState();
}

class _CycleTabState extends State<CycleTab> {
  CycleData? _d;
  final String _date = todayLabel();

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _d = widget.data;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final d = await CycleData.load(context.read<AppState>());
      if (mounted) setState(() => _d = d);
    } catch (_) {
      if (mounted) setState(() => _d = const CycleData());
    }
  }

  Future<void> _setEnabled(bool on) async {
    await context.read<AppState>().updateProfile({'track_cycle': on});
    await _load();
  }

  Future<void> _logStart() async {
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    await repo.postCycleLog(_date);
    await _load();
  }

  Future<void> _deleteLog(String date) async {
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    await repo.deleteCycleLog(date);
    await _load();
  }

  Future<void> _toggleSymptom(String s) async {
    final repo = context.read<AppState>().repo;
    final d = _d;
    if (repo == null || d == null) return;
    final now = [...?d.symptoms[_date]];
    now.contains(s) ? now.remove(s) : now.add(s);
    await repo.postCycleSymptoms(_date, now);
    await _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d;
    if (d == null) return const Center(child: CircularProgressIndicator());

    if (!d.enabled) {
      return StatusCard(
        'Cycle tracking is off',
        'Nothing is recorded or predicted until you turn it on. It stays on '
            'this phone.',
        fix: 'Turn on cycle tracking',
        icon: LucideIcons.circleDot,
        onFix: () => _setEnabled(true),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.cycleDay == null)
          StatusCard(
            'No period logged yet',
            'Counted from the days you log. Nothing is inferred from your body.',
            fix: 'Log a period start today',
            icon: LucideIcons.calendarPlus,
            onFix: _logStart,
          )
        else
          _today(c, p, d),

        if (d.predictedNext != null) ...[
          const SizedBox(height: S.x4),
          _prediction(c, p, d),
        ],

        Section('Resting heart rate this cycle', _overlay(c, d)),

        Section('What you noticed today', _symptoms(c, p, d)),

        Section('Logged days', _logs(c, p, d)),

        const SizedBox(height: S.x5),
        BigButton('Log a period start today',
            icon: LucideIcons.calendarPlus, color: C.pink, onTap: _logStart),
        const SizedBox(height: S.x3),
        Pressable(
          onTap: () => _setEnabled(false),
          child: Text('Turn off cycle tracking',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3)),
        ),
      ],
    );
  }

  // ── today ────────────────────────────────────────────────────────────────

  Widget _today(BuildContext c, P p, CycleData d) => Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('DAY IN THIS CYCLE', style: F.over.copyWith(color: p.ink3)),
            const Spacer(),
            if (d.phase != 'unknown') Pill(_phaseLabel(d.phase), C.pink),
          ]),
          const SizedBox(height: S.x2),
          Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('${d.cycleDay}', style: F.n34.copyWith(color: p.ink)),
                const SizedBox(width: S.x2),
                Text(
                    d.meanLength == null
                        ? 'counted from your last logged start'
                        : 'of about ${d.meanLength!.round()}',
                    style: F.cap.copyWith(color: p.ink3)),
              ]),
          if (d.fertileStart != null && d.fertileEnd != null) ...[
            const SizedBox(height: S.x4),
            InlineMetrics([
              (
                'FERTILE WINDOW, ESTIMATED',
                '${_short(d.fertileStart!)} – ${_short(d.fertileEnd!)}',
                C.purple,
              ),
            ]),
            const SizedBox(height: S.x2),
            Text(
              'Counted back from your mean cycle. Not contraception.',
              style: F.over.copyWith(color: p.ink3, height: 1.5),
            ),
          ],
        ]),
      );

  // ── prediction ───────────────────────────────────────────────────────────

  Widget _prediction(BuildContext c, P p, CycleData d) {
    final n = d.starts;
    final due = _parse(d.predictedNext!);
    final days = d.daysUntilNext?.round();
    return Surface(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NEXT PERIOD, EXPECTED AROUND',
                style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x1),
            Text(due == null ? d.predictedNext! : formatDay(due),
                style: F.n24.copyWith(color: p.ink)),
            const SizedBox(height: S.x1),
            Text(
                '${days == null ? '' : days < 0 ? '${-days} days late · ' : days == 0 ? 'today · ' : 'in $days days · '}'
                'from ${n - 1} measured gap${n == 2 ? '' : 's'} between '
                '$n logged starts',
                style: F.over.copyWith(color: p.ink3, height: 1.4)),
          ]),
        ),
      ]),
    );
  }

  // ── overlay ──────────────────────────────────────────────────────────────

  /// Resting HR against cycle day, for the CURRENT cycle only. `cycle_day` is
  /// counted from the last logged start, so anything outside 1…today is a row
  /// from a previous cycle wearing this cycle's numbering.
  Widget _overlay(BuildContext c, CycleData d) {
    final today = d.cycleDay;
    final byDay = <int, double>{};
    for (final o in d.overlay) {
      final cd = o['cycle_day'], v = o['resting_hr'];
      if (cd is! num || v is! num) continue;
      if (cd < 1 || (today != null && cd > today)) continue;
      byDay[cd.round()] = v.toDouble();
    }
    // Indexed by cycle day, not compacted: a night the band was off is a HOLE
    // in the line, and a compacted series would quietly join Day 4 to Day 9 as
    // if they were adjacent.
    final last = byDay.isEmpty
        ? 0
        : today ?? byDay.keys.reduce((a, b) => a > b ? a : b);
    final vals = <double?>[for (var i = 1; i <= last; i++) byDay[i]];
    final present = byDay.values.toList();
    final axis = present.length < 3 ? null : AxisSpec.of(present);
    final p = P.of(c);
    return Surface(
      child: ChartFrame(
        title: 'Resting heart rate',
        unit: 'bpm',
        height: 120,
        yAxis: axis,
        xLabels: axis == null ? const [] : ['Day 1', 'Day $last'],
        footnote: 'Your own nightly resting rate across this cycle. '
            'Descriptive only.',
        empty: axis == null
            ? const NoData(message: 'Not enough derived nights this cycle yet')
            : null,
        series: vals,
        child: axis == null
            ? const SizedBox.shrink()
            // No fill: a filled area under a heart-rate axis that starts at 52
            // is the truncated-axis form with the truncation hidden.
            : CustomPaint(
                size: Size.infinite,
                painter: LineChart(vals, p.on(C.pink),
                    fill: false, t: animate(c, 1), axis: axis),
              ),
      ),
    );
  }

  // ── symptoms ─────────────────────────────────────────────────────────────

  Widget _symptoms(BuildContext c, P p, CycleData d) {
    final on = d.symptoms[_date] ?? const <String>[];
    return Surface(
      child: Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          for (final s in kCycleSymptoms)
            Pressable(
              onTap: () => _toggleSymptom(s),
              child: AnimatedContainer(
                duration: motion(c, Motion.fast),
                padding:
                    const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
                decoration: BoxDecoration(
                  color: on.contains(s) ? p.wash(C.pink) : p.card2,
                  borderRadius: R.rPill,
                ),
                child: Text(s,
                    style: F.cap.copyWith(
                        color: on.contains(s) ? p.on(C.pink) : p.ink2,
                        fontWeight:
                            on.contains(s) ? FontWeight.w600 : FontWeight.w500)),
              ),
            ),
        ],
      ),
    );
  }

  // ── logs ─────────────────────────────────────────────────────────────────

  Widget _logs(BuildContext c, P p, CycleData d) {
    if (d.logs.isEmpty) {
      return const StatusCard(
        'Nothing logged yet',
        'A logged start is the only input.',
        icon: LucideIcons.calendarDays,
      );
    }
    final recent = d.logs.reversed.take(6).toList();
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < recent.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x2),
            child: Row(children: [
              Expanded(
                child: Text(
                    _parse(recent[i]['date'] as String? ?? '') == null
                        ? '${recent[i]['date']}'
                        : formatDay(_parse(recent[i]['date'] as String)!),
                    style: F.body.copyWith(color: p.ink)),
              ),
              Text('${recent[i]['kind']}'.toUpperCase(),
                  style: F.over.copyWith(color: p.ink3)),
              const SizedBox(width: S.x3),
              Pressable(
                semanticLabel: 'Remove ${recent[i]['date']}',
                onTap: () => _deleteLog(recent[i]['date'] as String),
                child: Icon(LucideIcons.x, size: 18, color: p.ink3),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

DateTime? _parse(String ymd) => DateTime.tryParse(ymd);

String _short(String ymd) {
  final d = _parse(ymd);
  return d == null ? ymd : formatDay(d);
}

String _phaseLabel(String p) => switch (p) {
      'menstrual' => 'Menstrual',
      'follicular' => 'Follicular',
      'ovulation' => 'Ovulation window',
      'luteal' => 'Luteal',
      _ => p,
    };

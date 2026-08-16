// CYCLE — the domain that was fully built in the data layer and dark in the UI.
//
// Three rules shape every line of it:
//
//   1. Everything on this screen is COUNTED from days you logged. The phase
//      and the prediction are arithmetic over your own dates — no threshold,
//      no population norm, no diagnosis. THERE IS NO FERTILE WINDOW: it was
//      `(median − 14) ± 2`, a textbook population constant printed as her own
//      dates, and WH-09 deleted it. The one thing the repo derives from a
//      sensor (`ovulation_est`, a temperature coverline) is deliberately NOT
//      rendered either: it compares an ADC-count threshold against a z-score
//      series, a live unit mismatch.
//   2. A prediction states its evidence and never hardens into a promise. It
//      is a RANGE — the median gap ± the MAD of her own gaps — with the number
//      of measured gaps behind it on the same row. It is often very wide, and
//      that width is the finding. It disappears entirely below two logged
//      starts, and below THREE it can only give the point and say why it has
//      no width.
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

/// WH-07 — what she may declare, and nothing beyond it. There is no "trying to
/// conceive" and no due date: this list exists to switch things OFF, and every
/// entry that would switch something on is a claim we cannot back.
const kReproStates = <(String, String, String)>[
  (
    'cycling',
    'I have natural cycles',
    'Counts a phase from your logged starts.',
  ),
  (
    'contraception',
    'Hormonal contraception',
    'No ovulation to count from, so no phase. Bleeds are still logged.',
  ),
  (
    'none',
    'Pregnant, postpartum, or not cycling',
    'No phase and no predicted next. Your biometrics still show.',
  ),
];

class CycleData {
  final bool enabled;
  final String phase;
  final int? cycleDay;
  final num? daysUntilNext, medianLength;
  final String? predictedNext;

  /// The band half her logged gaps fell inside — median gap ± MAD. Both null
  /// until two gaps exist, because one gap has no spread to state.
  final String? predictedFrom, predictedTo;

  /// Measured gaps behind the prediction. One fewer than logged starts.
  final int gapN;

  /// WH-07 — what she told the app, or null if she never did. Null is not
  /// "cycling": it is the conservative reading, and it keeps the phase off.
  final String? reproState;

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
    this.medianLength,
    this.predictedNext,
    this.predictedFrom,
    this.predictedTo,
    this.gapN = 0,
    this.reproState,
    this.logs = const [],
    this.overlay = const [],
    this.symptoms = const {},
  });

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
      medianLength: c['median_length'] as num?,
      predictedNext: c['predicted_next'] as String?,
      predictedFrom: c['predicted_from'] as String?,
      predictedTo: c['predicted_to'] as String?,
      gapN: (c['gap_n'] as num?)?.round() ?? 0,
      reproState: c['repro_state'] as String?,
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

  /// The symptom look-back is folded away by default — the chips above it are
  /// what she opened the tab to tap.
  bool _showShape = false;

  /// Read on every use. The tab lives in the shell's IndexedStack, so a field
  /// initialiser would still be yesterday after midnight and a period start
  /// would be logged against the wrong day.
  String get _date => todayLabel();

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

  /// Confirmed, because it cannot be undone OR redone: the only writer on this
  /// screen logs TODAY, so a start deleted off an older date has no way back.
  Future<void> _deleteLog(String date) async {
    final ok = await confirmRemove(
      context,
      title: 'Remove ${_short(date)}?',
      body:
          'Cycle day, phase and the predicted next date are all counted from '
          'the days you log. Only today can be logged, so this one cannot be '
          'put back.',
    );
    if (!ok || !mounted) return;
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    await repo.deleteCycleLog(date);
    await _load();
  }

  /// Pick, or clear back to unset. Clearing is a real answer — it returns the
  /// screen to the conservative reading rather than trapping her in a state she
  /// tapped once.
  Future<void> _pickRepro() async {
    final p = P.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      sheetAnimationStyle: sheetMotion(context),
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(borderRadius: R.rXl),
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(S.x4),
              child: Text(
                'What applies to you',
                style: F.head.copyWith(color: P.of(c).ink),
              ),
            ),
            for (final (key, label, why) in [
              ...kReproStates,
              ('', 'Prefer not to say', 'The app keeps the phase off.'),
            ])
              Pressable(
                onTap: () => Navigator.pop(c, key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: S.x4,
                    vertical: S.x3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: F.body.copyWith(color: P.of(c).ink)),
                      Text(
                        why,
                        style: F.over.copyWith(
                          color: P.of(c).ink3,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await context.read<AppState>().updateProfile({
      'repro_state': picked.isEmpty ? null : picked,
    });
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
        'It stays on this phone.',
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
            'Counted from the days you log.',
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

        if (d.logs.isNotEmpty) Section('Logged days', _logs(c, p, d)),

        // WH-07 — the one control that makes the screen say less. It sits in
        // this tab's settings gutter, next to the switch that turns the whole
        // thing off, because that is what it is: not a reading, a declaration.
        const SizedBox(height: S.x5),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: MetricRow(
            LucideIcons.circleDot,
            C.pink,
            'What applies to you',
            _reproLabel(d.reproState),
            sub: d.reproState == null
                ? 'Optional. Until you say, the app leaves the phase off.'
                : 'Only you and this phone. Never exported.',
            onTap: _pickRepro,
          ),
        ),
        const SizedBox(height: S.x5),
        BigButton(
          'Log a period start today',
          icon: LucideIcons.calendarPlus,
          color: C.pink,
          onTap: _logStart,
        ),
        const SizedBox(height: S.x3),
        Pressable(
          onTap: () => _setEnabled(false),
          child: Text(
            'Turn off cycle tracking',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3),
          ),
        ),
      ],
    );
  }

  // ── today ────────────────────────────────────────────────────────────────

  Widget _today(BuildContext c, P p, CycleData d) => Surface(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('DAY IN THIS CYCLE', style: F.over.copyWith(color: p.ink3)),
            const Spacer(),
            if (d.phase != 'unknown') Pill(_phaseLabel(d.phase), C.pink),
          ],
        ),
        const SizedBox(height: S.x2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${d.cycleDay}', style: F.n34.copyWith(color: p.ink)),
            const SizedBox(width: S.x2),
            Text(
              d.medianLength == null
                  ? 'counted from your last logged start'
                  : 'of about ${d.medianLength!.round()}',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
        ),
      ],
    ),
  );

  // ── prediction ───────────────────────────────────────────────────────────

  /// A RANGE, not a date — median gap ± the MAD of her own gaps.
  ///
  /// It is wide, often very wide, and that is the finding rather than a defect
  /// to tune away: a cycle that varies by six days cannot be predicted to one.
  /// Below two measured gaps there is no spread to state, so it falls back to
  /// the point and says why it has no width.
  Widget _prediction(BuildContext c, P p, CycleData d) {
    final from = d.predictedFrom, to = d.predictedTo;
    final ranged = from != null && to != null;
    final due = _parse(d.predictedNext!);
    final headline = ranged
        ? '${_short(from)} – ${_short(to)}'
        : due == null
        ? d.predictedNext!
        : formatDay(due);
    return Surface(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ranged
                      ? 'NEXT PERIOD, EXPECTED BETWEEN'
                      : 'NEXT PERIOD, EXPECTED AROUND',
                  style: F.over.copyWith(color: p.ink3),
                ),
                const SizedBox(height: S.x1),
                Text(
                  headline,
                  style: (ranged ? F.n17 : F.n24).copyWith(color: p.ink),
                ),
                const SizedBox(height: S.x1),
                Text(
                  _when(d),
                  style: F.over.copyWith(color: p.ink3, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// When, and what the number is made of. The evidence rides on the same row
  /// as the claim — never a date on its own.
  String _when(CycleData d) {
    final n = d.gapN;
    if (d.predictedFrom == null || d.predictedTo == null) {
      final days = d.daysUntilNext?.round();
      return '${_lead(days)}from your one measured gap, which cannot show how '
          'much your own cycle varies';
    }
    // Offsets off the SAME `days_until_next` the point case uses, never a
    // second read of the clock: the repo already resolved "today" once, and a
    // screen that resolves it again can disagree with itself over midnight.
    final w = _spanDays(d.predictedNext!, d.predictedTo!);
    final centre = d.daysUntilNext?.round();
    final lo = (centre == null || w == null) ? null : centre - w;
    final hi = (centre == null || w == null) ? null : centre + w;
    final String when;
    if (lo == null || hi == null) {
      when = '';
    } else if (hi < 0) {
      when = '${-hi} days past the end of it · ';
    } else if (lo <= 0) {
      when = 'you are inside it now · ';
    } else {
      when = 'in $lo–$hi days · ';
    }
    return '${when}half of your $n measured gaps landed inside a range this '
        'wide';
  }

  String _lead(int? days) => days == null
      ? ''
      : days < 0
      ? '${-days} days late · '
      : days == 0
      ? 'today · '
      : 'in $days days · ';

  int? _spanDays(String from, String to) {
    final a = _parse(from), b = _parse(to);
    return (a == null || b == null) ? null : b.difference(a).inDays;
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
        footnote: 'Descriptive only.',
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
                painter: LineChart(
                  vals,
                  p.on(C.pink),
                  fill: false,
                  t: animate(c, 1),
                  axis: axis,
                ),
              ),
      ),
    );
  }

  // ── symptoms ─────────────────────────────────────────────────────────────

  Widget _symptoms(BuildContext c, P p, CycleData d) {
    final on = d.symptoms[_date] ?? const <String>[];
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              for (final s in kCycleSymptoms)
                Pressable(
                  onTap: () => _toggleSymptom(s),
                  child: AnimatedContainer(
                    duration: motion(c, Motion.fast),
                    padding: const EdgeInsets.symmetric(
                      horizontal: S.x3,
                      vertical: S.x2,
                    ),
                    decoration: BoxDecoration(
                      color: on.contains(s) ? p.wash(C.pink) : p.card2,
                      borderRadius: R.rPill,
                    ),
                    child: Text(
                      s,
                      style: F.cap.copyWith(
                        color: on.contains(s) ? p.on(C.pink) : p.ink2,
                        fontWeight: on.contains(s)
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          _shape(c, p, d),
        ],
      ),
    );
  }

  /// WH-06 — the shape of what she has been ticking, under the chips that
  /// write it. COUNTING ONLY. It is behind a tap because it is a look back and
  /// the chips above are the thing she came here to do.
  ///
  /// THE DENOMINATOR IS DAYS SHE LOGGED, never days elapsed. Symptom logging is
  /// bursty and self-selecting — three tagged days in a fortnight she opened
  /// the app twice is not "21% of days", it is three of two. A rate over the
  /// calendar would be a fabrication wearing a frequency's clothes.
  ///
  /// Nothing here says a week of the cycle CAUSES anything, and nothing is
  /// ranked by significance — these tags never go near a correlation. ~20 tags
  /// against a handful of tagged days is a p-hacking machine at this n.
  Widget _shape(BuildContext c, P p, CycleData d) {
    final s = _symptomShape(d);
    if (s == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: S.x3),
        Pressable(
          semanticLabel: 'What you usually notice',
          onTap: () => setState(() => _showShape = !_showShape),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'What you usually notice',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
              Icon(
                _showShape ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 18,
                color: p.ink3,
              ),
            ],
          ),
        ),
        if (_showShape) ...[
          const SizedBox(height: S.x2),
          for (final e in s.counts)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(e.$1, style: F.cap.copyWith(color: p.ink)),
                  ),
                  Text(e.$2.join(' · '), style: F.n17.copyWith(color: p.ink2)),
                ],
              ),
            ),
          Text(
            'Four numbers, one per week of the cycle, counted back to your own '
            'logged starts. You logged something on ${s.daysByWeek.join(', ')} '
            'days of each week across ${s.cycles} cycles — those are the only '
            'days in any of this.',
            style: F.over.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      ],
    );
  }

  /// `null` when there is not enough to count over: under three logged starts
  /// is under two complete cycles, and a shape drawn on one is a shape drawn on
  /// nothing.
  _Shape? _symptomShape(CycleData d) {
    final starts = <DateTime>[
      for (final l in d.logs)
        if (l['kind'] == 'start') ?_parse(l['date'] as String? ?? ''),
    ]..sort();
    if (starts.length < 3) return null;

    final daysByWeek = List<int>.filled(4, 0);
    final byTag = <String, List<int>>{};
    var daysLogged = 0;
    for (final e in d.symptoms.entries) {
      if (e.value.isEmpty) continue;
      final day = _parse(e.key);
      if (day == null || day.isBefore(starts.first)) continue;
      // Nearest PRECEDING start, not the last one — a day from March belongs to
      // March's cycle, and counting it from the newest start puts it in week 40.
      final from = starts.lastWhere((s) => !s.isAfter(day));
      final week = (day.difference(from).inDays ~/ 7).clamp(0, 3);
      daysLogged++;
      daysByWeek[week]++;
      for (final tag in e.value) {
        (byTag[tag] ??= List<int>.filled(4, 0))[week]++;
      }
    }
    if (daysLogged == 0) return null;
    // Ordered by how often she ticked it. Frequency, not "significance" — one
    // is a count she can check, the other is a test we are not running.
    final counts = byTag.entries.map((e) => (e.key, e.value)).toList()
      ..sort(
        (a, b) => b.$2
            .reduce((x, y) => x + y)
            .compareTo(a.$2.reduce((x, y) => x + y)),
      );
    return _Shape(counts, daysByWeek, starts.length - 1);
  }

  // ── logs ─────────────────────────────────────────────────────────────────

  Widget _logs(BuildContext c, P p, CycleData d) {
    final recent = d.logs.reversed.take(6).toList();
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(
        children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) Divider(color: p.line, height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _parse(recent[i]['date'] as String? ?? '') == null
                          ? '${recent[i]['date']}'
                          : formatDay(_parse(recent[i]['date'] as String)!),
                      style: F.body.copyWith(color: p.ink),
                    ),
                  ),
                  Text(
                    '${recent[i]['kind']}'.toUpperCase(),
                    style: F.over.copyWith(color: p.ink3),
                  ),
                  const SizedBox(width: S.x3),
                  Pressable(
                    semanticLabel: 'Remove ${recent[i]['date']}',
                    onTap: () => _deleteLog(recent[i]['date'] as String),
                    child: Icon(LucideIcons.x, size: 18, color: p.ink3),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// WH-06 — per-tag counts by week of the cycle, and the denominators they sit
/// on. Counts, nothing else: no rate over the calendar, no test, no cause.
class _Shape {
  /// `(tag, [week1, week2, week3, week4])`, most-ticked first.
  final List<(String, List<int>)> counts;

  /// Days she logged ANYTHING, per week. The denominator — and the reason a
  /// zero in week 3 may mean "not that week" or "did not open the app".
  final List<int> daysByWeek;

  /// Measured cycles behind it (logged starts − 1).
  final int cycles;

  const _Shape(this.counts, this.daysByWeek, this.cycles);
}

DateTime? _parse(String ymd) => DateTime.tryParse(ymd);

String _short(String ymd) {
  final d = _parse(ymd);
  return d == null ? ymd : formatDay(d);
}

String _reproLabel(String? s) {
  for (final (key, label, _) in kReproStates) {
    if (key == s) return label;
  }
  return 'Not set';
}

String _phaseLabel(String p) => switch (p) {
  'menstrual' => 'Menstrual',
  'follicular' => 'Follicular',
  'ovulation' => 'Ovulation window',
  'luteal' => 'Luteal',
  _ => p,
};

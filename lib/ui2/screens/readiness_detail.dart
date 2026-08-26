// READINESS — the one composite, taken apart.
//
// Two producers meet on this screen and the copy says so rather than blending
// them: the headline number is the weighted composite, and the breakdown is a
// parallel percentile view of the same four inputs. Presenting the second as
// if it decomposed the first would be a small lie that is very hard to catch.

import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'investigate.dart';
import 'metric_detail.dart';

class ReadinessData {
  final Metric readiness;
  final List<Map<String, dynamic>> breakdown;
  final int inputsUsed;

  /// `readiness_absent_diag` off the stored bundle — per input `{value,
  /// baseline_n}` plus the composite's own `note`. Produced on
  /// EVERY day readiness comes back absent, and until now its only destination
  /// was a Firebase breadcrumb: the app told its developer why the number was
  /// missing and never told the person looking at the gap.
  ///
  /// Null when readiness scored, which is the same fact as the number existing.
  final Map<String, dynamic>? absentDiag;

  /// The last night that scored, when that is NOT today's.
  ///
  /// It is no longer the source of the number above — [overnightMetric]
  /// refuses an older night, so the headline is today's or it is absent, and
  /// the screen no longer wears a date in its nav bar claiming otherwise. What
  /// is left is coverage: naming the night the data stops at, inside the
  /// absence.
  final String? heldOverNight;

  /// DENSE — one slot per calendar day, `null` where no score was stored. The
  /// chart under it is dated, and `seriesOf` (values only) cannot date
  /// anything: a five-point series from five scattered weeks used to be drawn
  /// as five consecutive days.
  final List<double?> series;

  const ReadinessData({
    this.readiness = Metric.empty,
    this.breakdown = const [],
    this.inputsUsed = 0,
    this.heldOverNight,
    this.series = const [],
    this.absentDiag,
  });

  /// The absence diagnostic off a stored day bundle. Read straight from
  /// `day_result` the way `InvestigateData.load` reads `imported` — no
  /// repository accessor exists and this is the only screen that wants it.
  static Future<Map<String, dynamic>?> _absentDiag(String? day) async {
    if (day == null) return null;
    final payload = (await LocalDb.dayResult(day))?['payload_json'];
    if (payload is! String || !payload.contains('"readiness_absent_diag"')) {
      return null;
    }
    final b = jsonDecode(payload);
    final diag = b is Map ? b['readiness_absent_diag'] : null;
    return diag is Map ? diag.cast<String, dynamic>() : null;
  }

  static Future<ReadinessData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final chart = await repo.getChart('recovery');

    final daily = today['daily'];
    final gb = cd['readiness_glassbox'];
    final v = envValue(gb) ?? const <String, dynamic>{};
    final bd = v['breakdown'];

    final readiness = overnightMetric(today, daily is Map ? daily['readiness'] : null);

    return ReadinessData(
      readiness: readiness,
      // `narrative` and the glass-box `score` are DELIBERATELY not read. Both
      // belong to the deprecated percentile score, which bands at 70/40 while
      // the headline composite bands at 61/37/26 (see `readinessBand`) —
      // printing its verdict under the ring put "You're ready" directly
      // beneath "45 · Take it easy". The
      // breakdown below IS worth keeping; it is a parallel ranking of the same
      // four inputs, and the footer now says so.
      breakdown: [
        for (final e in (bd is List ? bd : const []))
          if (e is Map) e.cast<String, dynamic>(),
      ],
      inputsUsed: (v['inputs_used'] as num?)?.toInt() ?? 0,
      heldOverNight: heldOverNightOf(today),
      series: denseDays(pointsOf(chart), 90),
      // Only read when there is nothing to explain away — a scored day has no
      // diag in its bundle anyway, and this is one more day_result decode.
      //
      // TODAY'S DAY, never the held-over one. The held-over night usually
      // scored fine, so its diagnostic explains an absence that is not the one
      // on screen: it would list four measured inputs under a card saying the
      // number is missing. A day with no bundle has no diag and this comes back
      // null, which is correct — the note on the metric is the reason then.
      absentDiag: readiness.value != null
          ? null
          : await _absentDiag(
              (today['status'] as Map?)?['today_day']?.toString()),
    );
  }
}

class ReadinessDetail extends StatefulWidget {
  final ReadinessData? data;
  const ReadinessDetail({super.key, this.data});

  @override
  State<ReadinessDetail> createState() => _ReadinessDetailState();
}

class _ReadinessDetailState extends State<ReadinessDetail> {
  ReadinessData? _d;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _d = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final d = await ReadinessData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d ?? const ReadinessData();
    final v = d.readiness.value;
    final band = readinessBand(v);

    // No date in the nav bar. It named the held-over night, and the headline
    // can no longer BE that night — a date up here now would be labelling
    // today's number with somebody else's day.
    return detailScaffold(c, 'Readiness', [
      if (_loading && _d == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else ...[
        if (v == null) ...[
          // No `why:`. The pipeline records why readiness abstained on every
          // day it does, and the "What was missing" section directly below is
          // built from that record — a sentence written here was competing
          // with the real answer one line down and winning.
          StatusCard.forMetric('Readiness is not scored', d.readiness,
                  // Where the data stops, appended to whatever the pipeline
                  // said. Not a substitute for the reason and not a reading —
                  // "the last one was Saturday" is a fact about coverage.
                  gap: d.heldOverNight == null
                      ? null
                      : 'The last night scored was '
                          '${prettyDay(d.heldOverNight)}.') ??
              const SizedBox.shrink(),
          if (d.absentDiag != null)
            Section('What was missing', _absence(c, p, d.absentDiag!)),
        ] else
          Surface(
            child: Column(children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(alignment: Alignment.center, children: [
                  CustomPaint(
                    size: const Size(150, 150),
                    painter: Ring(d.readiness.normalized(100), p.on(band.color),
                        p.track,
                        stroke: 14, t: animate(c, 1)),
                  ),
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${v.round()}', style: F.n48.copyWith(color: p.ink)),
                    Text(band.label, style: F.cap.copyWith(color: p.ink3)),
                  ]),
                ]),
              ),
            ]),
          ),

        if (d.breakdown.isNotEmpty) ...[
          Section('What went into it', _breakdown(c, p, d)),
          const SizedBox(height: S.x4),
          Surface(
            elevation: 0,
            color: p.card2,
            child: Row(children: [
              Expanded(
                child: Text(
                  '${d.inputsUsed}/${d.breakdown.length} inputs. Each one is '
                  'ranked against your own history — a parallel view of the '
                  'same inputs, not slices of the number above.',
                  style: F.cap.copyWith(color: p.ink3, height: 1.5),
                ),
              ),
            ]),
          ),
        ] else if (v != null)
          Section(
            'What went into it',
            const StatusCard(
              'No breakdown yet',
              'Ranking each input against your own history takes about two '
                  'weeks of nights.',
              icon: LucideIcons.listTree,
            ),
          ),

        // The header used to say "Last 90 days" over a chart of five points.
        // It says what is drawn.
        Section(
          _historyTitle(d),
          !d.series.any((v) => v != null)
              ? const StatusCard(
                  'No readiness history',
                  '0 days scored.',
                  fix: 'Wear the band overnight',
                  icon: LucideIcons.chartLine,
                )
              : Surface(child: _history(c, d)),
        ),
        const SizedBox(height: S.x5),
        investigateRow(c, () => go(c, const Investigate('readiness'))),
      ],
    ]);
  }

  /// The last 90 CALENDAR days, trimmed to start at the first day that
  /// actually has a score — so the x labels span real dates and the empty run
  /// before the first sync is not drawn as ninety missing days.
  List<double?> _window(ReadinessData d) {
    final first = d.series.indexWhere((v) => v != null);
    return first <= 0 ? d.series : d.series.sublist(first);
  }

  String _historyTitle(ReadinessData d) {
    final n = d.series.any((v) => v != null) ? _window(d).length : 0;
    return n == 0 ? 'History' : 'Last $n day${n == 1 ? '' : 's'}';
  }

  Widget _history(BuildContext c, ReadinessData d) {
    final win = _window(d);
    // Readiness is a 0–100 score and the axis says so — auto-scaling turned a
    // 71-to-76 week into a chart that looked like a collapse and a recovery.
    const axis = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);
    final p = P.of(c);
    return ChartFrame(
      title: 'Readiness',
      unit: '/100',
      height: 120,
      yAxis: axis,
      // Slot 0 is `length - 1` days behind today, not `length` — the last slot
      // IS today. MetricDetail draws the same `recovery` series and already
      // counts it this way; the two screens dated one chart differently.
      xLabels: [
        '${win.length - 1} day${win.length == 2 ? '' : 's'} ago',
        'Today',
      ],
      series: win,
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(win, p.on(C.green), dots: false, t: animate(c, 1),
            axis: axis),
      ),
    );
  }

  /// The pipeline's own absence diagnostic, one row per input. Two facts per
  /// row and neither is inferred here: did last night produce this input, and
  /// how many of your own nights are behind it. The line underneath QUOTES the
  /// composite's note rather than guessing a reason from the rows above it —
  /// and it never turns a night count into a date, because nothing in the
  /// pipeline knows when you will next wear the band.
  Widget _absence(BuildContext c, P p, Map<String, dynamic> diag) {
    final rows = <(String, String)>[];
    for (final k in const ['hrv', 'rhr', 'resp', 'temp']) {
      final e = diag[k];
      if (e is! Map) continue;
      final n = (e['baseline_n'] as num?)?.toInt() ?? 0;
      rows.add((
        driverLabel(k),
        '${e['value'] == true ? 'Measured' : 'Not measured'} · '
            '$n night${n == 1 ? '' : 's'} of your own history',
      ));
    }
    final note = diag['note']?.toString();
    final need = needMessageFromNote(note);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.isNotEmpty)
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x3),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rows[i].$1, style: F.body.copyWith(color: p.ink)),
                      Text(rows[i].$2,
                          style: F.over.copyWith(color: p.ink3)),
                    ]),
              ),
            ],
          ]),
        ),
      const SizedBox(height: S.x3),
      Text(
        need != null
            ? '$need. Each input is ranked against your own nights, so the '
                'score cannot start before there are enough of them.'
            : (note != null && note.isNotEmpty
                ? note
                : 'Everything above was present, and the comparison against '
                    'your own history still could not be made.'),
        style: F.cap.copyWith(color: p.ink3, height: 1.5),
      ),
    ]);
  }

  Widget _breakdown(BuildContext c, P p, ReadinessData d) {
    final rows = d.breakdown;
    // THE WEIGHT THAT WAS USED, not the catalog weight. The score is
    // `wpsum / wsum` over the USABLE inputs only, so the raw .40/.30/.18/.12
    // are what each input would have carried had everything been present — with
    // skin temperature missing, HRV's 40% actually carried 45.5%.
    final wsum = rows
        .where((r) => r['used'] == true)
        .fold<double>(0, (a, r) => a + ((r['weight'] as num?)?.toDouble() ?? 0));
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          _row(p, rows[i], wsum),
        ],
      ]),
    );
  }

  Widget _row(P p, Map<String, dynamic> r, double wsum) {
    final key = r['label']?.toString() ?? '';
    final raw = (r['weight'] as num?)?.toDouble();
    final contribution = (r['weighted_contribution'] as num?);
    final used = r['used'] == true;
    final pastMdc = r['past_mdc'] == true;
    // No weight, or an input that carried none, means no percentage — `?? 0`
    // printed a confident "0% weight" for a number nobody reported.
    final share = !used || raw == null || wsum <= 0 ? null : raw / wsum;

    final parts = [
      if (share != null) '${(share * 100).round()}% weight',
      if (!used) 'not available',
      if (used && contribution == null) 'contribution not reported',
      // The temperature input is a raw sensor deviation, not a calibrated
      // temperature. It gets said, every time.
      if (key == 'temp') 'relative, uncalibrated',
      // An unlabelled glyph is not an explanation. This is the
      // smallest-worthwhile-change gate, so it says what it means.
      if (used && !pastMdc) 'within your usual spread',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(driverLabel(key), style: F.body.copyWith(color: p.ink)),
            Text(parts.join(' · '),
                style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        // No contribution number means no number — never a bare em-dash. The
        // sub-line above says which case it is.
        if (used && contribution != null) ...[
          const SizedBox(width: S.x3),
          Text(
            '${contribution >= 0 ? '+' : '−'}'
            '${contribution.abs().toStringAsFixed(1)}',
            style: F.n17.copyWith(
                color: p.on(contribution >= 0 ? C.green : C.orange)),
          ),
        ],
      ]),
    );
  }
}

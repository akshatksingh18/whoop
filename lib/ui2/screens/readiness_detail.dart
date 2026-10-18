// READINESS — the one composite, taken apart.
//
// Two producers meet on this screen and the copy says so rather than blending
// them: the headline number is the weighted composite, and the breakdown is a
// parallel percentile view of the same four inputs. Presenting the second as
// if it decomposed the first would be a small lie that is very hard to catch.

import 'dart:convert' show jsonDecode;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../compute/readiness_explain.dart';
import '../../data/db.dart';
import '../../data/day_label.dart' show dayLabelAtSec, DayClock;
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart';
import '../ui2.dart';
import 'home_screen.dart';
import 'metric_detail.dart';
import '../recent_hrv_card.dart';

/// Why [day]'s nightly HRV is missing, in plain words ([hrvWhy]), or null when
/// it was measured, the day has no record, or the stored note gives no reason.
Future<String?> hrvMissingReason(String? day) async {
  if (day == null) return null;
  final payload = (await LocalDb.dayResult(day))?['payload_json'];
  if (payload is! String) return null;
  final b = jsonDecode(payload);
  final clin = b is Map ? b['clinical'] : null;
  final m = clin is Map ? clin['rmssd_sleep_session'] : null;
  if (m is! Map || m['value'] is num) return null;
  return hrvWhy(m['note']?.toString());
}

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

  /// Why breathing rate did not count last night, in plain words, or null
  /// when it was measured (or the night has no record).
  final String? breathingNote;

  /// Why last night's HRV is missing, in plain words, or null when it was
  /// measured or the stored note gives no reason.
  final String? hrvNote;

  /// Last night's HRV against the score's own comparison (Build 90), or null.
  final RecentHrvView? hrv;

  const ReadinessData({
    this.readiness = Metric.empty,
    this.hrv,
    this.breakdown = const [],
    this.inputsUsed = 0,
    this.heldOverNight,
    this.series = const [],
    this.absentDiag,
    this.breathingNote,
    this.hrvNote,
  });

  /// The stored reason a night's breathing rate was withheld
  /// (`respiration.rsa.note`), in plain words. Null when it was measured.
  static Future<String?> _breathingNote(String? day) async {
    if (day == null) return null;
    final payload = (await LocalDb.dayResult(day))?['payload_json'];
    if (payload is! String) return null;
    final b = jsonDecode(payload);
    if (b is! Map) return null;
    final scalars = b['scalars'];
    if (scalars is Map && scalars['resp_rate'] is num) return null;
    final resp = b['respiration'];
    final rsa = resp is Map ? resp['rsa'] : null;
    final note = (rsa is Map ? rsa['note'] : null)?.toString() ?? '';
    return breathingWhy(note);
  }

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

  /// The HEADLINE composite's own per-input contributions for [day] (B88-11),
  /// shaped like the rows the breakdown renders. The glass-box percentile is a
  /// different model; showing its ranking under the composite ring explained a
  /// calculation that did not produce the number. Inputs the composite did not
  /// use are listed as unused so their absence stays visible.
  static Future<List<Map<String, dynamic>>> _compositeBreakdown(
    String? day,
  ) async {
    if (day == null) return const [];
    final payload = (await LocalDb.dayResult(day))?['payload_json'];
    if (payload is! String) return const [];
    final b = jsonDecode(payload);
    final clin = b is Map ? b['clinical'] : null;
    final comp = clin is Map ? clin['readiness_composite'] : null;
    final drivers = comp is Map ? comp['drivers'] : null;
    const keyOf = {'HRV': 'hrv', 'RHR': 'rhr', 'RR': 'resp', 'sleep': 'sleep'};
    final byLabel = <String, Map>{
      for (final d in (drivers is List ? drivers : const []))
        if (d is Map && keyOf[d['label']] != null) keyOf[d['label']]!: d,
    };
    const nominal = {'hrv': 0.35, 'rhr': 0.25, 'sleep': 0.20, 'resp': 0.12};
    final rows = [
      for (final e in nominal.entries)
        <String, dynamic>{
          'label': e.key,
          'weight': e.value,
          'used': byLabel.containsKey(e.key),
          'weighted_contribution': byLabel[e.key]?['contribution'],
          'past_mdc': false,
        },
    ];
    // Build 90 (Akshat's option A): the points each input moved the score from
    // a typical night, and last night's value against the same usual range the
    // score compared it with. Missing pieces leave the older plain row.
    final scored = [
      for (final r in rows)
        if (r['used'] == true && r['weighted_contribution'] is num) r,
    ];
    final pts = recoveryPoints([
      for (final r in scored) (r['weighted_contribution'] as num).toDouble(),
    ]);
    for (var i = 0; i < scored.length; i++) {
      scored[i]['points'] = pts[i];
    }
    for (final r in rows) {
      final key = r['label'] as String;
      final series = await _series(_seriesKey[key]!);
      final today = series.where((s) => s.date == day).toList();
      if (today.isEmpty) continue;
      final v = today.last.value;
      final scale = recoveryScale(recoveryBaseline(series, day));
      if (scale == null) continue;
      final usual = usualRange(scale);
      r['value_text'] = _valueText(key, v);
      r['usual_text'] =
          'usual ${_rangeText(key, usual.lo, usual.hi)}';
      r['word'] = usualWord((v - scale.centre) / scale.spread);
    }
    return rows;
  }

  static const _seriesKey = {
    'hrv': 'ln_rmssd_v2',
    'rhr': 'rhr',
    'sleep': 'tst_min',
    'resp': 'resp_rate',
  };

  static Future<List<DatedValue>> _series(String key) async => [
    for (final r in await LocalDb.metricSeries(key, measuredOnly: true))
      if (r['date'] is String && r['value'] is num)
        (date: r['date'] as String, value: (r['value'] as num).toDouble()),
  ];

  static String _hm(double minutes) {
    final m = minutes.round();
    return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  static String _num(String key, double v) => switch (key) {
    'hrv' => math.exp(v).round().toString(),
    'rhr' => v.round().toString(),
    'resp' => v.toStringAsFixed(1),
    _ => _hm(v),
  };

  static String _valueText(String key, double v) =>
      '${_num(key, v)}${switch (key) {
        'hrv' => ' ms',
        'rhr' => ' bpm',
        'resp' => ' /min',
        _ => '',
      }}';

  static String _rangeText(String key, double lo, double hi) =>
      '${_num(key, lo)}–${_num(key, hi)}';

  /// The recent-HRV card for [day], on the score's own series and window.
  static Future<RecentHrvView?> _recentHrv(String? day) async =>
      day == null ? null : loadRecentHrv(day);

  static Future<ReadinessData> load(LocalRepository repo, {String? day}) async {
    final today = await repo.getToday();
    final chart = await repo.getChart('recovery');
    final currentDay = (today['status'] as Map?)?['today_day']?.toString();
    if (day != null && day != currentDay) {
      final matches = pointsOf(chart).where((p) => dayLabelAtSec(p.t) == day);
      final readiness = matches.isEmpty
          ? Metric.empty
          : Metric.parse(matches.last.v);
      final bd = await _compositeBreakdown(day);
      return ReadinessData(
        readiness: readiness,
        hrv: readiness.value == null ? null : await _recentHrv(day),
        breakdown: bd,
        inputsUsed: bd.where((r) => r['used'] == true).length,
        series: denseDays(pointsOf(chart), 90),
        absentDiag: await _absentDiag(day),
        breathingNote: await _breathingNote(day),
        hrvNote: await hrvMissingReason(day),
      );
    }

    final daily = today['daily'];
    final status = today['status'] as Map?;
    final night = (status?['overnight_day'] ?? status?['today_day'])
        ?.toString();
    final bd = await _compositeBreakdown(night);

    final readiness = overnightMetric(
      today,
      daily is Map ? daily['readiness'] : null,
    );

    return ReadinessData(
      readiness: readiness,
      hrv: await _recentHrv(night),
      // The composite's OWN contributions (B88-11), not the glass box.
      breakdown: bd,
      inputsUsed: bd.where((r) => r['used'] == true).length,
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
              (today['status'] as Map?)?['today_day']?.toString(),
            ),
      breathingNote: await _breathingNote(
        (today['status'] as Map?)?['today_day']?.toString(),
      ),
      hrvNote: await hrvMissingReason(
        (status?['overnight_day'] ?? status?['today_day'])?.toString(),
      ),
    );
  }
}

class ReadinessDetail extends StatefulWidget {
  final ReadinessData? data;
  final String? day;

  /// Inside the shared metric screen's Today tab: no nav bar and no history,
  /// which that screen's ranges already draw.
  final bool embedded;
  const ReadinessDetail({
    super.key,
    this.data,
    this.day,
    this.embedded = false,
  });

  @override
  State<ReadinessDetail> createState() => _ReadinessDetailState();
}

/// A withheld breathing rate's stored note, in plain words.
String breathingWhy(String note) {
  final n = note.toLowerCase();
  if (n.contains('artifact')) return 'too much movement or signal noise';
  if (n.contains('consensus') || n.contains('agree')) {
    return 'the night\'s breathing windows disagreed';
  }
  if (n.contains('too few') || n.contains('beats'))
    return 'not enough beat data';
  if (n.contains('beat rate')) return 'heart rate too high to read breathing';
  return 'not measured';
}

/// Why a day has no readiness score, in a few words, from that day's stored
/// `readiness_absent_diag`. [hasDay] is false when the day was never analysed.
///
/// The rule behind most of these: a score needs at least 14 earlier nights
/// with HRV and resting heart rate measured (`readinessCompositeMinBaseline`
/// in packages/analytics), counting only days this band measured (imported
/// days are kept out of the baseline on purpose).
String readinessGap(Map<String, dynamic>? diag, {required bool hasDay}) {
  if (!hasDay) return 'no data that day';
  if (diag == null) return 'not scored';
  bool measured(String k) =>
      diag[k] is Map && (diag[k] as Map)['value'] == true;
  int nights(String k) => diag[k] is Map
      ? (((diag[k] as Map)['baseline_n'] as num?)?.toInt() ?? 0)
      : 0;
  const need = 14;
  if (!measured('hrv') && !measured('rhr'))
    return 'no sleep heart data that night';
  final short = [
    if (measured('hrv') && nights('hrv') < need) nights('hrv'),
    if (measured('rhr') && nights('rhr') < need) nights('rhr'),
  ];
  if (short.isNotEmpty) {
    final have = short.reduce((a, b) => a < b ? a : b);
    return 'building your baseline: $have of $need nights';
  }
  if (!measured('hrv')) return 'HRV not measured that night';
  if (!measured('rhr')) return 'resting heart rate not measured';
  return 'held back: a reading was far outside your range';
}

class _ReadinessDetailState extends State<ReadinessDetail> with RevisionReload {
  /// The day under the finger on the history chart, or null.
  int? _pick;

  /// Why each unscored day under the finger had no score, read once per day.
  final _gaps = <String, String>{};

  Future<void> _loadGap(String day) async {
    if (_gaps.containsKey(day)) return;
    _gaps[day] = '…';
    String why;
    try {
      final row = await LocalDb.dayResult(day);
      final payload = row?['payload_json'];
      Map<String, dynamic>? diag;
      if (payload is String && payload.contains('"readiness_absent_diag"')) {
        final b = jsonDecode(payload);
        final x = b is Map ? b['readiness_absent_diag'] : null;
        diag = x is Map ? x.cast<String, dynamic>() : null;
      }
      why = readinessGap(diag, hasDay: row != null);
    } catch (_) {
      why = 'not scored';
    }
    if (mounted) setState(() => _gaps[day] = why);
  }

  ReadinessData? _d;
  bool _showHow = false;

  /// One plain line for the band the score falls in.
  static String _advice(int tier) => switch (tier) {
    3 => 'Recovered. A good day to push hard.',
    2 => 'Normal recovery. Train as planned.',
    1 => 'Below your usual. Keep today easier.',
    _ => 'Well below your usual. Put rest first.',
  };
  bool _loading = true, _failed = false;

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

  @override
  bool get revisionReloads => widget.data == null;
  @override
  void reload() {
    _gaps.clear();
    _load();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final token = beginRead(#readiness);
    try {
      final d = await ReadinessData.load(repo, day: widget.day);
      if (stillNewest(#readiness, token))
        setState(() {
          _d = d;
          _loading = false;
          _failed = false;
        });
    } catch (_) {
      if (stillNewest(#readiness, token))
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d ?? const ReadinessData();
    final v = d.readiness.value;
    final band = readinessBand(v, l);
    final zone = widget.day == null
        ? null
        : DayClock.abbreviation(
            widget.day!,
            nowSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          );

    // No date in the nav bar. It named the held-over night, and the headline
    // can no longer BE that night — a date up here now would be labelling
    // today's number with somebody else's day.
    return detailScaffold(
      c,
      l?.readinessDetailTitle ?? 'Recovery',
      embedded: widget.embedded,
      [
        if (widget.day != null)
          Text(
            '${prettyDay(widget.day, l)}${zone == null ? '' : ' · $zone'}',
            style: F.body.copyWith(color: p.ink2),
          ),
        if (_failed)
          StatusCard(
            'Recovery could not load',
            'Your saved nights are intact.',
            fix: 'Retry',
            onFix: _load,
          )
        else if (_loading && _d == null) ...[
          const SizedBox(height: S.x8),
          const Center(child: CircularProgressIndicator()),
        ] else ...[
          if (v == null) ...[
            // No `why:`. The pipeline records why readiness abstained on every
            // day it does, and the "What was missing" section directly below is
            // built from that record — a sentence written here was competing
            // with the real answer one line down and winning.
            StatusCard.forMetric(
                  l?.readinessDetailNotScoredTitle ?? 'Recovery is not scored',
                  d.readiness,
                  // Where the data stops, appended to whatever the pipeline
                  // said. Not a substitute for the reason and not a reading —
                  // "the last one was Saturday" is a fact about coverage.
                  gap: d.heldOverNight == null
                      ? null
                      : (l?.readinessDetailLastNightScored(
                              prettyDay(d.heldOverNight, l),
                            ) ??
                            'The last night scored was '
                                '${prettyDay(d.heldOverNight, l)}.'),
                ) ??
                const SizedBox.shrink(),
            if (d.absentDiag != null)
              Section(
                l?.readinessDetailWhatWasMissing ?? 'What was missing',
                _absence(c, p, d.absentDiag!),
              ),
          ] else
            // Build 88 (mock `7-recovery`): the score as the hero in the
            // recovery colour, and what drove it in the same panel.
            Surface(
              pad: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HeroStat(
                    illustration: const CalmIllustration(),
                    value: '${v.round()}',
                    color: C.recovery,
                    label: l?.homeRingRecovery ?? 'Recovery',
                    lines: [
                      band.label,
                      'vs your own last 28 nights, within 60 days',
                    ],
                  ),
                  Text(
                    _advice(band.tier),
                    style: F.body.copyWith(color: p.ink2),
                  ),
                  if (_lead(c, d) case final lead?) ...[
                    const SizedBox(height: S.x2),
                    Text(lead, style: F.body.copyWith(color: p.ink)),
                  ],
                  if (d.breakdown.isNotEmpty) ...[
                    const SizedBox(height: S.x3),
                    Divider(color: p.line, height: 1),
                    const SizedBox(height: S.x3),
                    Text(
                      _hasPoints(d) ? 'WHAT MOVED IT' : 'WHAT DROVE IT',
                      style: F.label.copyWith(color: p.ink2),
                    ),
                    _breakdown(c, p, d),
                    if (_hasPoints(d))
                      Padding(
                        padding: const EdgeInsets.only(top: S.x1),
                        child: Text(
                          'Points each input moved the score from a typical '
                          'night (50). A bar to the left lowers it.',
                          style: F.cap.copyWith(color: p.ink2),
                        ),
                      ),
                    if (d.breathingNote != null)
                      Text(
                        'Breathing rate not counted last night: ${d.breathingNote}.',
                        style: F.cap.copyWith(color: p.ink2),
                      ),
                  ],
                ],
              ),
            ),

          if (v != null && d.hrv != null) ...[
            const SizedBox(height: S.x3),
            RecentHrvCard(d.hrv!, sharedWith: 'the HRV page'),
          ],
          if (d.breakdown.isNotEmpty) ...[
            // A scored day shows its drivers in the hero panel above; an
            // unscored day still lists them here.
            if (v == null) Section('What drove it', _breakdown(c, p, d)),
            const SizedBox(height: S.x4),
            Pressable(
              onTap: () => setState(() => _showHow = !_showHow),
              semanticLabel: 'How it is worked out',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'How it\'s worked out',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  ),
                  Icon(
                    _showHow ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 16,
                    color: p.ink3,
                  ),
                ],
              ),
            ),
            if (_showHow) ...[
              const SizedBox(height: S.x2),
              Surface(
                elevation: 0,
                color: p.card2,
                child: Text(
                  '${d.inputsUsed} of ${d.breakdown.length} inputs were available. '
                  'Each is compared with your own recent nights: HRV carries '
                  '35% of the weight, resting heart rate 25%, last night\'s sleep '
                  '20% and breathing rate 12%. Resting HR is the lowest 30-minute '
                  'average while asleep. Skin temperature is left out on '
                  'this band (its sensor reading is not a temperature). '
                  '"Usual" is within one typical night-to-night swing of your '
                  'last 28 measured nights. Points walk from a typical night '
                  '(50) to the score, biggest input first, so they add up to it.',
                  style: F.cap.copyWith(color: p.ink3, height: 1.5),
                ),
              ),
            ],
          ] else if (v != null)
            Section(
              l?.readinessDetailWhatWentIntoIt ?? 'What went into it',
              StatusCard(
                l?.readinessDetailNoBreakdownTitle ?? 'No breakdown yet',
                l?.readinessDetailNoBreakdownBody ??
                    'Ranking each input against your own history takes about two '
                        'weeks of nights.',
                icon: LucideIcons.listTree,
              ),
            ),

          // The header used to say "Last 90 days" over a chart of five points.
          // It says what is drawn.
          if (!widget.embedded)
            Section(
              _historyTitle(c, d),
              !d.series.any((v) => v != null)
                  ? StatusCard(
                      l?.readinessDetailNoHistoryTitle ??
                          'No readiness history',
                      l?.readinessDetailNoHistoryBody ?? '0 days scored.',
                      fix:
                          l?.readinessDetailWearOvernight ??
                          'Wear the band overnight',
                      icon: LucideIcons.chartLine,
                    )
                  : Surface(child: _history(c, d)),
            ),
        ],
      ],
    );
  }

  /// The last 90 CALENDAR days, trimmed to start at the first day that
  /// actually has a score — so the x labels span real dates and the empty run
  /// before the first sync is not drawn as ninety missing days.
  List<double?> _window(ReadinessData d) {
    final first = d.series.indexWhere((v) => v != null);
    return first <= 0 ? d.series : d.series.sublist(first);
  }

  String _historyTitle(BuildContext c, ReadinessData d) {
    final l = AppLocalizations.of(c);
    final n = d.series.any((v) => v != null) ? _window(d).length : 0;
    return n == 0
        ? (l?.readinessDetailHistoryTitle ?? 'History')
        : (l?.readinessDetailLastNDays(n) ?? 'Last $n day${n == 1 ? '' : 's'}');
  }

  Widget _history(BuildContext c, ReadinessData d) {
    final win = _window(d);
    // Readiness is a 0–100 score and the axis says so — auto-scaling turned a
    // 71-to-76 week into a chart that looked like a collapse and a recovery.
    const axis = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final n = win.length;
    String label(int i) {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day - (n - 1 - i));
      return '${day.year}-${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
    }

    String says(int i) {
      final v = win[i];
      final when = i == n - 1 ? 'Today' : prettyDay(label(i), l);
      if (v != null) return '$when · ${v.round()} ${readinessBand(v, l).label}';
      return '$when · no score, ${_gaps[label(i)] ?? '…'}';
    }

    // A line like every other day-by-day chart; the band of the touched day
    // is in the readout. Point i sits at i/(n-1).
    int at(double f) => n < 2 ? 0 : (f * (n - 1)).round().clamp(0, n - 1);
    return ChartFrame(
      title: l?.readinessDetailTitle ?? 'Recovery',
      unit: l?.readinessDetailUnit ?? '/100',
      height: 120,
      yAxis: axis,
      readout: _pick == null || _pick! >= n ? null : says(_pick!),
      // Slot 0 is `length - 1` days behind today, not `length` — the last slot
      // IS today. MetricDetail draws the same `recovery` series and already
      // counts it this way; the two screens dated one chart differently.
      xLabels: [
        l?.readinessDetailDaysAgo(win.length - 1) ??
            '${win.length - 1} day${win.length == 2 ? '' : 's'} ago',
        l?.readinessDetailToday ?? 'Today',
      ],
      series: win,
      child: Scrubber(
        value: _pick == null || n < 2 ? null : _pick! / (n - 1),
        step: n < 2 ? 1 : 1 / (n - 1),
        label: 'Readiness history',
        describe: (f) => says(at(f)),
        onChanged: (f) {
          final i = at(f);
          setState(() => _pick = i);
          if (win[i] == null) _loadGap(label(i));
        },
        child: CustomPaint(
          size: Size.infinite,
          painter: LineChart(
            win,
            p.on(C.green),
            fill: false,
            dots: n <= 40,
            dotInk: p.card,
            axis: axis,
            cursor: _pick,
            cursorInk: p.ink,
            t: animate(c, 1),
          ),
        ),
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
    final l = AppLocalizations.of(c);
    final rows = <(String, String)>[];
    for (final k in const ['hrv', 'rhr', 'sleep', 'resp', 'temp']) {
      final e = diag[k];
      if (e is! Map) continue;
      final n = (e['baseline_n'] as num?)?.toInt() ?? 0;
      rows.add((
        k == 'rhr' ? 'Resting HR · asleep' : driverLabel(k, l),
        '${e['value'] == true ? (l?.readinessDetailMeasured ?? 'Measured') : (l?.readinessDetailNotMeasured ?? 'Not measured')} · '
            '${l?.readinessDetailNightsOfHistory(n) ?? '$n night${n == 1 ? '' : 's'} of your own history'}',
      ));
    }
    final note = diag['note']?.toString();
    final need = needMessageFromNote(note);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty)
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(color: p.line, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].$1, style: F.body.copyWith(color: p.ink)),
                        Text(rows[i].$2, style: F.over.copyWith(color: p.ink3)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: S.x3),
        Text(
          need != null
              ? (l?.readinessDetailNeedSuffix(need) ??
                    '$need. Each input is ranked against your own nights, so the '
                        'score cannot start before there are enough of them.')
              : (note != null && note.isNotEmpty
                    ? note
                    : (l?.readinessDetailNoNoteFallback ??
                          'Everything above was present, and the comparison against '
                              'your own history still could not be made.')),
          style: F.cap.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
    );
  }

  static bool _hasPoints(ReadinessData d) =>
      d.breakdown.any((r) => r['points'] is int);

  /// "Mostly HRV." plus what it did, from the biggest movers (3+ points).
  String? _lead(BuildContext c, ReadinessData d) {
    final l = AppLocalizations.of(c);
    final movers = [
      for (final r in d.breakdown)
        if (r['points'] is int && (r['points'] as int).abs() >= 3) r,
    ]..sort((a, b) =>
        (b['points'] as int).abs().compareTo((a['points'] as int).abs()));
    if (!_hasPoints(d)) return null;
    if (movers.isEmpty) return 'Every input was close to your usual.';
    String name(Map r) {
      final k = r['label'];
      return k == 'rhr' ? 'Resting HR' : driverLabel(k, l);
    }

    // Lower-case mid-sentence, but never an acronym ("resting HR", "HRV").
    String lower(String s) => s
        .split(' ')
        .map((w) => w == w.toUpperCase() ? w : w.toLowerCase())
        .join(' ');

    final top = movers.first;
    final word = (top['word'] as String?)?.toLowerCase();
    final head = movers.length == 1
        ? 'Mostly ${name(top)}.'
        : 'Mostly ${name(top)}, then ${lower(name(movers[1]))}.';
    final what = word == null
        ? ''
        : ' Last night\'s ${lower(name(top))} '
              'was ${word.replaceFirst(' usual', ' your usual')}';
    final rest = movers.length == 1 ? '; everything else was close to usual.' : '.';
    return word == null ? head : '$head$what$rest';
  }

  Widget _breakdown(BuildContext c, P p, ReadinessData d) {
    final rows = d.breakdown;
    // THE WEIGHT THAT WAS USED, not the catalog weight. The score is
    // `wpsum / wsum` over the USABLE inputs only, so the raw .35/.25/.20/.12/.08
    // are what each input would have carried had everything been present — with
    // skin temperature missing, HRV's 40% actually carried 45.5%.
    final wsum = rows
        .where((r) => r['used'] == true)
        .fold<double>(
          0,
          (a, r) => a + ((r['weight'] as num?)?.toDouble() ?? 0),
        );
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(color: p.line, height: 1),
            _row(c, p, rows[i], wsum),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext c, P p, Map<String, dynamic> r, double wsum) {
    if (r['points'] is int || r['used'] != true) return _rowA(c, p, r);
    return _rowOld(c, p, r, wsum);
  }

  /// Build 90 (option A): label and points; value against the usual range and
  /// a plain word; a bar centred on "no effect". A missing input says so.
  Widget _rowA(BuildContext c, P p, Map<String, dynamic> r) {
    final l = AppLocalizations.of(c);
    final key = r['label']?.toString() ?? '';
    final name = key == 'rhr' ? 'Resting HR · asleep' : driverLabel(key, l);
    final used = r['used'] == true;
    final pts = r['points'] as int?;
    final scale = math.max(
      20,
      _d?.breakdown.fold<int>(
            0,
            (m, x) => math.max(m, ((x['points'] as int?) ?? 0).abs()),
          ) ??
          20,
    );
    final lowers = pts != null && pts <= -3;
    final tone = lowers ? p.on(C.alert) : p.ink;
    final value = [
      ?r['value_text'] as String?,
      ?r['usual_text'] as String?,
    ].join(' · ');
    final word = !used
        ? 'Unavailable, not counted'
        : (r['word'] as String?) ?? '';
    final metric = switch (key) {
      'hrv' => 'hrv',
      'rhr' => 'resting_hr',
      'resp' => 'resp_rate',
      'sleep' => 'sleep',
      _ => null,
    };
    final signed = pts == null ? '' : (pts > 0 ? '+$pts' : pts < 0 ? '−${-pts}' : '0');
    return Pressable(
      onTap: metric == null
          ? null
          : () => go(c, MetricDetail.at(metric, widget.day)),
      semanticLabel: [
        name,
        if (value.isNotEmpty) value,
        if (word.isNotEmpty) word,
        if (pts != null) '$signed points',
      ].join(', '),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (pts != null)
                  Text(
                    signed,
                    style: F.body.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (value.isNotEmpty || word.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: S.x2,
                children: [
                  if (value.isNotEmpty)
                    Text(value, style: F.cap.copyWith(color: p.ink2)),
                  if (word.isNotEmpty)
                    Text(
                      word,
                      style: F.cap.copyWith(
                        color: lowers ? p.on(C.alert) : p.ink2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            if (!used && key == 'hrv' && _d?.hrvNote != null)
              Text(_d!.hrvNote!, style: F.cap.copyWith(color: p.ink2)),
            if (pts != null) ...[
              const SizedBox(height: S.x2),
              ExcludeSemantics(
                child: SizedBox(
                  height: 8,
                  child: LayoutBuilder(
                    builder: (c, box) {
                      final half = box.maxWidth / 2;
                      final len = half * (pts.abs() / scale).clamp(0.0, 1.0);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: p.track,
                                borderRadius: R.rPill,
                              ),
                            ),
                          ),
                          Positioned(
                            left: pts < 0 ? half - len : half,
                            width: len,
                            top: 0,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: lowers
                                    ? p.on(C.alert)
                                    : p.on(C.recovery),
                                borderRadius: R.rPill,
                              ),
                            ),
                          ),
                          Positioned(
                            left: half,
                            width: 1,
                            top: 0,
                            bottom: 0,
                            child: ColoredBox(color: p.ink3),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _rowOld(BuildContext c, P p, Map<String, dynamic> r, double wsum) {
    final l = AppLocalizations.of(c);
    final key = r['label']?.toString() ?? '';
    final raw = (r['weight'] as num?)?.toDouble();
    final contribution = (r['weighted_contribution'] as num?);
    final used = r['used'] == true;
    final pastMdc = r['past_mdc'] == true;
    // No weight, or an input that carried none, means no percentage — `?? 0`
    // printed a confident "0% weight" for a number nobody reported.
    final share = !used || raw == null || wsum <= 0 ? null : raw / wsum;

    // Plain words, coloured: better than your usual, about usual, or worse.
    final (String word, Color col) = !used
        ? ('Not measured', C.n500)
        : contribution == null || !pastMdc
        ? ('About usual', C.n500)
        : contribution >= 0
        ? ('Better than usual', C.green)
        : ('Worse than usual', C.orange);
    final metric = switch (key) {
      'hrv' => 'hrv',
      'rhr' => 'resting_hr',
      'resp' => 'resp_rate',
      'temp' => 'skin_temp',
      'sleep' => 'sleep',
      _ => null,
    };
    return Pressable(
      onTap: metric == null
          ? null
          : () => go(c, MetricDetail.at(metric, widget.day)),
      semanticLabel:
          '${key == 'rhr' ? 'Resting HR · asleep' : driverLabel(key, l)}, $word',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    key == 'rhr' ? 'Resting HR · asleep' : driverLabel(key, l),
                    style: F.body.copyWith(color: p.ink),
                  ),
                  if (key == 'rhr')
                    Text(
                      'Lowest 30-minute average while asleep',
                      style: F.body.copyWith(color: p.ink),
                    ),
                  if (share != null)
                    Text(
                      '${(share * 100).round()}% of the score',
                      style: F.over.copyWith(color: p.ink3),
                    )
                  else if (!used && key == 'hrv' && _d?.hrvNote != null)
                    Text(_d!.hrvNote!, style: F.cap.copyWith(color: p.ink2)),
                ],
              ),
            ),
            const SizedBox(width: S.x3),
            Text(
              word,
              style: F.cap.copyWith(
                color: col == C.n500 ? p.ink2 : p.on(col),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (metric != null) ...[
              const SizedBox(width: S.x2),
              Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
            ],
          ],
        ),
      ),
    );
  }
}

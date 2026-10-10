// DAY STRAIN — when the day's effort actually happened.
//
// `getDayStrain` was fully implemented and called by nothing. Everything drawn
// here was already computed and persisted: `series.strain_curve` (one point per
// WAKE MINUTE), the zone minutes, and `max_hr_used` — the ceiling the pipeline
// actually integrated against, printed rather than laundered into the score.
//
// The CURVE leads. The 0–21 is a summary of the curve, not the other way round:
// two days can land on the same number with completely different shapes, and
// the shape is the thing you can act on.
//
// What this screen deliberately does NOT draw:
//   * CTL/ATL/TSB. That is a fortnight of history and it already has a card one
//     tap away on the Workout tab. A day screen repeating it is noise.
//   * the resting heart rate TRIMP was anchored on. `getDayHeart`'s
//     `resting_hr` is now that same nocturnal number (`scalars.rhr` no longer
//     falls back to daytime HR), so it COULD be printed — it just does not earn
//     a line on a day screen whose subject is the curve. Naming the input in a
//     sentence is enough.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart' show whyFromNote;
import '../screens/home_screen.dart' show pointsOf, repoOf, monthName;
import '../screens/metric_detail.dart' show dayNavRow, detailScaffold;
import '../ui2.dart';
import 'zones.dart' show ZonesDetail;

/// Below this the day is not comparable to a full one and the screen says so.
/// Wear coverage is a percentage of the whole day, so a normal night off the
/// wrist already costs ~30 points — this is "most of the waking day", not
/// "nearly all of it".
const _lowCoveragePct = 60;

/// The trace, the score, and everything needed to say what the score is made
/// of. Every field is nullable: a day the band never saw renders its absence.
class DayStrainData {
  /// The local day the curve actually came from. `getDayStrain` falls back to
  /// the last settled bundle while today is still deriving, so this is read off
  /// the curve's own timestamps rather than off the label we asked for.
  final DateTime? day;

  /// One slot per minute of [day], null where nothing was recorded. A compacted
  /// curve under a 00:00–24:00 axis draws a sync gap as though it were measured.
  final List<double?> curve;

  final double? strain;

  /// Five zone minutes, or null when the day banked no split.
  final List<int>? zoneMin;

  /// The HR ceiling the pipeline integrated against — `max_hr_used`, the same
  /// number the maths saw.
  final num? maxHrUsed;

  /// TS-04 — which anchors THIS day's zone bars were binned on: 'karvonen'
  /// (observed ceiling + measured resting HR), 'observed' (measured ceiling
  /// only) or 'tanaka' (the age estimate). The bar's footnote states what the
  /// bar IS, rather than what it usually is.
  final String? zoneSource;
  final num? zoneMaxHr;

  final int? peakHr, wornMin, coveragePct;

  /// Resting heart rate from the night before: strain's other anchor.
  final int? rhr;

  /// Every day with a strain, oldest first, for the day stepper.
  final List<String> days;

  /// WHY the day has no strain, as the bundle said it — never a sentence
  /// written on this screen. Null means nothing came back with the absence, and
  /// the screen then says exactly that.
  final String? note;

  const DayStrainData({
    this.day,
    this.curve = const [],
    this.strain,
    this.zoneMin,
    this.maxHrUsed,
    this.zoneSource,
    this.zoneMaxHr,
    this.peakHr,
    this.wornMin,
    this.coveragePct,
    this.note,
    this.rhr,
    this.days = const [],
  });

  bool get hasCurve => curve.any((v) => v != null);

  static Future<DayStrainData> load(
    LocalRepository repo, {
    String? want,
  }) async {
    final asked = want ?? todayLabel();
    var days = const <String>[];
    try {
      days = {
        for (final p in pointsOf(await repo.getChart('strain')))
          dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)),
        todayLabel(),
        // NEWEST FIRST: the contract `DayNav` walks (its Previous button takes
        // index + 1). Oldest-first sent Previous to tomorrow and Next to
        // yesterday (B86-01).
      }.toList()..sort((a, b) => b.compareTo(a));
    } catch (_) {
      days = const [];
    }
    final s = await repo.getDayStrain(asked);
    if (s.isEmpty) {
      return DayStrainData(day: DateTime.tryParse(asked), days: days);
    }

    final pts = <(int, double)>[
      for (final e in (s['curve'] as List? ?? const []))
        if (e is Map && e['t'] is num && e['v'] is num)
          ((e['t'] as num).toInt(), (e['v'] as num).toDouble()),
    ];

    DateTime? day;
    var grid = const <double?>[];
    if (pts.isNotEmpty) {
      final first = DateTime.fromMillisecondsSinceEpoch(pts.first.$1 * 1000);
      day = DateTime(first.year, first.month, first.day);
      final out = List<double?>.filled(1440, null);
      for (final p in pts) {
        final stamp = DateTime.fromMillisecondsSinceEpoch(p.$1 * 1000);
        if (dayLabelOf(stamp) == dayLabelOf(day)) {
          out[stamp.hour * 60 + stamp.minute] = p.$2;
        }
      }
      grid = out;
    }

    // Wear for THE DAY THE CURVE CAME FROM, not the day we asked for — both
    // reads fall back the same way, so asking for the resolved label is what
    // keeps the coverage figure and the trace describing one day.
    //
    // Read even when there is NO curve, which it did not used to be. Whether
    // the band saw the day is what decides if "wear the band through the day"
    // is an instruction or an insult, and a day with no strain is exactly the
    // day that question gets asked on.
    Map<String, dynamic> wear = const {};
    try {
      wear = await repo.getDayWear(day == null ? asked : dayLabelOf(day));
    } catch (_) {
      wear = const {};
    }

    final z = s['zones'];
    final zoneMin =
        z is Map &&
            [for (var i = 1; i <= 5; i++) z['z$i']].every((v) => v is num)
        ? [for (var i = 1; i <= 5; i++) (z['z$i'] as num).toInt()]
        : null;

    final hr = s['hr'];
    return DayStrainData(
      day: day,
      curve: grid,
      strain: (s['strain'] as num?)?.toDouble(),
      zoneMin: zoneMin,
      maxHrUsed: s['max_hr_used'] as num?,
      zoneSource: s['zone_source'] as String?,
      zoneMaxHr: s['zone_max_hr'] as num?,
      peakHr: hr is Map ? (hr['max'] as num?)?.toInt() : null,
      wornMin: (wear['worn_min'] as num?)?.toInt(),
      coveragePct: (wear['coverage_pct'] as num?)?.toInt(),
      // The headline absence's reason, at the top level of the payload — the
      // same string as `absent.strain`.
      note: s['note'] as String?,
      rhr: (s['rhr'] as num?)?.toInt(),
      days: days,
    );
  }
}

class DayStrainDetail extends StatefulWidget {
  /// Preloaded, for goldens. Null means read the repo on open.
  final DayStrainData? data;

  /// The day to open (`yyyy-MM-dd`); null is today.
  final String? day;
  final bool embedded;
  const DayStrainDetail({
    super.key,
    this.data,
    this.day,
    this.embedded = false,
  });

  @override
  State<DayStrainDetail> createState() => _DayStrainDetailState();
}

class _DayStrainDetailState extends State<DayStrainDetail> with RevisionReload {
  DayStrainData? _d;
  bool _loading = true;
  bool _failed = false;
  late String? _day = widget.day;

  /// The minute under the finger on the day's curve, or null.
  int? _pick;

  void _goDay(String day) {
    setState(() {
      _day = day;
      _pick = null;
      _loading = true;
    });
    _load();
  }

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
  void reload() => _load();

  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final token = beginRead(#day);
    try {
      final d = await DayStrainData.load(repo, want: _day);
      if (stillNewest(#day, token))
        setState(() => (_d = d, _loading = false, _failed = false));
    } catch (_) {
      if (stillNewest(#day, token))
        setState(() => (_loading = false, _failed = true));
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final d = _d ?? const DayStrainData();
    final day = d.day;
    // The date the drawn day IS. `getDayStrain` serves the last settled bundle
    // while today is still deriving, and a screen headed "Today" over
    // yesterday's trace is the whole reason this is read off the curve.
    final sub = day == null
        ? ''
        : dayLabelOf(day) == todayLabel()
        ? (l?.dayStrainToday ?? 'TODAY')
        : '${monthName(day.month, l)} ${day.day}'.toUpperCase();

    return detailScaffold(
      c,
      l?.dayStrainTitle ?? 'Day strain',
      [
        if (!widget.embedded)
          ...dayNavRow(
            _day ?? (day == null ? null : dayLabelOf(day)),
            d.days,
            _goDay,
          ),
        if (widget.embedded && day != null && dayLabelOf(day) != todayLabel())
          Text(sub),
        if (_loading && _d == null) ...[
          const SizedBox(height: S.x8),
          const Center(child: CircularProgressIndicator()),
        ] else if (_failed)
          StatusCard(
            'Strain could not load',
            'Your saved days are intact.',
            fix: 'Retry',
            onFix: _load,
          )
        else ...[
          ..._hero(p, d),
          ..._trace(p, l, d),
          ..._zones(p, l, d),
          const SizedBox(height: S.x4),
          _how(p, l, d),
        ],
      ],
      embedded: widget.embedded,
      sub: d.days.length < 2 ? sub : '',
    );
  }

  bool _showHow = false;

  /// WHOOP-style effort words for the 0–21 scale.
  static String _band(double s) => s >= 18
      ? 'All out'
      : s >= 14
      ? 'High'
      : s >= 10
      ? 'Moderate'
      : 'Light';

  // ── the number first: big, coloured, with a bar out of 21 ─────────────────
  List<Widget> _hero(P p, DayStrainData d) {
    final s = d.strain;
    if (s == null) return const [];
    return [
      Surface(
        pad: const EdgeInsets.all(S.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    s.toStringAsFixed(1),
                    style: F.n48.copyWith(color: p.on(C.strain)),
                  ),
                  const SizedBox(width: S.x2),
                  Text(_band(s), style: F.head.copyWith(color: p.ink)),
                ],
              ),
            ),
            const SizedBox(height: S.x3),
            ClipRRect(
              borderRadius: R.rPill,
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Positioned.fill(child: ColoredBox(color: p.track)),
                    FractionallySizedBox(
                      widthFactor: (s / 21).clamp(0.0, 1.0),
                      child: ColoredBox(
                        color: p.on(C.strain),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: S.x3),
            Text(
              [
                'of 21',
                if (d.peakHr != null) 'peak ${d.peakHr} bpm',
                if (d.wornMin != null)
                  'worn ${d.wornMin! ~/ 60}h ${d.wornMin! % 60}m',
              ].join(' · '),
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
        ),
      ),
      const SizedBox(height: S.x3),
    ];
  }

  // ── the curve, and only then the number ────────────────────────────────────
  List<Widget> _trace(P p, AppLocalizations? l, DayStrainData d) {
    if (!d.hasCurve) {
      // THE BUNDLE'S REASON, or none. This card used to state one — "it needs a
      // resting heart rate from a scored night and a day the band was on your
      // wrist" — and it printed that on a day with a scored night (RHR 56.8)
      // and 89 % wear, because the sentence was written here rather than
      // handed over. A cause the screen did not receive is a guess.
      final why = whyFromNote(d.note, unit: 'days');
      // And "wear the band" is only an instruction on a day the band did not
      // see. Offered on a day it was on the wrist all along it is worse than
      // no button, because the user spends trust doing it.
      final saw = (d.wornMin ?? 0) > 0 || (d.coveragePct ?? 0) > 0;
      // A day CAN carry a strain with no trace behind it: `backfillStrainScale`
      // rescales the stored headline onto the current scale and DROPS the
      // per-minute curve, which cannot be rescaled with it. Measured on
      // whoop-4, that is 6 of 17 days — and on every one of them this card said
      // "this day produced no strain" directly above a day that produced 10.8.
      // The absence is the TRACE, so that is what the card is allowed to name;
      // why the trace is not stored is not something this screen was told.
      final s = d.strain;
      return [
        StatusCard(
          s == null
              ? (l?.dayStrainNoTraceTitle ?? 'No strain trace for this day')
              : (l?.dayStrainNoMinuteTraceTitle ??
                    'No minute-by-minute trace for this day'),
          s == null
              ? why ??
                    (l?.dayStrainNoReasonBody ??
                        'Nothing recorded says why this day produced no strain.')
              : (l?.dayStrainScoredNoTraceBody(s.toStringAsFixed(1)) ??
                    'The day strain is ${s.toStringAsFixed(1)}. The waking minutes '
                        'it was built from are not stored for this day.'),
          fix: (s == null && !saw)
              ? (l?.dayStrainWearBandFix ?? 'Wear the band through the day')
              : '',
          icon: LucideIcons.trendingUp,
        ),
      ];
    }
    final n = d.curve.length;
    final denominator = n > 1 ? n - 1 : 1;
    final last = latestDaySlot(d.day == null ? null : dayLabelOf(d.day!), n);
    final curve = [for (var i = 0; i < n; i++) i <= last ? d.curve[i] : null];
    final axis = AxisSpec.of(curve.whereType<double>(), floor: 0);
    final drawn = curve.where((v) => v != null).length;
    final pick = _pick?.clamp(0, last);
    String says(int i) {
      final v = curve[i];
      final hh = (i ~/ 60).toString().padLeft(2, '0');
      final mm = (i % 60).toString().padLeft(2, '0');
      return '$hh:$mm · ${v == null ? 'not recorded' : v.toStringAsFixed(1)}';
    }

    int at(double f) => (f * (n - 1)).round().clamp(0, last);
    return [
      Surface(
        child: Column(
          children: [
            ChartFrame(
              title: 'Through the day',
              unit: '0–21',
              height: 170,
              yAxis: axis,
              xLabels: const ['00:00', '12:00', '24:00'],
              series: curve,
              readout: pick == null ? null : says(pick),
              footnote: 'From $drawn recorded minutes.',
              child: Scrubber(
                value: pick == null ? null : pick / denominator,
                maxValue: last / denominator,
                step: 1 / 48,
                label: 'Strain through the day',
                describe: (f) => says(at(f)),
                onChanged: (f) => setState(() => _pick = at(f)),
                child: CustomPaint(
                  size: Size.infinite,
                  painter: LineChart(
                    curve,
                    p.on(C.strain),
                    axis: axis,
                    t: animate(context, 1),
                    cursor: pick,
                    cursorInk: p.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (d.coveragePct != null && d.coveragePct! < _lowCoveragePct)
        Padding(
          padding: const EdgeInsets.only(top: S.x4),
          child: StatusCard(
            l?.dayStrainLowCoverageTitle(d.coveragePct!) ??
                'The band saw ${d.coveragePct}% of this day',
            l?.dayStrainLowCoverageBody ??
                'Strain is a total over the minutes that were recorded, so a '
                    'partly-worn day reads lower than a full one and the two are '
                    'not comparable.',
            icon: LucideIcons.watch,
          ),
        ),
    ];
  }

  // ── where the effort sat ───────────────────────────────────────────────────
  List<Widget> _zones(P p, AppLocalizations? l, DayStrainData d) {
    final z = d.zoneMin;
    if (z == null) return const [];
    final total = z.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return const [];
    return [
      Section(
        l?.dayStrainTimeInZonesSection ?? 'Time in zones',
        Surface(
          child: Column(
            children: [
              for (var i = 4; i >= 0; i--) ...[
                if (i < 4) const SizedBox(height: S.x3),
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        'Z${i + 1}',
                        style: F.cap.copyWith(color: p.ink2),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: R.rPill,
                        child: SizedBox(
                          height: 10,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: ColoredBox(color: p.track),
                              ),
                              FractionallySizedBox(
                                widthFactor: (z[i] / total).clamp(0.0, 1.0),
                                child: ColoredBox(
                                  color: ZoneBar.cols(p)[i],
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${z[i]} min',
                        textAlign: TextAlign.right,
                        style: F.cap.copyWith(color: p.ink),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        // Progressive disclosure: this day screen gains a LINK, not a row. The
        // ceiling, the edges in bpm and the 28-day distribution are all one tap
        // behind it.
        action: l?.dayStrainHowSet ?? 'How these are set',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ZonesDetail())),
      ),
    ];
  }

  // ── the inputs, named ──────────────────────────────────────────────────────
  /// The method, folded away until asked for.
  Widget _how(P p, AppLocalizations? l, DayStrainData d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (_showHow) ...[const SizedBox(height: S.x2), _inputs(p, l, d)],
      ],
    );
  }

  /// Three plain lines. The method (Banister TRIMP over waking heart rate,
  /// scaled to 0–21) is the same; this only says it in words.
  Widget _inputs(P p, AppLocalizations? l, DayStrainData d) {
    final max = d.maxHrUsed?.round();
    final rhr = d.rhr;
    final anchors = [
      rhr == null
          ? 'your resting rate'
          : 'your resting rate ($rhr bpm last night)',
      max == null ? 'your max' : 'the ceiling used for this day ($max bpm)',
    ];
    final lines = [
      'Strain is how hard your heart worked while you were awake, from 0 to 21.',
      'It compares your heart rate with ${anchors[0]} and ${anchors[1]}.',
      'Time at a high heart rate adds the most, and it gets harder to climb '
          'the higher it already is.',
    ];
    return Surface(
      elevation: 0,
      color: p.card2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x2),
            Text(lines[i], style: F.cap.copyWith(color: p.ink2, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

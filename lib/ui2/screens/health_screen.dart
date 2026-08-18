// HEALTH — observation-oriented. "What is happening, what is changing, is
// anything unusual?"
//
// Rows, not a wall of cards. A card is a claim that something deserves your
// attention; forty of them side by side is a claim about nothing. Overview is
// a list you scan, Trends is where change lives, Vitals is what the sensor
// measured, and Labs is what a laboratory measured — the only numbers in this
// app that are absolute.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/lab_catalogue.dart';
import '../../data/local_repository.dart';
import '../../models/metric.dart';
import '../profile/profile.dart';
import '../ui2.dart';
import 'circadian_detail.dart';
import 'home_screen.dart';
import 'investigate.dart';
import 'metric_detail.dart';

class HealthData {
  final Map<String, dynamic> today, insights, profile;

  /// Timestamped. The x axis and the "how old is this number" line are both
  /// read off the points' own dates — `metric_series` has one row per DERIVED
  /// day, so the newest stored point can be a week old.
  final Map<String, List<ChartPoint>> charts;

  /// Derived days INSIDE THE LAST 30 CALENDAR DAYS — see [load].
  final int daysWithData;
  final Metric need;

  /// Non-null when the cross-day rollup was withheld — see [staleInsightsCard].
  final Map<String, dynamic>? insightsStale;

  const HealthData({
    this.today = const {},
    this.insights = const {},
    this.profile = const {},
    this.charts = const {},
    this.daysWithData = 0,
    this.need = Metric.empty,
    this.insightsStale,
  });

  /// The stored points for [key].
  List<ChartPoint> points(String key) => charts[key] ?? const [];

  /// [days] slots ending today, `null` where nothing was derived — the shape
  /// every painter in this app takes.
  List<double?> spark(String key, int days) => denseDays(points(key), days);

  Metric daily(String k) {
    final d = today['daily'];
    return metricOf(d is Map ? d[k] : null);
  }

  /// Every one of these is a real envelope from the pipeline, read in one
  /// place so Overview cannot disagree with itself. Trends is a different
  /// question — it plots what is STORED, and dates its hero when the newest
  /// stored point is not today's.
  Metric get hrv {
    final b = today['hrv'];
    final rmssd = b is Map ? b['rmssd'] as num? : null;
    if (rmssd == null || b is! Map) return Metric.empty;
    return Metric.parse(
        {...b.cast<String, dynamic>(), 'value': rmssd, 'unit': 'ms'});
  }

  Metric get sleepMin {
    final b = today['sleep'];
    return metricOf(b is Map ? b['duration_min'] : null);
  }

  Metric get stress => metricOf(today['stress']);
  Metric get resp => metricOf(today['resp']);

  static Future<HealthData> load(LocalRepository repo) async {
    final today = await repo.getToday();
    final cd = await repo.getInsights();
    final profile = await repo.getProfile();
    final days = await repo.availableDays();

    final charts = <String, List<ChartPoint>>{};
    for (final k in const [
      'resting_hr',
      'hrv',
      'sleep',
      'stress',
      'resp_rate',
    ]) {
      charts[k] = pointsOf(await repo.getChart(k));
    }

    final coach = cd['sleep_coach'];
    final needEnv = coach is Map ? coach['need'] : null;
    final needSec = envValue(needEnv)?['need_sec'] as num?;

    // The last 30 CALENDAR days, not the newest 30 rows. `availableDays()` is
    // unbounded — every derived day since install — so `daysWithData` was the
    // whole history and `.clamp(0, 30)` painted "30 of 30" for anyone past
    // their first month, however many days they had actually missed.
    // `DateTime(y, m, d - 29)` and not `subtract(Duration(days: 29))`: the
    // duration form lands at 23:00 the day before across a DST boundary.
    final n = DateTime.now();
    final from = dayLabelOf(DateTime(n.year, n.month, n.day - 29));

    return HealthData(
      today: today,
      insights: cd,
      profile: profile,
      charts: charts,
      daysWithData: days.where((d) => d.compareTo(from) >= 0).length,
      need: envMetric(needEnv, needSec == null ? null : needSec / 60,
          unit: 'min'),
      insightsStale: staleReasonOf(cd),
    );
  }
}

class VitalsData {
  /// The day these four blocks describe. When today has no derived record the
  /// loader falls back to the newest one there is, which is routinely days ago
  /// — and every row was captioned "Today" regardless.
  final String? day;

  /// Every derived day, newest first — what [DayNav] steers over.
  final List<String> days;

  final Map<String, dynamic> timeline, lungs, wear, hrv;
  const VitalsData({
    this.day,
    this.days = const [],
    this.timeline = const {},
    this.lungs = const {},
    this.wear = const {},
    this.hrv = const {},
  });

  static Future<VitalsData> load(LocalRepository repo, {String? want}) async {
    final today = await repo.getToday();
    final days = await repo.availableDays();
    final day = pickDay(
        days, want, (today['status'] as Map?)?['today_day']?.toString());
    if (day == null) return VitalsData(days: days);
    final timeline = await repo.getDayTimeline(day);
    return VitalsData(
      // The repository stamps the bundle it actually served; prefer it over the
      // day we asked for, which is what its own comment says to do.
      day: timeline['date']?.toString() ?? day,
      days: days,
      timeline: timeline,
      lungs: await repo.getDayLungs(day),
      wear: await repo.getDayWear(day),
      hrv: await repo.getDayHrv(day),
    );
  }
}

/// Whole calendar days between a `'YYYY-MM-DD'` day id and today, or null when
/// there is no day. Zero or less means the day IS today.
int? _behind(String? dayId) {
  final d = dayId == null ? null : DateTime.tryParse(dayId);
  return d == null ? null : calendarDaysBetween(d, DateTime.now());
}

class LabsData {
  final List<Map<String, dynamic>> results;
  final List<LabMarker> markers;
  const LabsData({this.results = const [], this.markers = const []});

  static Future<LabsData> load() async {
    final rows = await LocalDb.labResults();
    final defs = await LocalDb.labMarkerDefs();
    return LabsData(
      results: rows,
      markers: [
        ...kLabMarkers,
        for (final d in defs)
          if (!kLabMarkersByKey.containsKey(d['key']))
            LabMarker(
              key: d['key'].toString(),
              label: (d['label'] ?? d['key']).toString(),
              unit: (d['unit'] ?? '').toString(),
              category: LabCategory.blood,
              decimals: (d['decimals'] as num?)?.toInt() ?? 1,
              ranges: [
                if (d['ref_low'] is num && d['ref_high'] is num)
                  LabRefRange(
                      low: (d['ref_low'] as num).toDouble(),
                      high: (d['ref_high'] as num).toDouble()),
              ],
              custom: true,
            ),
      ],
    );
  }
}

// ═══════════════════ the catalogue ═══════════════════
//
// EXPLORE. The app persists 39 daily series and carries 25 written metric
// specs — title, unit, colour, icon, method, citation — and until this tab
// existed `MetricDetail` was constructed with SEVEN keys anywhere in the tree.
// Sixteen finished screens had no navigation edge at all. That is a routing
// gap, not a content gap, and this is the routing.
//
// It is an index, not a dashboard: nothing here computes, nothing here is a
// number about you. It says what this app can tell you, groups it the way a
// person would look for it, and says for each one how many days it actually
// has — which is the only honest answer to "is there anything in there".

/// One catalogue entry: the [MetricSpec] key (which is what [MetricDetail]
/// takes), the `metric_series` key its history is stored under, and the single
/// line that says what it answers.
///
/// Icon, colour and title are NOT here — they come off the spec. A second copy
/// is how two screens end up disagreeing about what a metric is called.
class _CatRow {
  final String key, series, blurb;
  const _CatRow(this.key, this.series, this.blurb);
}

class _Cat {
  final String title;
  final List<_CatRow> rows;
  const _Cat(this.title, this.rows);
}

/// The families, in the order a person looks for them.
///
/// What is deliberately NOT here:
/// - SpO2, ODI and anything apnea-shaped. Refused outright — a capability this
///   app does not produce has no entry, no card and no key, and an index that
///   listed them to explain their absence would be the exact thing the
///   absent-forever rule forbids.
/// - Cycle. It is a Wellness tab with its own door and its own on/off switch;
///   a second entrance from Health would be a duplicate route, not a feature.
/// - `rmssd_whole`, `stress_si`, `brv_slope`. Real numbers, but single-night
///   with no series ever. They had written specs for a while and nothing could
///   open them; the specs are gone now, so there is nothing to route to either.
///   `stress` and `brv` below are the charted forms of two of the three.
/// - Body clock, zones, Nerd stats. Each already has a door at the same depth
///   as this one; adding a second is navigation debt.
const _catalogue = <_Cat>[
  _Cat('Heart & rhythm', [
    _CatRow('resting_hr', 'rhr', 'The lowest sustained rate of the night'),
    _CatRow('hrv', 'rmssd', 'RMSSD over the cleanest window of sleep'),
    _CatRow('hrv_cv', 'hrv_cv', 'How much that swings from night to night'),
    _CatRow('lf_hf', 'lf_hf', 'Where beat-timing power sits across frequencies'),
    _CatRow('dip', 'dip_pct', 'How far your heart rate falls while you sleep'),
    _CatRow('hrr', 'hrr_bpm', 'How fast it falls in the minute after a bout'),
  ]),
  _Cat('Sleep', [
    _CatRow('sleep', 'tst_min', 'Time asleep, from motion and beat timing'),
    _CatRow('efficiency', 'efficiency', 'Asleep as a share of time in bed'),
    _CatRow('deep', 'deep_min', 'Heart-rate flatness inside NREM'),
    _CatRow('rem', 'rem_min', 'Staged from beat variability and movement'),
    _CatRow('nap_min', 'nap_min', 'Sleep detected outside the main night'),
  ]),
  _Cat('Breathing', [
    _CatRow('resp_rate', 'resp_rate', 'Breaths per minute, recovered from beat timing'),
    _CatRow('brv', 'brv_cv', 'How much that rate varies across the night'),
  ]),
  _Cat('Movement & load', [
    _CatRow('steps', 'steps', 'Counted by a pedometer, never modelled'),
    _CatRow('active_min', 'active_min', 'Minutes of movement volume, not locomotion'),
    _CatRow('calories', 'calories', 'Active energy from heart rate and your profile'),
    _CatRow('strain', 'strain', 'Cardiovascular load over the day, on 0–21'),
    _CatRow('trimp', 'trimp', 'Time in each zone, weighted by its cost'),
  ]),
  _Cat('Body & wear', [
    _CatRow('skin_temp', 'skin_temp_z', 'Distance from your own recent nights'),
    _CatRow('wear', 'worn_min', 'Minutes with a band record present'),
  ]),
];

class ExploreData {
  /// Non-null `metric_series` rows per key — used ONLY as has / hasn't.
  ///
  /// The number itself is never rendered per row (see `_family`): as a value
  /// beside a metric it reads as a score, and it collapses "rare", "new key"
  /// and "substrate pruned" into one figure. What it is good for is the split —
  /// which rows have history, which are named in the empty card, and the
  /// "N of M measures" header, where the aggregate is honest because it is
  /// about the DEVICE and not about any one metric.
  final Map<String, int> counts;
  const ExploreData({this.counts = const {}});

  static Future<ExploreData> load() async => ExploreData(
        counts: await LocalDb.metricSeriesCounts([
          for (final f in _catalogue)
            for (final r in f.rows) r.series,
        ]),
      );
}

class HealthScreen extends StatefulWidget {
  final HealthData? data;
  final VitalsData? vitals;
  final LabsData? labs;
  final ExploreData? explore;

  /// Which sub-tab to open on. Goldens use it; production always starts at 0.
  final int tab;

  const HealthScreen(
      {super.key,
      this.data,
      this.vitals,
      this.labs,
      this.explore,
      this.tab = 0});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  // EXPLORE SITS SECOND, not last. Five chips do not fit a 390 pt frame at 1×:
  // the fifth is clipped by the edge, and a half-visible chip is exactly the
  // discoverability failure this tab exists to fix. Labs takes the clip instead
  // — it is the manual-entry tab, the one a user goes looking for on purpose,
  // and the only one here that holds numbers this app did not measure.
  static const _tabs = ['Overview', 'Explore', 'Trends', 'Vitals', 'Labs'];
  late int _tab = widget.tab;

  HealthData? _d;
  VitalsData? _v;
  LabsData? _l;
  ExploreData? _e;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    _v = widget.vitals;
    _l = widget.labs;
    _e = widget.explore;
    if (widget.data != null) {
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
      final d = await HealthData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// A tab's read THREW. `_v`/`_l` stay null on that path and null renders the
  /// spinner, so swallowing the error left the tab spinning silently for as
  /// long as the user stayed on it — there was no absent state on that path at
  /// all, whatever the old comment here said.
  bool _vFailed = false, _lFailed = false, _eFailed = false;

  /// The day the Vitals tab is showing, once the user has steered off the
  /// default. Null means "whatever the loader resolves", which is today.
  String? _vDay;

  Future<void> _loadVitals({bool force = false}) async {
    final repo = repoOf(context);
    if (repo == null || (_v != null && !force)) return;
    try {
      final v = await VitalsData.load(repo, want: _vDay);
      if (mounted) setState(() => (_v = v, _vFailed = false));
    } catch (_) {
      if (mounted) setState(() => _vFailed = true);
    }
  }

  void _goVitalsDay(String day) {
    setState(() => _vDay = day);
    _loadVitals(force: true);
  }

  Future<void> _loadLabs() async {
    if (_l != null) return;
    try {
      final l = await LabsData.load();
      if (mounted) setState(() => (_l = l, _lFailed = false));
    } catch (_) {
      if (mounted) setState(() => _lFailed = true);
    }
  }

  /// The one card both failed reads render. Not "nothing logged yet" — a read
  /// that went wrong and an empty table are different states.
  StatusCard _readFailed(String what, VoidCallback retry) => StatusCard(
        'Could not read your $what',
        'The stored rows failed to load. Nothing was deleted — this is a read '
            'that went wrong.',
        fix: 'Try again',
        icon: LucideIcons.databaseZap,
        onFix: retry,
      );

  Future<void> _loadExplore() async {
    if (_e != null) return;
    try {
      final e = await ExploreData.load();
      if (mounted) setState(() => (_e = e, _eFailed = false));
    } catch (_) {
      if (mounted) setState(() => _eFailed = true);
    }
  }

  void _select(int i) {
    setState(() => _tab = i);
    if (i == 1) _loadExplore();
    if (i == 3) _loadVitals();
    if (i == 4) _loadLabs();
  }

  @override
  Widget build(BuildContext c) {
    final d = _d ?? const HealthData();
    return ListView(padding: pad, children: [
      const ScreenTitle('Health'),
      SubTabs(_tabs, _tab, _select, color: C.blue),
      const SizedBox(height: S.x5),
      if (_loading && _d == null)
        const Padding(
          padding: EdgeInsets.only(top: S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        switch (_tab) {
          0 => _overview(c, d),
          1 => _explore(c),
          2 => _trends(c, d),
          3 => _vitals(c, d),
          _ => _labs(c),
        },
    ]);
  }

  // ─────────────── OVERVIEW ───────────────
  Widget _overview(BuildContext c, HealthData d) {
    final p = P.of(c);
    final rows = <Widget>[];
    final gaps = <Widget>[];

    void row(Metric m, IconData icon, Color col, String name, String sub,
        String value, String unit, List<double?> spark, String metricKey,
        {String? whyAbsent}) {
      if (m.isEmpty) {
        final s = StatusCard.forMetric('No ${name.toLowerCase()}', m,
            why: whyAbsent ?? '');
        if (s != null) gaps.add(s);
        return;
      }
      rows.add(MetricRow(icon, col, name, value,
          sub: sub,
          unit: unit,
          spark: spark,
          onTap: () => go(c, MetricDetail(metricKey))));
    }

    // Five of these rows come off the overnight block, and `getToday` holds
    // that block over until today's settles. "Last night" / "Overnight" were
    // fixed literals, so a days-old night was stated as last night's — while
    // the Trends tab one tap away correctly said "as of 4 days ago" about the
    // same numbers.
    final night = heldOverNightOf(d.today);
    String ofNight(String s) => night == null ? s : '$s · ${prettyDay(night)}';

    final sleepMin = d.sleepMin;

    final rhr = d.daily('resting_hr');
    row(rhr, LucideIcons.heart, C.red, 'Resting heart rate', ofNight('Overnight'),
        rhr.value == null ? '' : '${rhr.value!.round()}', 'bpm',
        d.spark('resting_hr', 24), 'resting_hr',
        // Sleep duration and nocturnal RHR are gated separately, so "no night
        // was scored" is often the wrong reason and contradicts the Sleep row
        // sitting two lines down. Only the branch this screen can SEE is
        // stated — the other named a beat-quality gate it never read.
        whyAbsent: sleepMin.isEmpty
            ? 'Read from sleep, and no night was scored.'
            : '');

    final hrvMetric = d.hrv;
    row(hrvMetric, LucideIcons.activity, C.green, 'HRV',
        ofNight('RMSSD, asleep'),
        hrvMetric.value == null ? '' : '${hrvMetric.value!.round()}', 'ms',
        d.spark('hrv', 24), 'hrv',
        // Blaming signal quality unconditionally told a day-one user their
        // sensor produced dirty data on a night that never happened.
        whyAbsent: sleepMin.isEmpty
            ? 'Read only from sleep, and no night was scored.'
            : '');

    row(sleepMin, LucideIcons.moon, C.blue, 'Sleep',
        night == null ? 'Last night' : prettyDay(night),
        hm(sleepMin.value), '', d.spark('sleep', 24), 'sleep',
        whyAbsent: 'No sleep period long enough to score was recorded.');

    final stressBlock = d.today['stress'];
    final stressScore =
        stressBlock is Map ? (stressBlock['score'] as num?) : null;
    row(
        d.stress,
        LucideIcons.brain,
        C.purple,
        'Stress',
        ofNight((stressBlock is Map ? stressBlock['level']?.toString() : null) ??
            'Stress'),
        stressScore == null ? '' : '${stressScore.round()}',
        // 0–100, and the scale has to be on the row. Wellness has always shown
        // it for the same number.
        '/100',
        d.spark('stress', 24),
        'stress',
        // Was 'No resting stretch long enough last night.' — one of several
        // gates stress abstains on, asserted for all of them.
        whyAbsent: sleepMin.isEmpty
            ? 'Read from the night, and no night was scored.'
            : '');

    final respMetric = d.resp;
    row(respMetric, LucideIcons.wind, C.teal, 'Respiratory rate',
        ofNight('Asleep'),
        respMetric.value == null ? '' : respMetric.value!.toStringAsFixed(1),
        'br/min',
        d.spark('resp_rate', 24), 'resp_rate',
        // THE ESTIMATOR'S OWN REASON when it left one, not a guess written
        // here. `respiration.rsa` records which gate it failed — too few beats,
        // artifact fraction over the gate, no stable HF peak, or a peak that
        // moved across spectral resolutions — and the repository now carries
        // that note through. This screen guessed "too noisy" for all four,
        // which was right about a quarter of the time.
        whyAbsent: respMetric.note?.isNotEmpty == true
            ? respMetric.note!
            : (sleepMin.isEmpty
                ? 'Read only from sleep, and no night was scored.'
                : 'No reading from last night.'));

    final illness = d.today['illness'];
    final state = illness is Map ? illness['state']?.toString() : null;
    // The CUSUM watch runs on NOCTURNAL RESTING HEART RATE ALONE. The copy here
    // used to name skin temperature as a second firing signal; the detector has
    // never been given a temperature series. `z` is its own standardised
    // deviation, so the sentence can say how far out the night sat.
    final illnessZ = illness is Map ? (illness['z'] as num?) : null;
    // The payload carries the night it is about. It is one entry per DERIVED
    // day, so after a gap "Last night" named a night the user did not wear the
    // band for.
    final illnessDay = illness is Map ? illness['date']?.toString() : null;
    final illnessBehind = _behind(illnessDay);
    final weight = (d.profile['weight_kg'] as num?);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.isNotEmpty)
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              rows[i],
            ],
          ]),
        ),
      for (final g in gaps) ...[const SizedBox(height: S.x3), g],

      // Illness watch — computed every rollup, read by nothing until now.
      if (state != null && state != 'green') ...[
        const SizedBox(height: S.x4),
        Observation(
          state == 'red'
              ? 'Several nights in a row are away from your normal'
              : (illnessBehind == null || illnessBehind <= 0
                  ? 'Last night sat outside your normal range'
                  : '${prettyDay(illnessDay)} sat outside your normal range'),
          // The RUN is what is above baseline — the accumulator only clears
          // after two nights back under. The stored z is the LATEST night's own
          // deviation and can be negative while the run is still up, which read
          // as "tracking above your own baseline, 1.3 deviations below it".
          'Your nocturnal resting heart rate has been running above your own '
              'baseline${illnessZ == null ? '' : '; that night sat '
                  '${illnessZ.abs().toStringAsFixed(1)} standardised deviations '
                  '${illnessZ >= 0 ? 'above' : 'below'} it'}. This watch reads '
              'that one signal; it names a pattern, and it does not name a '
              'cause.',
          advice: 'Worth noting if it continues past a couple of days.',
        ),
      ],

      Section(
        'Body composition',
        weight == null
            ? StatusCard(
                'No weight recorded',
                'Energy estimates need it.',
                fix: 'Add it in Profile',
                icon: LucideIcons.scale,
                onFix: () => go(c, const ProfileHome()),
              )
            : Column(children: [
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Builder(builder: (c) {
                    // Whatever the user chose two screens away in Settings —
                    // this row used to print kg regardless.
                    final u = unitsOf(c);
                    final (v, unit) = u == null
                        ? (weight.toStringAsFixed(1), 'kg')
                        : splitUnit(u.weight(weight));
                    return MetricRow(LucideIcons.scale, C.teal, 'Weight', v,
                        unit: unit,
                        sub: 'From your profile');
                  }),
                ),
                const SizedBox(height: S.x3),
                const StatusCard(
                  'No weight history',
                  'Only the current value is stored.',
                  icon: LucideIcons.chartLine,
                ),
              ]),
      ),
    ]);
  }

  // ─────────────── TRENDS ───────────────
  Widget _trends(BuildContext c, HealthData d) {
    final p = P.of(c);
    final cd = d.insights;
    final chrono = envValue(cd['chronotype']) ?? const {};
    final sjl = envValue(cd['social_jetlag']) ?? const {};
    final reg = envValue(cd['regularity']) ?? const {};
    final sjlH = sjl['abs_hours'] as num?;
    final sri = reg['sri'] as num?;
    final stale = staleInsightsCard(d.insightsStale, syncOf(c));

    /// [against] is the number the card compares the latest reading TO. Pass it
    /// and the delta is measured against that; leave it null and the delta is
    /// measured against the trailing mean of what is stored.
    ///
    /// It exists because the sleep card used to caption itself "vs your 7h 45m
    /// need" while still subtracting the 28-day AVERAGE — so the arrow and the
    /// figure under it read as sleep debt and were not. One of the two had to
    /// become true; the debt is the more useful of the pair.
    // No `Metric` argument: this card is drawn entirely from the stored
    // series, so taking the envelope only implied a cross-check that was
    // never made.
    Widget trend(String key, String label, String unit, Color col,
        {bool higherBetter = true, double? against, String? againstLabel}) {
      final pts = d.points(key);
      // Statistics off the STORED values; the painter gets the dense window.
      final s = valuesOf(pts);
      if (s.isEmpty) {
        return StatusCard(
          'No $label trend yet',
          '0 days stored.',
          icon: LucideIcons.chartLine,
        );
      }
      final prior = s.length > 1
          ? s.sublist(s.length - 1 - (s.length - 1).clamp(0, 28), s.length - 1)
          : const <double>[];
      // "vs your 28-day average" printed from the SECOND stored value, over a
      // mean of one. The window has to say how many days it actually holds.
      final mean =
          prior.isEmpty ? null : prior.reduce((a, b) => a + b) / prior.length;
      final base = against ?? mean;
      final window = against != null
          ? (againstLabel ?? '')
          : 'vs your ${prior.length}-day average';
      final delta = base == null ? 0.0 : s.last - base;
      final win = denseDays(pts, 30);
      final metricKey = key == 'sleep' ? 'sleep' : key;
      // The hero number is the newest STORED point, which after a sync gap is
      // not today's. Say when it is from rather than let the card imply now.
      final behind = daysBehind(pts.last.t) ?? 0;
      final asOf = behind <= 0 ? '' : ' · as of ${axisDay(pts.last.t)}';
      return TrendCard(
        label,
        key == 'sleep' ? hm(s.last) : metricValue(unit, s.last),
        key == 'sleep' ? '' : unit,
        base == null
            ? 'no baseline'
            : (key == 'sleep' ? hm(delta.abs()) : metricValue(unit, delta.abs())),
        '${base == null ? 'first readings' : window}$asOf',
        win,
        col,
        up: delta >= 0,
        // Null with no baseline: an arrow and a good/bad hue about a
        // comparison the card has just said it cannot make.
        good: base == null ? null : (delta >= 0) == higherBetter,
        onTap: () => go(c, MetricDetail(metricKey)),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      trend('resting_hr', 'Resting heart rate', 'bpm', C.red,
          higherBetter: false),
      const SizedBox(height: S.x3),
      trend('hrv', 'HRV', 'ms', C.green),
      const SizedBox(height: S.x3),
      if (d.need.value == null)
        trend('sleep', 'Time asleep', '', C.blue)
      else
        // `need` here is `crossday.sleep_coach.need` — the COMPUTED need. It is
        // never `sleep.need_min`, which is a hardcoded 480.
        trend('sleep', 'Time asleep', '', C.blue,
            against: d.need.value!.toDouble(),
            againstLabel: 'vs your ${hm(d.need.value)} need'),

      // Chronotype, jetlag and regularity ALL come out of the cross-day
      // rollup. When it is withheld, the section says why rather than showing
      // the cold-start "it takes a few weeks" line, which would be a lie.
      if (stale != null)
        Section('Body clock', stale)
      else
        Section(
          'Body clock',
          Surface(
            onTap: () => go(c, const CircadianDetail()),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: Text('Chronotype, jetlag and regularity',
                      style: F.cap.copyWith(color: p.ink2)),
                ),
                Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
              ]),
              if (chrono.isNotEmpty || sjlH != null || sri != null) ...[
                const SizedBox(height: S.x4),
                InlineMetrics([
                  if (chrono['type_label'] != null)
                    ('CHRONOTYPE', chrono['type_label'].toString(), C.indigo),
                  if (sjlH != null)
                    ('SOCIAL JETLAG', _hoursHm(sjlH), C.orange),
                  if (sri != null)
                    ('REGULARITY', '${sri.round()} / 100', C.green),
                ]),
              ],
            ]),
          ),
          action: 'Explore',
          onAction: () => go(c, const CircadianDetail()),
        ),

      Section(
        'Consistency',
        Surface(
          child: Consistency(
            // Already windowed to the last 30 calendar days by `HealthData.load`
            // — the clamp is a floor for a bad count, not the window.
            d.daysWithData.clamp(0, 30),
            30,
            'Days with a derived record in the last 30 days',
            C.domHealth,
          ),
        ),
      ),
    ]);
  }

  String _hoursHm(num h) {
    final m = (h * 60).round();
    return m < 60 ? '${m}m' : '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
  }

  // ─────────────── VITALS ───────────────
  Widget _vitals(BuildContext c, HealthData d) {
    final p = P.of(c);
    final v = _v;
    if (v == null) {
      return _vFailed
          ? _readFailed('vitals', () {
              setState(() => _vFailed = false);
              _loadVitals();
            })
          : const Padding(
              padding: EdgeInsets.only(top: S.x8),
              child: Center(child: CircularProgressIndicator()),
            );
    }

    // WHICH DAY this tab is showing. Every row here used to say "Today" for a
    // day the loader had fallen back to, which after a sync gap is days ago.
    final behind = _behind(v.day);
    final dayWord = behind == null || behind <= 0 ? 'Today' : prettyDay(v.day);
    // Skin temperature comes off the latest OVERNIGHT bundle, not the day the
    // other three rows describe, so it gets its own night when they differ.
    final tempNight = heldOverNightOf(d.today);

    final highs = v.timeline['highs'];
    num? high(String k) {
      final e = highs is Map ? highs[k] : null;
      return e is Map ? e['v'] as num? : null;
    }

    final lo = high('low_hr'), hi = high('peak_hr');
    final respBlock = v.lungs['resp'];
    final resp = respBlock is Map ? respBlock['value'] as num? : null;
    final worn = v.wear['worn_min'] as num?;
    final coverage = v.wear['coverage_pct'] as num?;
    final skinTemp = metricOf(d.today['skin_temp']);
    final rmssd = v.hrv['rmssd'] as num?;
    // MetricRow, not a private copy of it. The one this screen used to grow
    // stacked the value over its qualifier in a shrink-wrapped column, so
    // 'bpm today' and 'SD from your own nights' set each row's width and no
    // two values landed on the same x. The qualifier is not a unit and does
    // not belong beside the number: it goes under the name, where every other
    // list in the app already puts it.
    final rows = <Widget>[
      if (lo != null && hi != null)
        MetricRow(LucideIcons.heart, C.red, 'Heart rate',
            '${lo.round()} – ${hi.round()}',
            sub: dayWord, unit: 'bpm'),
      if (resp != null)
        MetricRow(LucideIcons.wind, C.teal, 'Respiratory rate',
            resp.toStringAsFixed(1),
            sub: 'Asleep', unit: 'br/min'),
      if (skinTemp.value != null)
        // NAME THE QUANTITY. This is `skin_temp_z` — standard deviations from
        // the user's own baseline. It printed signed and unitless beside a
        // heart rate in bpm, so it read as °C; and the sleep scrub's
        // "temperature" is a THIRD quantity again (raw ADC minus that day's
        // median), which is why neither may go unlabelled.
        MetricRow(LucideIcons.thermometer, C.orange, 'Skin temperature',
            '${skinTemp.value! >= 0 ? '+' : '−'}'
                '${skinTemp.value!.abs().toStringAsFixed(2)}',
            sub: tempNight == null
                ? 'vs your own nights'
                : 'vs your own nights · ${prettyDay(tempNight)}',
            unit: 'SD',
            // Both this row and the wear row below it carry a FULL, written,
            // cited spec in `metric_detail.dart` that no tap in the app opened.
            // The number was on screen and its method was unreachable.
            onTap: () => go(c, const MetricDetail('skin_temp'))),
      if (worn != null)
        MetricRow(LucideIcons.watch, C.green, 'Wear time', hm(worn),
            // `83.33333333333333% of the day` shipped. It is a percentage.
            sub: coverage == null
                ? dayWord
                : '${coverage.round()}% of '
                    '${dayWord == 'Today' ? 'the day' : dayWord}',
            onTap: () => go(c, const MetricDetail('wear'))),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ...dayNavRow(_vDay ?? v.day, v.days, _goVitalsDay),
      if (rows.isEmpty)
        StatusCard(
          'Nothing measured for this day',
          'No band recordings reached this day.',
          fix: syncOf(c) == null ? '' : 'Sync the band',
          icon: LucideIcons.watch,
          onFix: syncOf(c),
        )
      else
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              rows[i],
            ],
          ]),
        ),

      // No skin-temperature caveat card here. The row's own unit already says
      // the reading is relative, and `metric_detail` carries the method for
      // anyone who taps through — a whole card restating it on the way past is
      // the kind of explanation this screen was asked to stop giving.

      // No "Sleep architecture" deep dive either: Sleep is a tab of its own,
      // and a second door into it from Vitals is a duplicate entry point, not
      // a feature.
      if (rmssd != null)
        Section(
          'Deep dives',
          DeepDiveCard('Heart rate variability', '${rmssd.round()}', 'ms',
              'Time, frequency and non-linear', C.green,
              preview: _hrvPreview(c, d),
              onTap: () => go(c, const Investigate('hrv'))),
        ),
    ]);
  }

  /// The HRV preview inside the deep-dive card. Framed like every other chart:
  /// what it is, what it is measured in, what the heights mean, and how far
  /// back it reaches — all read off the series actually drawn.
  Widget _hrvPreview(BuildContext c, HealthData d) {
    const days = 30;
    final pts = d.points('hrv');
    // The window is thirty CALENDAR nights, dense, ending last night. The list
    // used to be the newest thirty STORED nights, which after a sync gap could
    // span two months while both axis labels — counted off the array — claimed
    // it spanned thirty. Nights with no record are holes, not joined across.
    final win = denseDays(pts, days);
    final have = [for (final v in win) ?v];
    final axis = AxisSpec.of(have, ticks: 2);
    final p = P.of(c);
    return ChartFrame(
      title: 'RMSSD, ${have.length} of the last $days nights',
      unit: 'ms',
      height: 48,
      yAxis: axis,
      xLabels: have.length < 2
          ? const []
          : ['${days - 1} nights ago', 'Last night'],
      empty: have.length < 2
          ? const NoData(message: 'One night is not a trend yet')
          : null,
      series: win,
      child: CustomPaint(
        size: Size.infinite,
        painter: LineChart(win, p.on(C.green), t: animate(c, 1), axis: axis),
      ),
    );
  }

  // ─────────────── EXPLORE ───────────────
  Widget _explore(BuildContext c) {
    final p = P.of(c);
    final e = _e;
    if (e == null) {
      return _eFailed
          ? _readFailed('measures', () {
              setState(() => _eFailed = false);
              _loadExplore();
            })
          : const Padding(
              padding: EdgeInsets.only(top: S.x8),
              child: Center(child: CircularProgressIndicator()),
            );
    }

    var have = 0, total = 0;
    for (final f in _catalogue) {
      for (final r in f.rows) {
        total++;
        if ((e.counts[r.series] ?? 0) > 0) have++;
      }
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        child: Consistency(have, total,
            'Measures with stored history on this device', C.domHealth,
            unit: 'measures'),
      ),
      const SizedBox(height: S.x3),
      // Not a promise of insight — a statement of what a tap gets you. Every
      // row below opens the same drill-down: the chart, your own range, the
      // method in full, and the paper it came from.
      Text(
          'Each one opens its chart, how it is computed, and the published '
          'method behind it.',
          style: F.over.copyWith(color: p.ink3, height: 1.6)),
      for (final f in _catalogue) _family(c, p, f, e.counts),
    ]);
  }

  Widget _family(BuildContext c, P p, _Cat f, Map<String, int> counts) {
    final have = [
      for (final r in f.rows)
        if ((counts[r.series] ?? 0) > 0) r,
    ];
    final none = [
      for (final r in f.rows)
        if ((counts[r.series] ?? 0) == 0) r,
    ];

    return Section(
      f.title,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (have.isNotEmpty)
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(children: [
              for (var i = 0; i < have.length; i++) ...[
                if (i > 0) Divider(color: p.line, height: 1),
                Builder(builder: (c) {
                  final r = have[i];
                  final s = specOf(r.key);
                  // NO NUMBER IN THE VALUE SLOT, on purpose.
                  //
                  // This used to print the day count. It read as a score: nine
                  // days of breathing rate beside seventeen of resting HR looks
                  // like the app is worse at breathing, when what it means is
                  // that the estimator abstains more — which is the behaviour
                  // we want. It also collapsed three different causes into one
                  // number: genuinely rare, key shipped last week, substrate
                  // pruned. `midsleep_sec` is forward-only and can never be
                  // backfilled, so it would sit at 1 next to everything else's
                  // 17 and mean nothing of the sort.
                  //
                  // And it was redundant. Rows with history sort above rows
                  // without, and the empty ones are named in the StatusCard
                  // below. Has / hasn't is the only thing an index owes you,
                  // and the layout already says it.
                  return MetricRow(s.icon, s.color, s.title, '',
                      sub: r.blurb,
                      onTap: () => go(c, MetricDetail(r.key)));
                }),
              ],
            ]),
          ),
        if (none.isNotEmpty) ...[
          if (have.isNotEmpty) const SizedBox(height: S.x3),
          StatusCard(
            have.isEmpty ? 'Nothing measured here yet' : 'Not measured yet',
            // No cause is named, because none is known here: this screen reads
            // a row count, and a count of zero says the day never produced one
            // — never why. No `fix:` either; there is no button that makes a
            // derive happen for a night that has already been scored.
            '${none.map((r) => specOf(r.key).title).join(' · ')}. '
                'No day on this device has produced one yet.',
            icon: LucideIcons.chartLine,
          ),
        ],
      ]),
    );
  }

  // ─────────────── LABS ───────────────
  Widget _labs(BuildContext c) {
    final p = P.of(c);
    final l = _l;
    if (l == null) {
      return _lFailed
          ? _readFailed('lab results', () {
              setState(() => _lFailed = false);
              _loadLabs();
            })
          : const Padding(
              padding: EdgeInsets.only(top: S.x8),
              child: Center(child: CircularProgressIndicator()),
            );
    }

    final sex = (_d?.profile['sex'])?.toString();
    // Newest draw per marker. `labResults` is already taken_on DESC.
    final latest = <String, Map<String, dynamic>>{};
    for (final r in l.results) {
      latest.putIfAbsent(r['marker'].toString(), () => r);
    }
    final byKey = {for (final m in l.markers) m.key: m};
    // A stored result with no number is not a measurement — it is dropped, the
    // way MonoTable drops an empty row. A bare em-dash in a lab column reads as
    // "the assay failed", which is a claim about your blood.
    final rows = latest.values.where((r) => r['value'] is num).toList()
      ..sort((a, b) => (byKey[a['marker']]?.label ?? '')
          .compareTo(byKey[b['marker']]?.label ?? ''));
    final lastDraw = l.results.isEmpty ? null : l.results.first['taken_on'];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (rows.isEmpty)
        const StatusCard(
          'No lab results yet',
          'Nothing logged yet.',
          icon: LucideIcons.testTube,
        )
      else ...[
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              _lab(p, byKey[rows[i]['marker'].toString()], rows[i], sex),
            ],
          ]),
        ),
        const SizedBox(height: S.x3),
        Text('Last panel ${lastDraw ?? ''} · logged by hand',
            style: F.over.copyWith(color: p.ink3)),
      ],
      const SizedBox(height: S.x4),
      BigButton('Add a result',
          icon: LucideIcons.plus,
          color: C.blue,
          soft: true,
          onTap: () => _addLab(c, l)),
      const SizedBox(height: S.x4),
      // The app never prints "abnormal" anywhere, so it does not need to say
      // it does not. What the user cannot know without being told is that the
      // range shown here is not the range their own lab used.
      Text('Ranges differ by lab. Use the one on your report.',
          style: F.over.copyWith(color: p.ink3, height: 1.6)),
    ]);
  }

  Widget _lab(P p, LabMarker? m, Map<String, dynamic> r, String? sex) {
    final v = (r['value'] as num?)?.toDouble();
    final unit = (r['unit'] ?? m?.unit ?? '').toString();
    final range = m?.rangeFor(sex);
    final inRange = v == null || m == null ? null : m.inRange(v, sex: sex);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            // No interval means NO OPINION — a grey dot, never a green one.
            color: inRange == null
                ? p.ink3
                : (inRange ? p.on(C.green) : p.on(C.orange)),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m?.label ?? r['marker'].toString(),
                style: F.body.copyWith(color: p.ink)),
            Text(
                range == null
                    ? 'No reference interval · ${r['taken_on']}'
                    : 'Typical ${_num(range.low)}–${_num(range.high)} · '
                        '${r['taken_on']}',
                style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x2),
        Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(v == null ? '' : (m?.format(v) ?? v.toString()),
                  style: F.n17.copyWith(
                      color: inRange == false ? p.on(C.orange) : p.ink)),
              const SizedBox(width: 3),
              Text(unit, style: F.over.copyWith(color: p.ink3)),
            ]),
      ]),
    );
  }

  String _num(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  /// Deliberately plain. Entering blood work is a rare, careful act; it does
  /// not need a designed flow, it needs the marker, the number and the date.
  Future<void> _addLab(BuildContext c, LabsData l) async {
    var marker = l.markers.first;
    final value = TextEditingController();
    final now = DateTime.now();
    final takenOn = TextEditingController(
        text: '${now.year.toString().padLeft(4, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}');

    final ok = await showDialog<bool>(
      context: c,
      builder: (dc) => StatefulBuilder(
        builder: (dc, setLocal) => AlertDialog(
          title: const Text('Add a result'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Unlabelled it announces only its current value — a marker
              // name, with no statement of what the field is.
              Semantics(
                label: 'Marker',
                child: DropdownButton<LabMarker>(
                  isExpanded: true,
                  value: marker,
                  items: [
                    for (final m in l.markers)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (m) => setLocal(() => marker = m ?? marker),
                ),
              ),
              TextField(
                controller: value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Value (${marker.unit})'),
              ),
              TextField(
                controller: takenOn,
                decoration:
                    const InputDecoration(labelText: 'Date drawn (YYYY-MM-DD)'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dc).pop(false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.of(dc).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    // Blood work typed by hand is exactly the input nobody notices is missing,
    // so nothing here fails quietly: the dialog used to close on Save and the
    // result was dropped whenever the value carried its unit ("78 ng/mL") or
    // the date was written the other way round.
    final v = Typed.of(value.text);
    final date = takenOn.text.trim();
    if (v.value == null || DateTime.tryParse(date) == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(v.value == null
            ? 'The value needs to be a number on its own, without the unit. '
                'Nothing was saved.'
            : 'The date needs to be YYYY-MM-DD. Nothing was saved.'),
      ));
      return;
    }
    try {
      await LocalDb.putLabResult(
        marker: marker.key,
        takenOn: date,
        value: v.value!,
        unit: marker.unit,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save it: $e')));
      }
      return;
    }
    _l = null;
    await _loadLabs();
  }
}

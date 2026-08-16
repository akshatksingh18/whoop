// The activity summary — eight archetypes, eight centres of gravity.
//
// The rule the whole file exists to enforce: a strength session is NOT a run
// with the map removed. A run is a route coloured by pace; a lift is a muscle
// map and a volume total; a hike is an elevation profile; a swim is a lap
// ladder; HIIT is an interval ladder; a match is heart rate and hard minutes.
// Same grammar — same cards, same type, same spacing — different defining
// object.
//
// [ActivityResult] is the seam. Everything on screen comes out of it, every
// field is nullable or empty by default, and an absent field renders a
// StatusCard rather than a zero. That is not politeness: `sessions` has no
// distance, no lap and no set columns of its own, so several of these fields
// come from elsewhere (`workout_route`, `strength_set`) or not at all, and the
// screen has to be honest about it without falling apart.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../charts.dart';
import '../grammar.dart';
import '../paint_activity.dart';
import '../profile/profile.dart';
import '../theme.dart';
import 'catalogue.dart';
import 'share.dart';

/// The defining visual object of an activity. Everything else supports it.
///
/// There is no `power`. Cycling power is watts at the crank, and nothing in
/// this stack measures them: no power meter is paired, no opcode carries them,
/// and a wrist cannot infer them. The indoor machines that used to claim the
/// archetype (bike, treadmill, elliptical, stair climber) are [basic] — their
/// defining object is the heart-rate trace, which is measured.
enum Arch { route, strength, interval, flow, laps, journey, match, basic }

const _sports = {
  'Football', 'Basketball', 'Cricket', 'Tennis', 'Badminton', 'Table tennis',
  'Squash', 'Volleyball', 'Hockey', 'Baseball', 'Rugby', 'Boxing',
  'Martial arts', 'Wrestling',
};
const _laps = {'Swimming', 'Rowing'};
const _journey = {
  'Hiking', 'Trail running', 'Mountain biking', 'Skiing', 'Snowboarding',
};

/// Name first, then track. The named sets are the activities whose defining
/// object is not what their tracking mode would suggest — a hike is tracked by
/// distance but is *about* the climb, and swimming is tracked by distance but
/// is *about* the lap.
Arch archOf(Activity a) {
  if (_journey.contains(a.name)) return Arch.journey;
  if (_laps.contains(a.name)) return Arch.laps;
  if (_sports.contains(a.name)) return Arch.match;
  return switch (a.track) {
    Track.sets => Arch.strength,
    Track.interval => Arch.interval,
    Track.stillness => Arch.flow,
    Track.distance => Arch.route,
    Track.duration => Arch.basic,
  };
}

String archLabel(Arch a) => switch (a) {
      Arch.route => 'Route',
      Arch.strength => 'Sets and load',
      Arch.interval => 'Intervals',
      Arch.flow => 'Flow',
      Arch.laps => 'Laps',
      Arch.journey => 'Elevation',
      Arch.match => 'Effort',
      Arch.basic => 'Session',
    };

// ── THE RECORD ─────────────────────────────────────────────────────────────

/// One logged set. `loadKg` is nullable and that is load-bearing: a bodyweight
/// pull-up stored as 0 kg makes session volume report zero for a real session
/// (UI_WIRING §5.4).
class LoggedSet {
  final String exerciseKey;
  final int reps;
  final double? loadKg;
  final int? rpe;
  final int? restSec;
  final DateTime at;

  const LoggedSet(this.exerciseKey, this.reps,
      {this.loadKg, this.rpe, this.restSec, required this.at});

  /// Volume for this set, or null when the load was never recorded.
  double? get volume => loadKg == null ? null : loadKg! * reps;
}

/// A strength session's sets, in log order.
class StrengthLog {
  final List<LoggedSet> sets;
  const StrengthLog(this.sets);

  static const empty = StrengthLog([]);

  bool get isEmpty => sets.isEmpty;
  int get setCount => sets.length;
  int get repCount => sets.fold(0, (a, s) => a + s.reps);
  List<String> get exercises {
    final seen = <String>[];
    for (final s in sets) {
      if (!seen.contains(s.exerciseKey)) seen.add(s.exerciseKey);
    }
    return seen;
  }

  /// Σ load × reps over the sets that HAVE a load. Null when none of them do —
  /// a bodyweight-only session has a real volume nobody measured.
  double? get volumeKg {
    var total = 0.0;
    var any = false;
    for (final s in sets) {
      final v = s.volume;
      if (v == null) continue;
      total += v;
      any = true;
    }
    return any ? total : null;
  }

  /// Whether any set was logged without a load — the total is then a floor,
  /// not a total, and the screen says so.
  bool get hasUnloadedSets => sets.any((s) => s.loadKg == null);

  Map<String, double> get volumeByExercise {
    final out = <String, double>{};
    for (final s in sets) {
      final v = s.volume;
      if (v == null) continue;
      out[s.exerciseKey] = (out[s.exerciseKey] ?? 0) + v;
    }
    return out;
  }

  /// Heaviest set by load, ties broken by reps. Null when nothing was loaded.
  LoggedSet? get topSet {
    LoggedSet? best;
    for (final s in sets) {
      if (s.loadKg == null) continue;
      if (best == null ||
          s.loadKg! > best.loadKg! ||
          (s.loadKg == best.loadKg && s.reps > best.reps)) {
        best = s;
      }
    }
    return best;
  }

  List<LoggedSet> forExercise(String key) =>
      [for (final s in sets) if (s.exerciseKey == key) s];
}

/// Epley 1RM estimate — ALWAYS an estimate, never shown without saying so.
/// Epley B. (1985), Poundage Chart. Boone's/Brzycki disagree by a few kg; at
/// six reps or fewer they are all within noise of each other.
double? oneRepMax(LoggedSet? s) =>
    s?.loadKg == null || s!.reps < 1 ? null : s.loadKg! * (1 + s.reps / 30);

/// One HIIT round.
class IntervalRound {
  final int workSec, restSec;
  final int? avgHr;
  const IntervalRound(this.workSec, this.restSec, {this.avgHr});
}

/// One distance split. Named `KmSplit` because Flutter's animation library
/// already owns `Split`, and a screen importing both should not have to.
class KmSplit {
  final double km;
  final int sec;
  final int? avgHr;
  const KmSplit(this.km, this.sec, {this.avgHr});
}

/// Everything a finished session knows about itself. Absent means absent.
class ActivityResult {
  final Activity activity;
  final DateTime start;
  final Duration duration;
  final bool private;

  // measured by the band / phone
  final int? avgHr, maxHr, calories;
  final double? strain;
  // Per-MINUTE mean heart rate, live (`LiveWorkoutState.perMinuteHr`) and
  // stored (`getWorkout()['hr']`) alike. Nothing on this screen has ever been
  // per-second, whatever the copy used to say.
  /// DENSE — one slot per minute of the session, `null` where the band
  /// recorded nothing. A compacted curve under an axis labelled `Start …
  /// duration` draws a dropout as though it had been measured.
  final List<double?> hr;
  final List<double> zoneMinutes; // five, Z1..Z5

  // route / journey
  final List<Offset> route; // normalised 0…1
  final List<double>? routePace; // per-point 0…1, colours the route
  final double? distanceKm;
  final List<double> elevationM;
  final double? gainM, lossM;
  final List<KmSplit> splits;

  // strength
  final StrengthLog strength;

  // laps — seconds per lap, in order. The bar chart's relative speeds are
  // derived from these rather than stored beside them: two fields for one
  // measurement is how a chart ends up disagreeing with its own axis.
  final List<int> lapSecs;
  final int? poolLengthM;
  final String? stroke;

  // intervals
  final List<IntervalRound> rounds;

  // flow
  final List<String> poses;
  final double? breathsPerMin;

  // match
  final List<(int, int)> gameScore;

  const ActivityResult(
    this.activity, {
    required this.start,
    required this.duration,
    this.private = false,
    this.avgHr,
    this.maxHr,
    this.calories,
    this.strain,
    this.hr = const [],
    this.zoneMinutes = const [],
    this.route = const [],
    this.routePace,
    this.distanceKm,
    this.elevationM = const [],
    this.gainM,
    this.lossM,
    this.splits = const [],
    this.strength = StrengthLog.empty,
    this.lapSecs = const [],
    this.poolLengthM,
    this.stroke,
    this.rounds = const [],
    this.poses = const [],
    this.breathsPerMin,
    this.gameScore = const [],
  });

  /// A copy carrying the things a session can only learn after it ends — the
  /// recorded route above all. Every field defaults to `this`, so enrichment
  /// can never silently drop the sets or the score the user typed.
  ActivityResult copyWith({
    int? avgHr,
    int? maxHr,
    List<double?>? hr,
    List<double>? zoneMinutes,
    List<Offset>? route,
    List<double>? routePace,
    double? distanceKm,
    List<double>? elevationM,
    double? gainM,
    double? lossM,
    List<KmSplit>? splits,
    StrengthLog? strength,
  }) =>
      ActivityResult(
        activity,
        start: start,
        duration: duration,
        private: private,
        avgHr: avgHr ?? this.avgHr,
        maxHr: maxHr ?? this.maxHr,
        calories: calories,
        strain: strain,
        hr: hr ?? this.hr,
        zoneMinutes: zoneMinutes ?? this.zoneMinutes,
        route: route ?? this.route,
        routePace: routePace ?? this.routePace,
        distanceKm: distanceKm ?? this.distanceKm,
        elevationM: elevationM ?? this.elevationM,
        gainM: gainM ?? this.gainM,
        lossM: lossM ?? this.lossM,
        splits: splits ?? this.splits,
        strength: strength ?? this.strength,
        lapSecs: lapSecs,
        poolLengthM: poolLengthM,
        stroke: stroke,
        rounds: rounds,
        poses: poses,
        breathsPerMin: breathsPerMin,
        gameScore: gameScore,
      );

  Arch get arch => archOf(activity);

  /// Per-lap speed relative to the fastest lap — what [LapBars] draws. The
  /// fastest lap is the only reference the swim itself provides.
  List<double> get lapSpeeds {
    if (lapSecs.isEmpty) return const [];
    final fastest = lapSecs.reduce((x, y) => x < y ? x : y);
    return [for (final t in lapSecs) t <= 0 ? 1.0 : fastest / t];
  }

  /// Minutes above 80% of max heart rate — Z4 and Z5. Null when the session
  /// banked no zone split, because "0 hard minutes" and "nobody counted" are
  /// different sessions.
  double? get hardMinutes => zoneMinutes.length == 5
      ? zoneMinutes[3] + zoneMinutes[4]
      : null;

  /// Seconds per kilometre. Null without a distance — there is no pace
  /// without one, and a duration alone will not do.
  int? get paceSecPerKm => distanceKm == null || distanceKm! <= 0
      ? null
      : (duration.inSeconds / distanceKm!).round();

  int? get lapCount => lapSecs.isEmpty ? null : lapSecs.length;

  double? get swimMetres => poolLengthM == null || lapCount == null
      ? null
      : (poolLengthM! * lapCount!).toDouble();
}

// ── FORMATTING ─────────────────────────────────────────────────────────────

/// mm:ss, or h:mm:ss past the hour.
String clock(int seconds) {
  final s = seconds.abs();
  final m = (s ~/ 60) % 60, h = s ~/ 3600;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s % 60)}' : '${two(m)}:${two(s % 60)}';
}

String hms(Duration d) => clock(d.inSeconds);

/// 1 234 → "1,234". Thousands separators, because six-thousand-eight-hundred
/// and forty-two kilos should not read as a phone number.
String grouped(num v) {
  final s = v.round().abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String pace(int secPerKm) => '${secPerKm ~/ 60}:'
    '${(secPerKm % 60).toString().padLeft(2, '0')}';

String _shortDate(DateTime t) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${months[t.month - 1]} ${t.day}, ${t.year} at $h:'
      '${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

// ── THE SCREEN ─────────────────────────────────────────────────────────────

class ActivitySummary extends StatefulWidget {
  final ActivityResult result;

  /// Body weight, for the calorie note. Null when the profile has none.
  final double? weightKg;

  /// Set only when persisting the session threw. Non-null means this summary
  /// is drawn from something that is NOT in the database, and calling it tries
  /// the write again.
  final Future<ActivityResult> Function()? onRetrySave;

  const ActivitySummary(this.result,
      {super.key, this.weightKg, this.onRetrySave});

  @override
  State<ActivitySummary> createState() => _ActivitySummaryState();
}

class _ActivitySummaryState extends State<ActivitySummary> {
  int tab = 0;

  /// A yoga session, a tennis match and an untracked session do not break into
  /// pieces — not "have none today", never. So they do not get the tab. The
  /// card that used to sit inside it explaining its own absence was the tab
  /// justifying its existence to the person who opened it.
  List<String> get _tabs => switch (arch) {
        Arch.flow || Arch.match || Arch.basic => const ['Overview', 'Graphs'],
        _ => const ['Overview', 'Splits', 'Graphs'],
      };

  /// Whether the session is still only on screen. Starts true whenever a
  /// retry was handed down, because that is what being handed one means.
  late bool unsaved = widget.onRetrySave != null;
  bool _saving = false;

  ActivityResult get r => widget.result;
  Activity get a => r.activity;
  Arch get arch => r.arch;

  Future<void> _retrySave() async {
    if (_saving) return;
    setState(() => _saving = true);
    var ok = false;
    try {
      await widget.onRetrySave!();
      ok = true;
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      unsaved = !ok;
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(
              a.name,
              sub: _shortDate(r.start).toUpperCase(),
              trailing: Pressable(
                semanticLabel: 'Share this ${a.name.toLowerCase()}',
                onTap: () => Navigator.of(c).push(MaterialPageRoute(
                    builder: (_) => ShareSheet(r))),
                child: Icon(LucideIcons.share2, size: 19, color: p.ink2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: SubTabs(_tabs, tab, (i) => setState(() => tab = i),
                color: a.color),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x10),
              // By NAME: the tab list is shorter for the archetypes that have
              // no splits, so index 1 is not always the same tab.
              children: switch (_tabs[tab]) {
                'Overview' => _overview(c, p),
                'Splits' => _splits(c, p),
                _ => _graphs(c, p),
              },
            ),
          ),
        ]),
      ),
    );
  }

  // ─────────────────── OVERVIEW ───────────────────
  List<Widget> _overview(BuildContext c, P p) {
    final hero = _hero();
    return [
      if (unsaved) ...[
        StatusCard(
          'This session is not saved yet',
          'Writing it to this phone failed.',
          fix: _saving ? 'Saving' : 'Try again',
          onFix: _saving ? null : _retrySave,
          icon: LucideIcons.triangleAlert,
        ),
        const SizedBox(height: S.x5),
      ],
      Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
                child: Text(hero.$1,
                    style: F.n48.copyWith(color: p.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            if (hero.$2.isNotEmpty) ...[
              const SizedBox(width: S.x2),
              Text(hero.$2, style: F.body.copyWith(color: p.ink3)),
            ],
            const Spacer(),
            if (r.private)
              const Pill('Private', C.n500, icon: LucideIcons.lock),
          ]),
      const SizedBox(height: S.x1),
      Text(hero.$3, style: F.cap.copyWith(color: p.ink2)),
      const SizedBox(height: S.x5),
      ..._definingObject(c, p),
      const SizedBox(height: S.x5),
      Surface(
        child: Row(
            children: _stats()
                .map((s) => Expanded(child: _st(p, s.$1, s.$2)))
                .toList()),
      ),
      ..._body(c, p),
      // Zones belong to any session that banked a split — a lift and a yoga
      // class have heart-rate zones too.
      ..._zoneSection(p),
      const SizedBox(height: S.x5),
      _calorieNote(p),
    ];
  }

  Widget _calorieNote(P p) => Surface(
        elevation: 0,
        color: p.card2,
        child: Row(children: [
          Expanded(
            child: Text(
                widget.weightKg == null
                    ? 'Calories need your weight. $kCalorieNeedsWeight'
                    : 'Estimated from ${a.met.toStringAsFixed(1)} MET, your '
                        'weight and heart rate.',
                style: F.cap.copyWith(color: p.ink3, height: 1.5)),
          ),
        ]),
      );

  /// (value, unit, caption). The hero is the archetype's own headline — and
  /// falls back to elapsed time, which is the one number every session has.
  (String, String, String) _hero() {
    final fallback = (hms(r.duration), '', 'Elapsed time');
    return switch (arch) {
      Arch.route || Arch.journey => r.distanceKm == null
          ? fallback
          : (
              r.distanceKm!.toStringAsFixed(2),
              'km',
              arch == Arch.journey && r.gainM != null
                  ? '+${r.gainM!.round()} m climbed'
                  : a.name
            ),
      Arch.strength => r.strength.volumeKg == null
          ? (
              '${r.strength.setCount}',
              r.strength.setCount == 1 ? 'set' : 'sets',
              'Nothing was logged with a load'
            )
          : (
              grouped(r.strength.volumeKg!),
              'kg',
              r.strength.hasUnloadedSets
                  ? 'Volume of the loaded sets'
                  : 'Total volume'
            ),
      Arch.laps => r.swimMetres == null
          ? fallback
          : (grouped(r.swimMetres!), 'm', '${r.lapCount} laps'),
      Arch.flow ||
      Arch.match ||
      Arch.interval ||
      Arch.basic =>
        fallback,
    };
  }

  /// Three supporting numbers. `—` never appears: a stat with nothing behind
  /// it is dropped, and the row shrinks.
  List<(String, String)> _stats() {
    final out = <(String, String)>[];
    void add(String? v, String label) {
      if (v != null) out.add((v, label));
    }

    add(hms(r.duration), 'Time');
    switch (arch) {
      case Arch.route:
        add(r.paceSecPerKm == null ? null : pace(r.paceSecPerKm!), 'Pace');
      case Arch.strength:
        add('${r.strength.setCount}', 'Sets');
        add('${r.strength.repCount}', 'Reps');
      case Arch.laps:
        add(r.lapCount?.toString(), 'Laps');
      case Arch.journey:
        add(r.gainM == null ? null : '+${r.gainM!.round()}', 'm gain');
      case Arch.interval:
        add(r.rounds.isEmpty ? null : '${r.rounds.length}', 'Rounds');
      case Arch.flow:
        add(r.poses.isEmpty ? null : '${r.poses.length}', 'Poses');
        add(r.breathsPerMin?.toStringAsFixed(1), 'Breaths/min');
      case Arch.match:
        add(r.gameScore.isEmpty ? null : '${r.gameScore.length}', 'Sets');
        add(r.hardMinutes == null ? null : '${r.hardMinutes!.round()}',
            'Hard min');
      case Arch.basic:
        break; // time, heart rate and calories are the whole story
    }
    add(r.avgHr?.toString(), 'Avg HR');
    add(r.calories == null ? null : grouped(r.calories!), 'kcal');
    add(r.strain?.toStringAsFixed(1), 'Strain');
    return out.take(3).toList();
  }

  Widget _st(P p, String v, String l) => Column(children: [
        Text(v, style: F.n24.copyWith(color: p.ink), maxLines: 1),
        const SizedBox(height: S.x1),
        Text(l,
            style: F.over.copyWith(color: p.ink3),
            textAlign: TextAlign.center),
      ]);

  // ─────────── THE DEFINING VISUAL OBJECT ───────────
  List<Widget> _definingObject(BuildContext c, P p) {
    switch (arch) {
      case Arch.route:
        if (r.route.length < 2) {
          return [
            // No `fix`: there is no "how route recording works" screen, and
            // StatusCard paints any fix string as a blue call to action —
            // a button that cannot be tapped is worse than no button.
            const StatusCard(
              'No route for this session',
              'Location was off, or this activity was not recorded with GPS.',
              icon: LucideIcons.map,
            ),
          ];
        }
        return [
          Surface(
            child: ChartFrame(
              title: 'ROUTE',
              unit: 'km',
              height: 200,
              legend: r.routePace == null
                  ? const []
                  : [('Slower', ZoneBar.cols(p)[2]), ('Faster', ZoneBar.cols(p)[3])],
              footnote: r.distanceKm == null
                  ? 'Start and finish are pinned.'
                  : '${r.distanceKm!.toStringAsFixed(2)} km, '
                      'start and finish pinned.',
              child: ClipRRect(
                borderRadius: R.rLg,
                child: Container(
                  color: p.card2,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: RouteMap(r.route,
                        pace: r.routePace,
                        slow: p.on(C.green),
                        fast: p.on(C.orange),
                        pinStart: p.on(C.green),
                        pinEnd: p.on(C.red),
                        pinInk: p.card),
                  ),
                ),
              ),
            ),
          ),
        ];

      case Arch.strength:
        final load = muscleLoad(r.strength.volumeByExercise);
        if (load.isEmpty) {
          return [
            const StatusCard(
              'No muscle map for this session',
              '0 exercises logged with a load.',
              icon: LucideIcons.personStanding,
            ),
          ];
        }
        final ranked = load.entries.toList()
          ..sort((x, y) => y.value.compareTo(x.value));
        return [
          Surface(
            child: ChartFrame(
              title: 'MUSCLE GROUPS',
              unit: '% of this session',
              height: 190,
              footnote: 'Share of your logged volume, relative to the hardest-'
                        'worked group.',
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: CustomPaint(
                          size: Size.infinite,
                          painter: MuscleMap(load, p.on(C.purple), p.track)),
                    ),
                    const SizedBox(width: S.x4),
                    Expanded(
                      child: Column(children: [
                        for (final e in ranked.take(5))
                          _MuscleRow(e.key, e.value),
                      ]),
                    ),
                  ]),
            ),
          ),
        ];

      case Arch.interval:
        if (r.rounds.isEmpty) {
          return [
            const StatusCard(
              'No rounds recorded',
              '0 rounds logged.',
              icon: LucideIcons.timer,
            ),
          ];
        }
        final peak = r.rounds
            .map((x) => x.workSec > x.restSec ? x.workSec : x.restSec)
            .reduce((x, y) => x > y ? x : y)
            .toDouble();
        return [
          Surface(
            child: ChartFrame(
              title: 'INTERVAL LADDER',
              unit: 'seconds',
              height: 110,
              legend: [('Work', p.on(C.red)), ('Rest', p.on(C.teal))],
              xLabels: ['Round 1', 'Round ${r.rounds.length}'],
              footnote: 'Longest block ${clock(peak.round())}.',
              child: CustomPaint(
                size: Size.infinite,
                painter: IntervalLadder([
                  for (final x in r.rounds)
                    (work: x.workSec / peak, rest: x.restSec / peak),
                ], p.on(C.red), p.on(C.teal)),
              ),
            ),
          ),
        ];

      case Arch.flow:
        // No breath ring here. The live screen's ring is a PACER driven by a
        // controller the user breathes along with; on a finished session there
        // is no phase to draw, and a static ring at some pleasing fraction is
        // a measurement-shaped decoration.
        return [
          Container(
            height: 170,
            decoration: BoxDecoration(
                borderRadius: R.rLg,
                color: p.wash(C.teal, strength: 1.6),
                boxShadow: p.el(1)),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.personStanding, size: 44, color: p.on(C.teal)),
                  const SizedBox(height: S.x2),
                  Text(
                      r.poses.isEmpty
                          ? hms(r.duration)
                          : '${r.poses.length} poses',
                      style: F.head.copyWith(color: p.ink)),
                  Text(
                      r.breathsPerMin == null
                          ? a.name
                          : '${r.breathsPerMin!.toStringAsFixed(1)} breaths/min',
                      style: F.over.copyWith(color: p.on(C.teal))),
                ]),
          ),
        ];

      case Arch.laps:
        if (r.lapSecs.isEmpty) {
          return [
            const StatusCard(
              'No laps counted',
              '0 laps tapped. No sensor can see a pool wall.',
              icon: LucideIcons.waves,
            ),
          ];
        }
        final fastest = r.lapSecs.reduce((x, y) => x < y ? x : y);
        final slowest = r.lapSecs.reduce((x, y) => x > y ? x : y);
        return [
          Surface(
            child: ChartFrame(
              title: 'LAPS',
              unit: 'seconds per lap',
              height: 150,
              xLabels: ['Lap 1', 'Lap ${r.lapSecs.length}'],
              footnote: [
                if (r.poolLengthM != null) '${r.poolLengthM} m pool',
                'fastest ${clock(fastest)}',
                'slowest ${clock(slowest)}',
              ].join(' · '),
              child: CustomPaint(
                  size: Size.infinite,
                  painter: LapBars(r.lapSpeeds, p.on(C.blue), p.track)),
            ),
          ),
        ];

      case Arch.journey:
        if (r.elevationM.length < 2) {
          return [
            const StatusCard(
              'No elevation profile',
              'No route, or the route carried no altitude.',
              icon: LucideIcons.mountain,
            ),
          ];
        }
        final peak = r.elevationM.reduce((x, y) => x > y ? x : y);
        final axis = AxisSpec.of(r.elevationM);
        return [
          Surface(
            child: Column(children: [
              ChartFrame(
                title: 'ELEVATION',
                unit: 'm',
                height: 130,
                yAxis: axis,
                xLabels: const ['Start', 'Finish'],
                footnote: 'Altitude comes from the GPS fixes, which are less '
                    'certain vertically than horizontally.',
                series: r.elevationM,
                child: CustomPaint(
                    size: Size.infinite,
                    painter: Elevation(r.elevationM, p.on(C.green),
                        markerInk: p.card, axis: axis)),
              ),
              const SizedBox(height: S.x4),
              InlineMetrics([
                if (r.gainM != null) ('Gain', '+${r.gainM!.round()} m', C.green),
                if (r.lossM != null) ('Loss', '−${r.lossM!.round()} m', C.orange),
                ('Peak', '${grouped(peak)} m', C.n500),
              ]),
            ]),
          ),
        ];

      // A match is heart rate and hard minutes. There is no court map: the
      // only positioning this app has is GPS at wrist accuracy, which indoors
      // is nothing at all — the old map drew a decorative scatter that looked
      // exactly like a measurement.
      case Arch.match || Arch.basic:
        if (r.hr.length < 2) {
          return [
            StatusCard(
              'No heart rate for this session',
              'The band reported nothing while this was running.',
              fix: 'Check band connection',
              // The band, its battery and its link all live behind the
              // profile's sources list. The CTA used to be paint.
              onFix: () => openProfile(c),
              icon: LucideIcons.heartPulse,
            ),
          ];
        }
        return [Surface(child: _hrFrame(p))];
    }
  }

  /// The heart-rate trace, framed — the one chart both `basic` and `match`
  /// are built on, so they cannot end up with two different axes for one
  /// measurement.
  Widget _hrFrame(P p, {double height = 130}) {
    final axis = AxisSpec.of(r.hr.whereType<double>());
    final hard = r.hardMinutes;
    return ChartFrame(
      title: 'HEART RATE',
      unit: 'bpm',
      height: height,
      yAxis: axis,
      xLabels: ['Start', hms(r.duration)],
      footnote: hard == null
          ? null
          : '${hard.round()} min above 80% of your maximum.',
      series: r.hr,
      child: CustomPaint(
          size: Size.infinite,
          painter: LineChart(r.hr, p.on(C.red),
              axis: axis, t: animate(context, 1))),
    );
  }

  /// The zone split, with the minutes in the key rather than in a second row
  /// underneath it that has to be kept in step by hand.
  Widget _zoneFrame(P p) => ChartFrame(
        title: 'TIME IN ZONES',
        unit: 'minutes',
        height: 10,
        legend: [
          for (var i = 0; i < 5; i++)
            ('Z${i + 1} · ${r.zoneMinutes[i].round()}m', ZoneBar.cols(p)[i]),
        ],
        child: CustomPaint(
            size: Size.infinite, painter: ZoneBar(_zoneFractions(), p)),
      );

  // ─────────── ARCHETYPE BODY ───────────
  List<Widget> _body(BuildContext c, P p) {
    switch (arch) {
      case Arch.strength:
        final top = r.strength.topSet;
        final rm = oneRepMax(top);
        return [
          if (top != null)
            Section(
              'Top set',
              Surface(
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: p.wash(C.yellow), borderRadius: R.rMd),
                    child: Icon(LucideIcons.trophy,
                        size: 19, color: p.on(C.yellow)),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              exerciseByKey(top.exerciseKey)?.label ??
                                  top.exerciseKey,
                              style: F.body.copyWith(
                                  color: p.ink, fontWeight: FontWeight.w600)),
                          Row(children: [
                            Flexible(
                                child: Text('1RM estimate ${rm!.round()} kg',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: F.over.copyWith(color: p.ink3))),
                          ]),
                        ]),
                  ),
                  const SizedBox(width: S.x2),
                  // The row rule: the name gives way, the measurement keeps
                  // its natural width and sits flush at the card edge.
                  Text('${_kg(top.loadKg!)} × ${top.reps}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: F.n17.copyWith(color: p.ink)),
                ]),
              ),
            ),
          if (r.strength.hasUnloadedSets)
            const Padding(
              padding: EdgeInsets.only(top: S.x4),
              child: StatusCard(
                'Some sets had no load',
                'Counted in sets and reps, but left out of volume.',
                icon: LucideIcons.info,
              ),
            ),
        ];

      // A pacer is not a measurement and a mood picker with nowhere to write
      // is not a question — `sessions` has no mood column and `journal_metric`
      // is per-day, not per-session. Both were removed rather than explained.
      case Arch.flow:
        return const [];

      case Arch.match:
        return [
          if (r.gameScore.isNotEmpty)
            Section(
              'Score',
              Surface(
                pad: const EdgeInsets.symmetric(horizontal: S.x4),
                child: Column(children: [
                  for (var i = 0; i < r.gameScore.length; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x3),
                      child: Row(children: [
                        Expanded(
                            child: Text('Set ${i + 1}',
                                style: F.body.copyWith(color: p.ink3))),
                        Text('${r.gameScore[i].$1} — ${r.gameScore[i].$2}',
                            style: F.n17.copyWith(
                                color: r.gameScore[i].$1 > r.gameScore[i].$2
                                    ? p.on(a.color)
                                    : p.ink3)),
                      ]),
                    ),
                    if (i < r.gameScore.length - 1)
                      Divider(color: p.line, height: 1),
                  ],
                ]),
              ),
            ),
        ];

      case Arch.route ||
            Arch.journey ||
            Arch.laps ||
            Arch.interval ||
            Arch.basic:
        return const [];
    }
  }

  List<Widget> _zoneSection(P p) => r.zoneMinutes.length != 5
      ? const []
      : [Section('Heart-rate zones', Surface(child: _zoneFrame(p)))];

  List<double> _zoneFractions() {
    final total = r.zoneMinutes.fold<double>(0, (x, y) => x + y);
    if (total <= 0) return const [0, 0, 0, 0, 0];
    return [for (final z in r.zoneMinutes) z / total];
  }

  String _kg(double v) =>
      v == v.roundToDouble() ? '${v.round()} kg' : '${v.toStringAsFixed(1)} kg';

  // ─────────────────── SPLITS ───────────────────
  // "Splits" is whatever this archetype breaks into: kilometres for a run,
  // sets for a lift, rounds for HIIT, laps for a swim.
  List<Widget> _splits(BuildContext c, P p) {
    switch (arch) {
      case Arch.route || Arch.journey:
        if (r.splits.isEmpty) {
          return [
            const StatusCard(
              'No splits for this session',
              'Splits need a recorded distance.',
              icon: LucideIcons.list,
            ),
          ];
        }
        final fastest =
            r.splits.map((s) => s.sec).reduce((x, y) => x < y ? x : y);
        return [
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
            child: Column(children: [
              Row(children: [
                SizedBox(
                    width: 26,
                    child: Text('KM', style: F.over.copyWith(color: p.ink3))),
                SizedBox(
                    width: 46,
                    child: Text('PACE', style: F.over.copyWith(color: p.ink3))),
                const Expanded(child: SizedBox()),
                SizedBox(
                    width: 34,
                    child: Text('HR',
                        textAlign: TextAlign.right,
                        style: F.over.copyWith(color: p.ink3))),
              ]),
              const SizedBox(height: S.x2),
              for (var i = 0; i < r.splits.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: Row(children: [
                    SizedBox(
                        width: 26,
                        child: Text('${i + 1}',
                            style: F.cap.copyWith(color: p.ink3))),
                    SizedBox(
                        width: 46,
                        child: Text(pace(r.splits[i].sec),
                            style: F.cap.copyWith(
                                color: p.ink, fontWeight: FontWeight.w600))),
                    Expanded(
                        child: PaceBar(fastest / r.splits[i].sec, C.green)),
                    SizedBox(
                        width: 34,
                        child: Text(r.splits[i].avgHr?.toString() ?? '',
                            textAlign: TextAlign.right,
                            style: F.cap.copyWith(color: p.ink2))),
                  ]),
                ),
            ]),
          ),
        ];

      case Arch.strength:
        if (r.strength.isEmpty) {
          return [
            const StatusCard(
              'No sets logged',
              '0 sets logged.',
              icon: LucideIcons.dumbbell,
            ),
          ];
        }
        return [
          for (final key in r.strength.exercises) ...[
            Section(
              exerciseByKey(key)?.label ?? key,
              Surface(
                pad: const EdgeInsets.symmetric(horizontal: S.x4),
                child: Column(children: [
                  for (var i = 0;
                      i < r.strength.forExercise(key).length;
                      i++) ...[
                    _setRow(p, i + 1, r.strength.forExercise(key)[i]),
                    if (i < r.strength.forExercise(key).length - 1)
                      Divider(color: p.line, height: 1),
                  ],
                ]),
              ),
            ),
          ],
        ];

      case Arch.interval:
        if (r.rounds.isEmpty) {
          return [
            const StatusCard('No rounds recorded',
                '0 rounds logged.',
                icon: LucideIcons.timer),
          ];
        }
        // The heart-rate column exists only when the rounds carry one. A
        // header over four blank cells reads as "your heart stopped".
        final anyHr = r.rounds.any((x) => x.avgHr != null);
        return [
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
            child: Column(children: [
              Row(children: [
                SizedBox(
                    width: 34,
                    child: Text('R', style: F.over.copyWith(color: p.ink3))),
                Expanded(
                    child: Text('WORK', style: F.over.copyWith(color: p.ink3))),
                Expanded(
                    child: Text('REST', style: F.over.copyWith(color: p.ink3))),
                if (anyHr)
                  SizedBox(
                      width: 52,
                      child: Text('AVG BPM',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: F.over.copyWith(color: p.ink3))),
              ]),
              const SizedBox(height: S.x2),
              for (var i = 0; i < r.rounds.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: Row(children: [
                    SizedBox(
                      width: 34,
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: p.wash(C.red), borderRadius: R.rSm),
                        child: Text('${i + 1}',
                            style: F.over.copyWith(color: p.on(C.red))),
                      ),
                    ),
                    Expanded(
                        child: Text(clock(r.rounds[i].workSec),
                            style: F.cap.copyWith(color: p.ink))),
                    Expanded(
                        child: Text(clock(r.rounds[i].restSec),
                            style: F.cap.copyWith(color: p.ink3))),
                    if (anyHr)
                      SizedBox(
                        width: 52,
                        child: Text(r.rounds[i].avgHr?.toString() ?? '',
                            textAlign: TextAlign.right,
                            style: F.cap.copyWith(
                                color: p.ink, fontWeight: FontWeight.w600)),
                      ),
                  ]),
                ),
            ]),
          ),
        ];

      case Arch.laps:
        if (r.lapSecs.isEmpty) {
          return [
            const StatusCard('No laps counted',
                '0 laps tapped. No sensor can see a pool wall.',
                icon: LucideIcons.waves),
          ];
        }
        final fastest = r.lapSecs.reduce((x, y) => x < y ? x : y);
        return [
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
            child: Column(children: [
              Row(children: [
                SizedBox(
                    width: 34,
                    child: Text('LAP', style: F.over.copyWith(color: p.ink3))),
                SizedBox(
                    width: 52,
                    child: Text('TIME', style: F.over.copyWith(color: p.ink3))),
                Expanded(
                    child: Text('SPEED vs FASTEST',
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.over.copyWith(color: p.ink3))),
              ]),
              const SizedBox(height: S.x2),
              for (var i = 0; i < r.lapSecs.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: Row(children: [
                    SizedBox(
                        width: 34,
                        child: Text('${i + 1}',
                            style: F.cap.copyWith(color: p.ink3))),
                    SizedBox(
                        width: 52,
                        child: Text(clock(r.lapSecs[i]),
                            style: F.cap.copyWith(
                                color: p.ink, fontWeight: FontWeight.w600))),
                    Expanded(
                        child: PaceBar(
                            r.lapSecs[i] <= 0 ? 1 : fastest / r.lapSecs[i],
                            C.blue)),
                  ]),
                ),
            ]),
          ),
        ];

      // Unreachable — `_tabs` gives these archetypes no Splits tab to open.
      case Arch.flow || Arch.match || Arch.basic:
        return const [];
    }
  }

  Widget _setRow(P p, int n, LoggedSet s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: p.wash(C.purple), borderRadius: R.rSm),
            child: Text('$n', style: F.over.copyWith(color: p.on(C.purple))),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(
                s.loadKg == null
                    ? '${s.reps} reps · bodyweight'
                    : '${_kg(s.loadKg!)} × ${s.reps}',
                style: F.body.copyWith(color: p.ink)),
          ),
          if (s.rpe != null)
            Text('RPE ${s.rpe}', style: F.cap.copyWith(color: p.ink3)),
          if (s.volume != null) ...[
            const SizedBox(width: S.x3),
            Text('${grouped(s.volume!)} kg',
                style: F.cap
                    .copyWith(color: p.ink2, fontWeight: FontWeight.w600)),
          ],
        ]),
      );

  // ─────────────────── GRAPHS ───────────────────
  List<Widget> _graphs(BuildContext c, P p) {
    final series = <(String, String, Color, List<double?>)>[
      if (r.hr.length > 1) ('Heart rate', 'bpm', C.red, r.hr),
      if (r.elevationM.length > 1)
        ('Elevation', 'm', C.teal, r.elevationM),
    ];
    if (series.isEmpty) {
      return [
        StatusCard(
          'No series to plot',
          'This session recorded no per-minute streams.',
          fix: 'Check band connection',
          onFix: () => openProfile(c),
          icon: LucideIcons.chartLine,
        ),
      ];
    }
    return [
      for (final g in series)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x3),
          child: Surface(
            child: Builder(builder: (_) {
              final axis = AxisSpec.of(g.$4.whereType<double>());
              return ChartFrame(
                title: g.$1.toUpperCase(),
                unit: g.$2,
                height: 110,
                yAxis: axis,
                xLabels: ['Start', hms(r.duration)],
                series: g.$4,
                child: CustomPaint(
                    size: Size.infinite,
                    painter: LineChart(g.$4, p.on(g.$3),
                        axis: axis, t: animate(context, 1))),
              );
            }),
          ),
        ),
    ];
  }
}

class _MuscleRow extends StatelessWidget {
  final String group;
  final double v;
  const _MuscleRow(this.group, this.v);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final label = group[0].toUpperCase() + group.substring(1);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Flexible, not Spacer-only: a long muscle-group name at 2x text
          // scale leaves the percentage no room, and tabular digits are wider
          // than proportional ones.
          Flexible(
            child: Text(label,
                style: F.cap.copyWith(color: p.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const Spacer(),
          Text('${(v * 100).round()}%',
              style: F.cap.copyWith(
                  color: p.ink2,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: S.x1),
        PaceBar(v, C.purple),
      ]),
    );
  }
}

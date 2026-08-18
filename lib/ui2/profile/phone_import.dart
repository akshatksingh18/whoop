// Two reads out of the phone's health store, behind one row on Your data.
//
// They are on the same screen because they are the same promise: OpenStrap did
// not measure any of this. What differs is what each one is ALLOWED to become.
//
//   · Resting heart rate seeds a BASELINE — a centre and a spread — and never a
//     day. Another device's resting HR is on another device's scale, which is
//     exactly why it can shape "usual for you" and can never be a value on a
//     chart. No imported night, no back-filled readiness.
//   · Cuff, meter and thermometer readings are DISPLAY ONLY, with the source
//     app's name attached to every one. They are never blended into a composite
//     and never a training target — the moment someone trains a wrist→BP
//     mapping on an imported cuff series, this app is a regulated device that
//     is wrong. That guard is repeated at the import site on purpose.
//
// HRV is deliberately absent from both. iOS writes SDNN, Android RMSSD, and the
// app's own baseline key is fed from rmssd; mixing them is how a new user gets
// a confidently wrong first month, which is worse than the blank it replaces.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../health/health_measurement_import.dart';
import '../../health/health_profile_import.dart';
import '../../health/health_rhr_seed.dart';
import '../../health/health_workout_import.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'devices.dart' show formatDayTime;

/// Whichever store this platform has. Named, because "your phone" is not a
/// thing a user can go and check a permission on.
String get storeName => Platform.isIOS ? 'Apple Health' : 'Health Connect';

/// The kinds SD-12 imports, in the order they are shown, with the label and the
/// unit each is stored in.
const List<(String kind, String label)> kImportedKindLabels = [
  (kKindSystolic, 'Blood pressure, systolic'),
  (kKindDiastolic, 'Blood pressure, diastolic'),
  (kKindGlucose, 'Blood glucose'),
  (kKindBodyTemp, 'Body temperature'),
];

class PhoneImport extends StatefulWidget {
  const PhoneImport({super.key});

  @override
  State<PhoneImport> createState() => _PhoneImportState();
}

class _PhoneImportState extends State<PhoneImport> {
  bool _busy = false;
  String? _note;
  bool _noteFailed = false;

  ana.BaselineState? _seed;
  SeedComparison? _compare;

  /// Imported workouts, newest first, with a route flag each.
  List<(Map<String, dynamic> row, bool hasRoute)> _workouts = const [];

  /// Latest row per kind, newest first. Each carries its own `source`; a row
  /// without one is not renderable and never reaches here.
  final Map<String, Map<String, dynamic>> _latest = {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final compare = await RhrSeedImporter.compareAgainstBand();
    final latest = <String, Map<String, dynamic>>{};
    for (final (kind, _) in kImportedKindLabels) {
      final rows = await LocalDb.importedMeasurements(kind, limit: 1);
      if (rows.isNotEmpty) latest[kind] = rows.first;
    }
    // Only the most recent few: this is a receipt for what was imported, not a
    // workout history screen. The app already has one of those, and it is for
    // workouts this band measured.
    final rows = await LocalDb.importedWorkouts(limit: 8);
    final workouts = <(Map<String, dynamic>, bool)>[];
    for (final r in rows) {
      workouts.add((r, await LocalDb.sessionHasRoute(r['uuid'] as String)));
    }
    if (!mounted) return;
    setState(() {
      _compare = compare;
      _workouts = workouts;
      _latest
        ..clear()
        ..addAll(latest);
    });
  }

  Future<void> _run(Future<(String, bool)> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final (text, failed) = await job();
      if (mounted) {
        setState(() {
          _note = text;
          _noteFailed = failed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _note = 'Failed: $e';
          _noteFailed = true;
        });
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(String, bool)> _seedRhr() async {
    final importer = RhrSeedImporter();
    if (!await importer.requestPermission()) {
      return (
        '$storeName did not grant resting heart rate. Nothing was read.',
        true,
      );
    }
    final state = await importer.seed();
    if (state == null) {
      return (
        'Nothing usable came back. A store with no resting heart rate in it, '
            'or too few days to describe a range, cannot become a baseline.',
        true,
      );
    }
    if (mounted) setState(() => _seed = state);
    return (
      '${state.nValid} day${state.nValid == 1 ? '' : 's'} folded into a shadow '
          'baseline. No day was added to any chart.',
      false,
    );
  }

  Future<(String, bool)> _syncMeasurements() async {
    final importer = ImportedMeasurementImporter();
    if (!await importer.requestPermission()) {
      return (
        '$storeName did not grant those readings. Nothing was read.',
        true,
      );
    }
    final n = await importer.sync();
    return n == 0
        ? (
            'Nothing came back. $storeName holds no readings of these kinds, '
                'or none inside the window it will share.',
            false,
          )
        : (
            '$n reading${n == 1 ? '' : 's'} stored, each with the app that '
                'recorded it.',
            false,
          );
  }

  /// Read body metrics into the local profile.
  ///
  /// Goes through `AppState.updateProfile`, the only writer of `AppState.user`.
  /// The merge policy (weight and height win, age and sex only fill a gap)
  /// lives in `mergeHealthProfile` and is not re-decided here.
  Future<(String, bool)> _importProfile() async {
    final importer = HealthProfileImporter();
    if (!await importer.requestPermission()) {
      return ('$storeName did not grant those fields. Nothing was read.', true);
    }
    final snap = await importer.read();
    if (snap.isEmpty) {
      return (
        'Nothing came back. $storeName holds no height, weight'
            '${Platform.isIOS ? ', birthday' : ''} or sex for you — type them '
            'in on Edit profile instead.',
        false,
      );
    }
    if (!mounted) return ('', false);
    final app = context.read<AppState>();
    final changes = healthProfileChanges(app.user, snap);
    if (changes.isEmpty) {
      return (
        'Read ${snap.found.join(', ')}. Your profile already says the same '
            'thing, so nothing changed.',
        false,
      );
    }
    await app.updateProfile(mergeHealthProfile(app.user, snap));
    return ('Updated ${changes.join(', ')} from $storeName.', false);
  }

  Future<(String, bool)> _importWorkouts() async {
    final importer = HealthWorkoutImporter();
    if (!await importer.requestPermission()) {
      return ('$storeName did not grant workouts. Nothing was read.', true);
    }
    final res = await importer.sync();
    if (res.workouts == 0) {
      return (
        'Nothing came back. $storeName holds no workouts inside the window it '
            'will share.',
        false,
      );
    }
    final n = res.workouts;
    final route = !res.routesSupported
        // Stated every time rather than once in the body copy: this is the
        // moment the user is looking for their map, and "Android cannot" has
        // to arrive with the result, not near it.
        ? ' Health Connect will not share routes, so none have coordinates.'
        : res.withRoutes == 0
            ? ' None of them had a route recorded.'
            : ' ${res.withRoutes} came with a route.';
    return ('$n workout${n == 1 ? '' : 's'} listed.$route', false);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final seed = _seed;
    final cmp = _compare;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('From your phone'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  // ── seed-baselines ──────────────────────────────────────────
                  Section(
                    'A baseline, not days',
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Reads one thing: your resting heart rate, from '
                            '$storeName. It is folded into a centre and a '
                            'spread — what counts as usual for you — and then '
                            'held.',
                            style: F.body.copyWith(color: p.ink2, height: 1.4),
                          ),
                          const SizedBox(height: S.x3),
                          Text(
                            // Says what it does TODAY, which is nothing. The
                            // seed is deliberately read by no metric until it
                            // has been checked against the band; copy that
                            // implied it was already shaping readiness would be
                            // promising a number this screen does not produce.
                            'Nothing in the app uses it yet. It waits for this '
                            'band’s own first 14 nights and is compared '
                            'against them below — a phone that disagrees with '
                            'the band is a liability, not a head start.',
                            style: F.cap.copyWith(color: p.ink3, height: 1.5),
                          ),
                          const SizedBox(height: S.x3),
                          Text(
                            'It never becomes a value either way. No night '
                            'appears on the sleep chart, no day gets a '
                            'readiness score, and nothing is written back.',
                            style: F.cap.copyWith(color: p.ink3, height: 1.5),
                          ),
                          const SizedBox(height: S.x4),
                          BigButton(
                            'Read resting heart rate',
                            icon: LucideIcons.heartPulse,
                            color: C.blue,
                            soft: true,
                            onTap: _busy ? null : () => _run(_seedRhr),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (seed != null) ...[
                    const SizedBox(height: S.x3),
                    MetricRow(
                      LucideIcons.heartPulse,
                      C.blue,
                      'Seeded centre',
                      '${seed.baseline.round()}',
                      unit: 'bpm',
                      sub:
                          '${seed.nValid} days from $storeName · '
                          'spread ${seed.spread.toStringAsFixed(1)}',
                    ),
                  ],
                  // THE GATE. Null until the band has its own 14 nights — and a
                  // comparison from three nights would be a false all-clear, so
                  // there is nothing to draw until then.
                  if (cmp != null) ...[
                    const SizedBox(height: S.x3),
                    StatusCard(
                      cmp.disagrees
                          ? 'The phone and the band disagree'
                          : 'The phone and the band agree',
                      cmp.disagrees
                          ? '$storeName puts your resting heart rate '
                                '${cmp.deltaBpm.abs().toStringAsFixed(1)} bpm '
                                '${cmp.deltaBpm > 0 ? 'higher' : 'lower'} than '
                                'this band measures it over '
                                '${cmp.bandNights} nights. They are not describing '
                                'the same thing, so the seed stays where it is and '
                                'is used for nothing.'
                          : 'Over ${cmp.bandNights} nights the band lands within '
                                '${cmp.deltaBpm.abs().toStringAsFixed(1)} bpm of '
                                'what $storeName said. The seed is still only a '
                                'centre and a spread.',
                      icon: cmp.disagrees
                          ? LucideIcons.triangleAlert
                          : LucideIcons.check,
                    ),
                  ],
                  const SizedBox(height: S.x6),
                  // ── SD-12 ───────────────────────────────────────────────────
                  Section(
                    'Measured by something else',
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'A cuff, a glucose meter, a thermometer. This band '
                            'cannot measure any of them, which is the entire '
                            'reason they are worth showing — and why the app '
                            'that recorded each reading is named beside it.',
                            style: F.body.copyWith(color: p.ink2, height: 1.4),
                          ),
                          const SizedBox(height: S.x3),
                          Text(
                            'Shown as they arrived. Never averaged into one of '
                            'this app’s own numbers, never used to teach it to '
                            'guess one from the wrist.',
                            style: F.cap.copyWith(color: p.ink3, height: 1.5),
                          ),
                          const SizedBox(height: S.x4),
                          BigButton(
                            'Read from $storeName',
                            icon: LucideIcons.stethoscope,
                            color: C.teal,
                            soft: true,
                            onTap: _busy ? null : () => _run(_syncMeasurements),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final (kind, label) in kImportedKindLabels)
                    if (_latest[kind] case final row?) ...[
                      const SizedBox(height: S.x3),
                      MetricRow(
                        LucideIcons.clipboardList,
                        C.teal,
                        label,
                        _formatValue(row['value']),
                        unit: '${row['unit'] ?? ''}',
                        sub: _sourceLine(row),
                      ),
                    ],
                  const SizedBox(height: S.x6),
                  // ── body metrics → local profile ────────────────────────────
                  Section(
                    'Your body',
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Height and weight from $storeName'
                            '${Platform.isIOS ? ', plus your birthday and sex' : ''}'
                            '. Weight is the one that matters: the calorie and '
                            'BMR estimates read it, and a figure typed in once '
                            'a year quietly gets more wrong every month.',
                            style: F.body.copyWith(color: p.ink2, height: 1.4),
                          ),
                          const SizedBox(height: S.x3),
                          Text(
                            // The asymmetry, said on the platform it affects.
                            // Health Connect has no characteristic record for
                            // either — it is not a permission we could ask for.
                            Platform.isIOS
                                ? 'Height and weight are taken from the store '
                                    'each time. Your age and sex are only '
                                    'filled in if the profile has none — '
                                    'neither drifts, so a value already there '
                                    'was your choice.'
                                : 'Health Connect has no birthday and no sex '
                                    'to read — no app can. Set those on Edit '
                                    'profile; height and weight come from '
                                    'here.',
                            style: F.cap.copyWith(color: p.ink3, height: 1.5),
                          ),
                          const SizedBox(height: S.x4),
                          BigButton(
                            'Read height and weight',
                            icon: LucideIcons.scale,
                            color: C.purple,
                            soft: true,
                            onTap: _busy ? null : () => _run(_importProfile),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x6),
                  // ── workouts + routes ───────────────────────────────────────
                  Section(
                    'Workouts recorded elsewhere',
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Runs, rides and sessions another app recorded'
                            '${Platform.isIOS ? ', with their routes' : ''}. '
                            'They are listed and drawn, each named with the '
                            'app that recorded it.',
                            style: F.body.copyWith(color: p.ink2, height: 1.4),
                          ),
                          const SizedBox(height: S.x3),
                          Text(
                            // The ceiling, stated before the button rather than
                            // discovered afterwards when a strain score does
                            // not move.
                            'They stay separate from workouts this band '
                            'measured. An imported workout never adds to your '
                            'strain, never changes a day’s score, and never '
                            'becomes a personal record — this app did not '
                            'measure it and cannot vouch for it.',
                            style: F.cap.copyWith(color: p.ink3, height: 1.5),
                          ),
                          if (!Platform.isIOS) ...[
                            const SizedBox(height: S.x3),
                            Text(
                              'Routes are not included on Android. Health '
                              'Connect keeps them behind a separate, '
                              'restricted permission that this app has not '
                              'applied for, so the workouts arrive without '
                              'coordinates.',
                              style: F.cap.copyWith(color: p.ink3, height: 1.5),
                            ),
                          ],
                          const SizedBox(height: S.x4),
                          BigButton(
                            'Read workouts',
                            icon: LucideIcons.footprints,
                            color: C.orange,
                            soft: true,
                            onTap: _busy ? null : () => _run(_importWorkouts),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final (row, hasRoute) in _workouts) ...[
                    const SizedBox(height: S.x3),
                    MetricRow(
                      hasRoute ? LucideIcons.map : LucideIcons.activity,
                      C.orange,
                      _workoutTitle(row),
                      _workoutValue(row),
                      unit: 'min',
                      sub: _workoutSub(row, hasRoute),
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: S.x6),
                    Center(
                      child: CircularProgressIndicator(color: p.on(C.blue)),
                    ),
                  ],
                  if (_note != null && _note!.isNotEmpty) ...[
                    const SizedBox(height: S.x5),
                    StatusCard(
                      _noteFailed ? 'That did not work' : 'Done',
                      _note!,
                      icon: _noteFailed
                          ? LucideIcons.triangleAlert
                          : LucideIcons.check,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "118" / "5.4". One decimal only when the value has one — a cuff reading
/// printed as `118.0` reads like a precision nobody claimed.
String _formatValue(Object? v) {
  final d = (v as num?)?.toDouble();
  if (d == null) return '';
  return d == d.roundToDouble() ? '${d.round()}' : d.toStringAsFixed(1);
}

/// "RUNNING" → "Running". The health store's own enum name, title-cased and
/// de-underscored. Not mapped through a lookup table on purpose: a map would
/// need an entry for every one of ~80 activity types and would print a blank
/// for whatever the next OS version adds.
String _workoutTitle(Map<String, dynamic> row) {
  final raw = (row['kind'] as String?)?.trim() ?? '';
  if (raw.isEmpty) return 'Workout';
  return raw
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

/// Duration in whole minutes. The only figure shown large, because it is the
/// one the source app cannot get wrong.
String _workoutValue(Map<String, dynamic> row) {
  final start = (row['start_ts'] as num?)?.toInt();
  final end = (row['end_ts'] as num?)?.toInt();
  if (start == null || end == null || end <= start) return '';
  return '${((end - start) / 60).round()}';
}

/// "Strava · Thu 4 Sep, 07:12 · 8.2 km · route". Distance and energy appear
/// only when the store recorded them — an absent distance is absent, and a
/// "0.0 km" under a run is a wrong number, not a missing one.
String _workoutSub(Map<String, dynamic> row, bool hasRoute) {
  final src = (row['source'] as String?)?.trim();
  final ts = (row['start_ts'] as num?)?.toInt();
  final dist = (row['distance_m'] as num?)?.toDouble();
  final kcal = (row['energy_kcal'] as num?)?.toDouble();
  return [
    if (src != null && src.isNotEmpty) src,
    if (ts != null)
      formatDayTime(DateTime.fromMillisecondsSinceEpoch(ts * 1000)),
    if (dist != null && dist > 0) '${(dist / 1000).toStringAsFixed(1)} km',
    if (kcal != null && kcal > 0) '${kcal.round()} kcal',
    if (hasRoute) 'route',
  ].join(' · ');
}

/// "Omron Connect · Thu 4 Sep, 07:12". The source is not optional decoration:
/// a reading this app did not take, shown without saying who did, is a reading
/// this app is implicitly claiming.
String _sourceLine(Map<String, dynamic> row) {
  final src = (row['source'] as String?)?.trim();
  final ts = (row['ts'] as num?)?.toInt();
  final when = ts == null
      ? null
      : formatDayTime(DateTime.fromMillisecondsSinceEpoch(ts * 1000));
  return [if (src != null && src.isNotEmpty) src, ?when].join(' · ');
}

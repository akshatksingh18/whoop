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

import '../../data/db.dart';
import '../../health/health_measurement_import.dart';
import '../../health/health_rhr_seed.dart';
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
    if (!mounted) return;
    setState(() {
      _compare = compare;
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

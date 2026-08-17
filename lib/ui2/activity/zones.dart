// HEART-RATE ZONES — the ceiling, the two anchors, and (only sometimes) the
// 28-day distribution. TS-03 / TS-04 / TS-05.
//
// THE SENTENCE IS THE FEATURE. Zone edges are percentages of a ceiling, and
// this app has two completely different ceilings depending on what it has seen:
// a number MEASURED on the wrist, or `208 − 0.7·age`. Those are materially
// different claims and the screen says which one it is every time. The number
// itself never changes its wording either: "highest we've seen" with the date
// and the session, never "your max HR", and nothing anywhere invites a
// max-effort test.
//
// WHY THE DISTRIBUTION IS OFTEN ABSENT. A three-bar "most of your minutes are
// in the grey middle" read off bands built on 220−age is manufactured — the
// bars would be a picture of an arithmetic assumption, not of training. So it
// is GATED, in the repository, not captioned: no observed ceiling and no
// measured resting HR means no chart at all. It appears about four weeks after
// the band first sees you go hard, and not before.
//
// WHAT THIS SCREEN WILL BE ACCUSED OF. A very low resting heart rate makes
// zone 1 enormous — 48 → 184 bpm puts Z1 at 48–116. That is the reserve
// arithmetic working exactly as intended and it will be reported as a bug, so
// the copy names it before the user does.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/local_repository.dart';
import '../screens/home_screen.dart' show repoOf;
import '../screens/metric_detail.dart' show detailScaffold;
import '../ui2.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// 'YYYY-MM-DD' → '3 Aug'. Returns the raw label if it does not parse — a date
/// we cannot format is still better than dropping the attribution.
String _prettyDay(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${_months[d.month - 1]}';
}

/// One zone row as the repository serves it.
typedef ZoneRow = ({int zone, String name, int lo, int hi});

class ZonesData {
  /// The observed ceiling: bpm, the day it was held, and the session it came
  /// from. Null while the band has never seen a qualifying effort.
  final int? ceilingBpm;
  final String? ceilingDate;
  final String? ceilingSession;

  /// `karvonen` (both anchors measured) · `observed` (ceiling measured, resting
  /// history still short) · `tanaka` (the age estimate) · null (no ceiling).
  final String? source;
  final int? maxHr;

  /// The 28-day median resting HR the reserve was measured from, and how many
  /// nights back it.
  final int? restingHr;
  final int restingDays, restingMinDays;

  final List<ZoneRow> zones;

  /// TS-05. Null whenever the bars would be built on the age estimate, on too
  /// few sessions, or on sessions with no per-minute trace.
  final List<int>? distMinutes;
  final int distSessions, distEasy, distModerate, distHard;
  final String? distShape;

  const ZonesData({
    this.ceilingBpm,
    this.ceilingDate,
    this.ceilingSession,
    this.source,
    this.maxHr,
    this.restingHr,
    this.restingDays = 0,
    this.restingMinDays = 14,
    this.zones = const [],
    this.distMinutes,
    this.distSessions = 0,
    this.distEasy = 0,
    this.distModerate = 0,
    this.distHard = 0,
    this.distShape,
  });

  bool get measured => source == 'karvonen';

  static ZonesData parse(Map<String, dynamic> z) {
    final c = z['ceiling'];
    final d = z['distribution'];
    final mins = d is Map ? d['minutes'] : null;
    return ZonesData(
      ceilingBpm: c is Map ? (c['bpm'] as num?)?.round() : null,
      ceilingDate: c is Map ? c['date'] as String? : null,
      ceilingSession: c is Map ? c['session_type'] as String? : null,
      source: z['source'] as String?,
      maxHr: (z['max_hr'] as num?)?.round(),
      restingHr: (z['resting_hr'] as num?)?.round(),
      restingDays: (z['resting_days'] as num?)?.toInt() ?? 0,
      restingMinDays: (z['resting_min_days'] as num?)?.toInt() ?? 14,
      zones: [
        for (final r in (z['zones'] as List? ?? const []).whereType<Map>())
          (
            zone: (r['zone'] as num).toInt(),
            name: r['name'] as String? ?? '',
            lo: (r['lo'] as num).round(),
            hi: (r['hi'] as num).round(),
          ),
      ],
      distMinutes: mins is List && mins.length == 5
          ? [for (final v in mins) (v as num).round()]
          : null,
      distSessions: d is Map ? (d['sessions'] as num?)?.toInt() ?? 0 : 0,
      distEasy: d is Map ? (d['easy_min'] as num?)?.toInt() ?? 0 : 0,
      distModerate: d is Map ? (d['moderate_min'] as num?)?.toInt() ?? 0 : 0,
      distHard: d is Map ? (d['hard_min'] as num?)?.toInt() ?? 0 : 0,
      distShape: d is Map ? d['shape'] as String? : null,
    );
  }

  static Future<ZonesData> load(LocalRepository repo) async =>
      parse(await repo.getZones());
}

class ZonesDetail extends StatefulWidget {
  /// Preloaded, for goldens. Null means read the repo on open.
  final ZonesData? data;
  const ZonesDetail({super.key, this.data});

  @override
  State<ZonesDetail> createState() => _ZonesDetailState();
}

class _ZonesDetailState extends State<ZonesDetail> {
  ZonesData? _d;
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
      final d = await ZonesData.load(repo);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = _d ?? const ZonesData();
    return detailScaffold(c, 'Heart-rate zones', [
      if (_loading && _d == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else ...[
        _ceiling(p, d),
        Section('Your zones', _zones(p, d)),
        ..._distribution(p, d),
      ],
    ]);
  }

  // ── the ceiling, said the only way it can honestly be said ─────────────────
  Widget _ceiling(P p, ZonesData d) {
    final bpm = d.ceilingBpm;
    if (bpm == null) {
      return const StatusCard(
        'No measured ceiling yet',
        'The highest heart rate we can stand behind is one the band HELD for '
            'at least 15 seconds while you were moving — a one-second spike is '
            'a sleeve dragging over the sensor, not a heart rate. Until a '
            'session produces one, the zones below come off your age.',
        fix: 'Wear the band for your normal hard sessions',
        icon: LucideIcons.heartPulse,
      );
    }
    final where = [
      if (d.ceilingDate != null) 'on ${_prettyDay(d.ceilingDate!)}',
      if (d.ceilingSession != null) 'during ${d.ceilingSession!.toLowerCase()}',
    ].join(', ');
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HIGHEST WE HAVE SEEN', style: F.over.copyWith(color: p.ink3)),
          const SizedBox(height: S.x2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$bpm', style: F.n34.copyWith(color: p.on(C.red))),
              const SizedBox(width: S.x2),
              Text('bpm', style: F.body.copyWith(color: p.ink3)),
            ],
          ),
          if (where.isNotEmpty) ...[
            const SizedBox(height: S.x1),
            Text(
              where[0].toUpperCase() + where.substring(1),
              style: F.body.copyWith(color: p.ink2),
            ),
          ],
          const SizedBox(height: S.x3),
          Text(
            'This is the highest we have measured, not a limit. If you have '
            'never gone truly hard with the band on, it is lower than what '
            'you can actually reach, and it will keep creeping up as it sees '
            'harder efforts. Do not go and test it.',
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── the edges, and the two numbers they were built from ────────────────────
  Widget _zones(P p, ZonesData d) {
    if (d.zones.isEmpty) {
      return const StatusCard(
        'No zones yet',
        'Zone edges are percentages of a maximum heart rate. Without your age '
            'or a strap we have calibrated a ceiling for, there is no ceiling '
            'to take a percentage of.',
        fix: 'Add your age in Profile',
        icon: LucideIcons.activity,
      );
    }
    return Surface(
      child: Column(
        children: [
          for (final z in d.zones) ...[
            if (z.zone > 1) Divider(height: S.x5, color: p.line),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 28,
                  decoration: BoxDecoration(
                    color: ZoneBar.cols(p)[z.zone - 1],
                    borderRadius: R.rSm,
                  ),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Z${z.zone} · ${z.name}',
                        style: F.body.copyWith(color: p.ink),
                      ),
                    ],
                  ),
                ),
                Text(
                  z.zone == 5 ? '${z.lo}+' : '${z.lo}–${z.hi}',
                  style: F.n17.copyWith(color: p.ink2),
                ),
                const SizedBox(width: S.x2),
                Text('bpm', style: F.cap.copyWith(color: p.ink3)),
              ],
            ),
          ],
          const SizedBox(height: S.x4),
          Text(
            _anchorCopy(d),
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// WHERE THESE EDGES CAME FROM — the whole point of the screen. Three
  /// different claims, three different sentences, never a shared hedge.
  String _anchorCopy(ZonesData d) {
    final max = d.maxHr;
    switch (d.source) {
      case 'karvonen':
        return 'Each edge is a percentage of the gap between your resting heart '
            'rate (${d.restingHr}, the median of your last ${d.restingDays} '
            'nights) and the highest we have seen ($max). Both are numbers the '
            'band measured on you. A low resting heart rate makes zone 1 very '
            'wide — that is the arithmetic, not a fault. These are still bands '
            'by convention, not your thresholds: nothing here can measure where '
            'your aerobic or lactate threshold actually sits.';
      case 'observed':
        return 'Each edge is a percentage of the highest heart rate we have '
            'seen ($max). Once ${d.restingMinDays} nights of resting heart rate '
            'exist (you have ${d.restingDays}), the edges move to the gap '
            'between that and your resting rate, which is the more personal of '
            'the two. Bands are a convention, not your thresholds.';
      case 'tanaka':
        return 'Each edge is a percentage of $max bpm — ESTIMATED FROM YOUR AGE '
            'and your strap, not measured on you. The estimate is a population '
            'average and can be 20 bpm out either way for one person, so treat '
            'these edges as rough. They become measured edges on their own once '
            'the band sees a hard enough session.';
      default:
        return 'Zone edges are percentages of a maximum heart rate.';
    }
  }

  // ── TS-05 — drawn only when both anchors were measured ─────────────────────
  List<Widget> _distribution(P p, ZonesData d) {
    final mins = d.distMinutes;
    if (mins == null) {
      // NOT a chart with a caveat. The absence IS the honest state, so it says
      // what would have to be true for the chart to mean anything.
      return [
        Section(
          'Where your intensity went',
          StatusCard(
            'Not shown yet',
            d.measured
                ? 'It needs about a month of recorded sessions to describe a '
                      'pattern rather than a fortnight of noise, each with the '
                      'per-minute heart rate we keep for them.'
                : 'These bars would be a picture of the age estimate, not of '
                      'your training. They appear once the zone edges above come '
                      'from a measured ceiling and a measured resting rate.',
            icon: LucideIcons.chartColumn,
          ),
        ),
      ];
    }
    final total = mins.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return const [];
    return [
      Section(
        'Where your intensity went',
        Surface(
          child: ChartFrame(
            title: 'SESSION MINUTES, LAST 28 DAYS',
            unit: 'minutes',
            height: 10,
            legend: [
              for (var i = 0; i < 5; i++)
                ('Z${i + 1} · ${mins[i]}m', ZoneBar.cols(p)[i]),
            ],
            footnote: _shapeCopy(d),
            child: CustomPaint(
              size: Size.infinite,
              painter: ZoneBar([for (final v in mins) v / total], p),
            ),
          ),
        ),
      ),
    ];
  }

  /// A DESCRIPTION of the shape, with no target attached.
  ///
  /// Deliberately no 80/20: that literature is trained endurance athletes
  /// against lab-defined thresholds, and these are %HRR bands off a ceiling a
  /// wrist sensor happened to catch. Naming the shape is a mirror; calling a
  /// share of it correct would be a prescription we cannot support.
  String _shapeCopy(ZonesData d) {
    final shape = switch (d.distShape) {
      'pyramidal' =>
        'Most of your minutes are easy, fewer in the middle, '
            'fewest hard — a pyramid.',
      'polarised' =>
        'Most of your minutes are easy and the rest are hard, '
            'with little in between — polarised.',
      'middle-heavy' =>
        'Most of your minutes sit in the middle rather than '
            'easy or hard.',
      _ => '',
    };
    return '$shape ${d.distEasy} min easy, ${d.distModerate} moderate, '
        '${d.distHard} hard, over ${d.distSessions} recorded sessions. A '
        'description, not a target — there is no share of these that is '
        'correct, and the bands are a convention rather than your measured '
        'thresholds.';
  }
}

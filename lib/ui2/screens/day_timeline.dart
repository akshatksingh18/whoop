// DAY TIMELINE — what happened, in the order it happened.
//
// Every screen in this app answers "how much" for one number over many days.
// None of them answered "what was going on around then", which is the question
// somebody asks the moment a line moves: the workout, the nap, the coffee at
// nine, the night the band spent on the charger. The pieces were all on disk
// and all on the same axis already — `getDayTimeline` joins HR, HRV, sleep,
// naps, sessions and events; `getDayWear` holds the off-wrist segments; meals,
// doses and timed journal fields each carry their own clock — and nothing put
// them in one column.
//
// WHAT IT IS NOT. It is not an explanation. Two things next to each other on a
// clock is adjacency, and adjacency is not cause — a timeline is the most
// tempting place in the app to imply otherwise, so the page states the limit
// in the same words the journal findings use and never orders items by
// anything but time.
//
// A THING WITH NO CLOCK DOES NOT GET A PLACE ON ONE. A journal note is stored
// per DAY with no time, and so is a meal logged without one. Placing those
// anywhere on the axis — midnight, noon, the middle — would be inventing the
// one fact the entry is missing. They go in their own block underneath, which
// says what it is.

import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../data/journal_fields.dart';
import '../../data/local_repository.dart';
import '../../data/med_store.dart';
import '../../data/nutrition_store.dart';
import '../activity/catalogue.dart' show activityByName;
import '../ui2.dart';
import 'home_screen.dart' show clockOfTs, repoOf;
import 'metric_detail.dart' show dayNavRow, detailScaffold, pickDay;

/// One thing that happened, at a time it is known to have happened at.
@immutable
class Moment {
  const Moment({
    required this.at,
    required this.title,
    required this.icon,
    this.color,
    this.until,
    this.detail = '',
  });

  /// Epoch seconds. The ONLY sort key — nothing on this page is ranked.
  final int at;

  /// Epoch seconds when this was a span rather than an instant.
  final int? until;

  final String title;
  final String detail;
  final IconData icon;

  /// The accent this line is drawn in, or NULL for a fact about the band
  /// rather than about the person — the charger, the restart, the wrist it was
  /// not on. Those render in muted ink, because a colour is a claim that the
  /// row belongs to a domain and none of them do.
  final Color? color;
}

/// Something that was logged for this day and carries no time of day. Kept
/// apart from [Moment] by the type, so it cannot accidentally be placed.
@immutable
class DayNote {
  const DayNote(this.title, this.detail, this.icon);
  final String title, detail;
  final IconData icon;
}

/// Band events worth a line. Everything else the strap emits is about the
/// strap — bonds, flash writes, sync bookkeeping — and belongs on Devices, not
/// in somebody's day.
const _events = <int, (String, IconData)>{
  7: ('On the charger', LucideIcons.batteryCharging),
  8: ('Off the charger', LucideIcons.batteryFull),
  14: ('You double-tapped the band', LucideIcons.hand),
  15: ('The band restarted', LucideIcons.rotateCw),
  21: ('Battery pack attached', LucideIcons.batteryCharging),
  22: ('Battery pack removed', LucideIcons.battery),
  57: ('Alarm went off', LucideIcons.alarmClock),
};

/// An off-wrist gap shorter than this is a dropout, not an event in a day.
/// Listing every one of them would bury the four that mean something under
/// forty that mean the strap moved.
const int kMinOffWristMin = 15;

String _dur(num? minutes) {
  if (minutes == null) return '';
  final m = minutes.round();
  return m < 60 ? '${m}m' : '${m ~/ 60}h ${m % 60}m';
}

String _span(int from, int? to) =>
    to == null ? clockOfTs(from) : '${clockOfTs(from)} – ${clockOfTs(to)}';

/// THE JOIN. Pure, so the ordering and the placement rules are testable
/// without a database or a frame.
///
/// [timeline] is `getDayTimeline`, [wear] is `getDayWear`. Everything else is
/// one store each. A source that returned nothing simply contributes nothing —
/// there is no placeholder for a domain the user does not use.
List<Moment> dayMoments({
  required Map<String, dynamic> timeline,
  Map<String, dynamic> wear = const {},
  List<FoodEntry> meals = const [],
  List<({String label, int at})> doses = const [],
  Map<String, JournalMetricValue> journal = const {},
  List<JournalFieldSpec> fields = const [],
}) {
  final out = <Moment>[];
  int? asInt(Object? v) => (v as num?)?.toInt();

  // Sleep. The onset normally sits in the PREVIOUS calendar day — a day's
  // sleep is the night that ended that morning — so it sorts to the top and
  // reads as what it is: you were already asleep when this day started.
  for (final s in (timeline['sleep'] as List?) ?? const []) {
    if (s is! Map) continue;
    final on = asInt(s['onset_ts']), off = asInt(s['wake_ts']);
    if (on == null || off == null) continue;
    out.add(Moment(
      at: on,
      until: off,
      title: 'Asleep',
      detail: '${_span(on, off)} · ${_dur((off - on) / 60)}',
      icon: LucideIcons.moon,
      color: C.blue,
    ));
  }

  for (final n in (timeline['naps'] as List?) ?? const []) {
    if (n is! Map) continue;
    final on = asInt(n['start']), off = asInt(n['end']);
    if (on == null) continue;
    out.add(Moment(
      at: on,
      until: off,
      title: 'Nap',
      detail: '${_span(on, off)} · ${_dur(n['duration_min'] as num?)}',
      icon: LucideIcons.bedDouble,
      color: C.indigo,
    ));
  }

  for (final s in (timeline['sessions'] as List?) ?? const []) {
    if (s is! Map) continue;
    final on = asInt(s['start_ts']);
    if (on == null) continue;
    final type = s['type']?.toString();
    final act = activityByName(type);
    final bits = <String>[
      _span(on, asInt(s['end_ts'])),
      if (s['duration_min'] != null) _dur(s['duration_min'] as num?),
      if (s['avg_hr'] != null) '${s['avg_hr']} bpm avg',
    ];
    out.add(Moment(
      at: on,
      until: asInt(s['end_ts']),
      title: act?.name ?? (type ?? 'Workout').replaceAll('_', ' '),
      detail: bits.join(' · '),
      icon: act?.icon ?? LucideIcons.dumbbell,
      color: act?.color ?? C.orange,
    ));
  }

  // The band off the wrist. This is the single most useful line on the page on
  // most people's days, because it is the reason the rest of the day is empty
  // — and the segments already carry the exact clock times.
  for (final w in (wear['segments'] as List?) ?? const []) {
    if (w is! Map || w['on'] == true) continue;
    final on = asInt(w['start']), off = asInt(w['end']);
    final len = (w['len_min'] as num?) ?? (on != null && off != null ? (off - on) / 60 : null);
    if (on == null || len == null || len < kMinOffWristMin) continue;
    out.add(Moment(
      at: on,
      until: off,
      title: 'Band off your wrist',
      detail: '${_span(on, off)} · ${_dur(len)}',
      icon: LucideIcons.watch,
    ));
  }

  // The day's extremes. NOT anomalies — the highest and lowest reading a day
  // has is arithmetic, and calling it unusual would be a claim the number does
  // not support. What it is good for is a time to look at.
  final highs = timeline['highs'];
  if (highs is Map) {
    for (final e in const [
      ('peak_hr', 'Highest heart rate', LucideIcons.trendingUp),
      ('low_hr', 'Lowest heart rate', LucideIcons.trendingDown),
    ]) {
      final h = highs[e.$1];
      final t = h is Map ? asInt(h['t']) : null;
      final v = h is Map ? h['v'] as num? : null;
      if (t == null || v == null) continue;
      out.add(Moment(
        at: t,
        title: e.$2,
        detail: '${v.round()} bpm at ${clockOfTs(t)}',
        icon: e.$3,
        color: C.red,
      ));
    }
  }

  // Events, de-duplicated: the strap delivers the same (id, ts) up to four
  // times, and a day with the charger on it should not read as four chargers.
  final seen = <String>{};
  for (final e in (timeline['events'] as List?) ?? const []) {
    if (e is! Map) continue;
    final id = asInt(e['event_id']), t = asInt(e['ts']);
    final def = id == null ? null : _events[id];
    if (def == null || t == null || !seen.add('$id/$t')) continue;
    out.add(Moment(
      at: t,
      title: def.$1,
      detail: clockOfTs(t),
      icon: def.$2,
    ));
  }

  for (final m in meals) {
    final t = m.atTs;
    if (t == null) continue;
    final kcal = m.kcal;
    out.add(Moment(
      at: t,
      title: m.label.isEmpty ? m.meal : m.label,
      detail: [
        clockOfTs(t),
        if (m.meal.isNotEmpty) m.meal,
        // A bare occasion is complete as a log. It just has no energy on it,
        // and printing "0 kcal" for one is the fabrication this app refuses.
        if (kcal != null) '${kcal.round()} kcal',
      ].join(' · '),
      icon: LucideIcons.utensils,
      color: C.domFood,
    ));
  }

  for (final d in doses) {
    out.add(Moment(
      at: d.at,
      title: d.label,
      detail: 'Taken at ${clockOfTs(d.at)}',
      icon: LucideIcons.pill,
      color: C.purple,
    ));
  }

  // Timed journal fields — caffeine and alcohol carry the minute they last
  // landed, which is the sleep-relevant fact about both.
  final dayStart = asInt(timeline['day_start']);
  final specs = {for (final f in fields) f.key: f};
  journal.forEach((key, v) {
    final min = v.atMinuteOfDay;
    if (min == null || dayStart == null) return;
    final spec = specs[key];
    final n = v.value == v.value.roundToDouble()
        ? v.value.round().toString()
        : v.value.toStringAsFixed(1);
    out.add(Moment(
      at: dayStart + min * 60,
      title: spec?.label ?? key.replaceAll('_', ' '),
      // "last one at" is the stored meaning, and saying just "at" would turn a
      // total plus one timestamp into a single event that never happened.
      detail: '$n${spec == null || spec.unit.isEmpty ? '' : ' ${spec.unit}'} '
          '· last at ${clockOfTs(dayStart + min * 60)}',
      icon: LucideIcons.notebookPen,
      color: C.domMind,
    ));
  });

  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Logged for the day, with no time on it. Same sources, opposite branch.
List<DayNote> dayNotes({
  List<FoodEntry> meals = const [],
  Map<String, JournalMetricValue> journal = const {},
  List<JournalFieldSpec> fields = const [],
  List<Map<String, dynamic>> journalRows = const [],
}) {
  final out = <DayNote>[];
  for (final r in journalRows) {
    final note = (r['note'] as String?)?.trim() ?? '';
    // `tags_json`, not `tags` — the column holds a JSON list and a reader that
    // asked for the wrong name got null and silently dropped every tagged day
    // whose note was empty.
    final tags = <String>[];
    try {
      final j = jsonDecode((r['tags_json'] as String?) ?? '[]');
      if (j is List) tags.addAll([for (final t in j) t.toString()]);
    } catch (_) {/* a malformed row loses its tags, not the note */}
    if (note.isEmpty && tags.isEmpty) continue;
    out.add(DayNote(
      note.isEmpty ? 'Tagged' : note,
      tags.join(' · '),
      LucideIcons.notebookPen,
    ));
  }
  final specs = {for (final f in fields) f.key: f};
  journal.forEach((key, v) {
    if (v.atMinuteOfDay != null) return;
    final spec = specs[key];
    final n = v.value == v.value.roundToDouble()
        ? v.value.round().toString()
        : v.value.toStringAsFixed(1);
    out.add(DayNote(
      spec?.label ?? key.replaceAll('_', ' '),
      '$n${spec == null || spec.unit.isEmpty ? '' : ' ${spec.unit}'}',
      LucideIcons.clipboardList,
    ));
  });
  for (final m in meals) {
    if (m.atTs != null) continue;
    out.add(DayNote(
      m.label.isEmpty ? m.meal : m.label,
      [
        if (m.meal.isNotEmpty) m.meal,
        if (m.kcal != null) '${m.kcal!.round()} kcal',
      ].join(' · '),
      LucideIcons.utensils,
    ));
  }
  return out;
}

// ═══════════════════ the screen ═══════════════════

class TimelineData {
  const TimelineData({
    this.day,
    this.days = const [],
    this.moments = const [],
    this.notes = const [],
  });

  final String? day;

  /// Every derived day, newest first — what [DayNav] steers over.
  final List<String> days;
  final List<Moment> moments;
  final List<DayNote> notes;

  static Future<TimelineData> load(LocalRepository repo, {String? want}) async {
    final days = await repo.availableDays();
    final today = await repo.getToday();
    final day = pickDay(
        days, want, (today['status'] as Map?)?['today_day']?.toString());
    if (day == null) return TimelineData(days: days);

    final timeline = await repo.getDayTimeline(day);
    final wear = await repo.getDayWear(day);
    final fields = await repo.getJournalFields();
    final journal = await repo.getJournalMetrics(day);
    final db = await LocalDb.instance;
    final meals = await NutritionDb.entriesForDay(db, day);
    final notes = await LocalDb.journalRows(sinceDaysEpoch: day);

    // Doses: one row per (medication, slot), and only the ones actually taken
    // carry a clock. A skipped dose is a real fact with no time attached, so it
    // is not on the axis — see the note at the top of this file.
    final defs = {for (final d in await MedDb.defs(db, activeOnly: false)) d.key: d};
    final taken = <({String label, int at})>[];
    (await MedDb.dosesForDay(db, day)).forEach((key, slots) {
      for (final row in slots.values) {
        final ts = (row['taken_ts'] as num?)?.toInt();
        if (ts == null) continue;
        taken.add((label: defs[key]?.label ?? key, at: ts));
      }
    });

    return TimelineData(
      day: day,
      days: days,
      moments: dayMoments(
        timeline: timeline,
        wear: wear,
        meals: [for (final m in meals) m.sanitised],
        doses: taken,
        journal: journal,
        fields: fields,
      ),
      notes: dayNotes(
        meals: [for (final m in meals) m.sanitised],
        journal: journal,
        fields: fields,
        journalRows: [for (final r in notes) if (r['date'] == day) r],
      ),
    );
  }
}

class DayTimelineScreen extends StatefulWidget {
  const DayTimelineScreen({super.key, this.day, this.data});

  /// The day to open. Null means the newest derived one.
  final String? day;
  final TimelineData? data;

  @override
  State<DayTimelineScreen> createState() => _DayTimelineScreenState();
}

class _DayTimelineScreenState extends State<DayTimelineScreen> {
  TimelineData? _d;
  bool _loading = true;
  String? _day;

  @override
  void initState() {
    super.initState();
    _day = widget.day;
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
      final d = await TimelineData.load(repo, want: _day);
      if (mounted) setState(() => (_d = d, _loading = false));
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goDay(String day) {
    setState(() {
      _day = day;
      _loading = true;
    });
    _load();
  }

  @override
  Widget build(BuildContext c) {
    final d = _d ?? const TimelineData();
    return detailScaffold(c, 'What happened', sub: 'ONE DAY, IN ORDER', [
      ...dayNavRow(_day ?? d.day, d.days, _goDay),
      if (_loading) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else
        ...timelineBody(c, d),
    ]);
  }
}

/// The page's body, given loaded data. Split out so the gallery can build every
/// state of it without a repository.
List<Widget> timelineBody(BuildContext c, TimelineData d) {
  final p = P.of(c);
  return [
    if (d.moments.isEmpty && d.notes.isEmpty)
      const StatusCard(
        'Nothing was recorded on this day',
        'No sleep, no session, no log and no band event carrying a time. A day '
            'with nothing on it is usually a day the band was off.',
        icon: LucideIcons.circleSlash,
      )
    else ...[
      if (d.moments.isEmpty)
        const StatusCard(
          'Nothing on this day carries a time',
          'What was logged for it is below.',
          icon: LucideIcons.clock,
        )
      else
        Surface(
          pad: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x2),
          child: Column(
            children: [
              for (final m in d.moments) MomentRow(m),
            ],
          ),
        ),
      if (d.notes.isNotEmpty)
        Section(
          'Also logged on this day',
          Surface(
            pad: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x2),
            child: Column(
              children: [
                for (final n in d.notes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(n.icon, size: 17, color: p.ink3),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n.title,
                                  style: F.body.copyWith(color: p.ink)),
                              if (n.detail.isNotEmpty)
                                Text(n.detail,
                                    style: F.cap.copyWith(color: p.ink2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      if (d.notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: S.x2, left: S.x1),
          child: Text(
            'These were recorded against the day and carry no time of day, so '
            'they are not placed on it.',
            style: F.over.copyWith(color: p.ink3, height: 1.5),
          ),
        ),
    ],
    const SizedBox(height: S.x4),
    Text(
      'Patterns in your own logs, not causes. Two things next to each other '
      'here happened near each other, which is all this page claims.',
      style: F.over.copyWith(color: p.ink3, height: 1.5),
    ),
  ];
}

/// One line of the day. The time is the left column and everything aligns to
/// it, because the ONE thing this page is ordered by should be the one thing
/// you can scan.
class MomentRow extends StatelessWidget {
  const MomentRow(this.m, {super.key});
  final Moment m;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Semantics(
      label: '${clockOfTs(m.at)}, ${m.title}. ${m.detail}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scaled with the text, not fixed: the column exists so the times
            // line up, and a hard 62 px is a clipped clock at 3.1x on exactly
            // the phones whose owners chose 3.1x.
            SizedBox(
              width: MediaQuery.textScalerOf(c).scale(58),
              child: Text(clockOfTs(m.at), style: F.n17.copyWith(color: p.ink3)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(m.icon,
                  size: 17, color: m.color == null ? p.ink3 : p.on(m.color!)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    style: F.body
                        .copyWith(color: p.ink, fontWeight: FontWeight.w600),
                  ),
                  if (m.detail.isNotEmpty)
                    Text(m.detail,
                        style: F.cap.copyWith(color: p.ink2, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

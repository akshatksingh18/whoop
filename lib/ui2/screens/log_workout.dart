// LOG A WORKOUT — the two places the athlete owns the times, and the review
// screen the auto-detector has been writing to for months with nobody reading.
//
// WHY THIS FILE EXISTS AT ALL. `LocalRepository.logManualWorkout` and
// `setWorkoutWindow` have been implemented, tested and reachable from the
// coach's tool layer since the manual-session work landed, and reachable from
// the app from nowhere: the UI rebuild deleted `lib/ui/workouts/` and lib/ui2
// never replaced this part of it. Back-logging a session, or widening one the
// detector clipped, meant asking a BYOK language model to do it for you.
//
// The same deletion orphaned `workout_suggestions`. The detector still fills
// that table on every derive; `activeWorkoutSuggestions()` had exactly one
// reader and it only ever DISMISSED. `kRouteWorkoutSuggestion` survived, the
// tab mapping survived, and the destination did not — so the deep link fell
// through `screenForRoute`'s `_ => null` and landed on the plain Workouts tab.
//
// ONE WRITE SEAM. Confirming a detected bout is not a special kind of write:
// it is a manual session over the window the detector proposed, so it goes
// through `logManualWorkout` like every other. That is what gets it a strain
// and a calorie figure scored from the 1 Hz substrate — the old confirm path
// hand-built a row with neither and every confirmed suggestion landed in the
// log showing blanks. It also retires the suggestion on its own, inside the
// repo, via `supersededSuggestionIds`.
//
// WHAT THE DETECTOR REPORTS. The hard-effort CORE, not wall clock — see the
// header of `compute/manual_session.dart`. An hour of mixed training routinely
// detects as ~25 minutes, which is correct for a prompt and wrong for a log
// entry, and is exactly why "Adjust the times" sits beside "Log it" rather
// than three screens away.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/manual_session.dart';
import '../../data/db.dart';
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../notify/notification_prefs.dart';
import '../../state/app_state.dart';
import '../activity/catalogue.dart';
import '../profile/profile.dart' show SetRow, settingsGroup;
import '../ui2.dart';
import 'home_screen.dart' show repoOf;

/// One detected bout, as this screen needs it. Built straight off a
/// `workout_suggestions` row.
class Suggestion {
  const Suggestion({
    required this.id,
    required this.startTs,
    required this.endTs,
    this.sport,
    this.peakBpm,
    this.avgBpm,
  });

  final String id;
  final int startTs, endTs;
  final String? sport;
  final int? peakBpm, avgBpm;

  int get durationMin => ((endTs - startTs) / 60).round();

  /// The catalogue entry behind `sport`, when this build knows it. Null is
  /// carried rather than defaulted so the row can say what it was told.
  Activity? get activity => activityByName(sport);

  /// Null when the row is malformed — a suggestion with no window is not a
  /// suggestion, and it must not reach a screen that offers to log it.
  static Suggestion? from(Map<String, dynamic> r) {
    final id = r['id'];
    final s = (r['start_ts'] as num?)?.toInt();
    final e = (r['end_ts'] as num?)?.toInt();
    if (id is! String || s == null || e == null || e <= s) return null;
    return Suggestion(
      id: id,
      startTs: s,
      endTs: e,
      sport: r['sport'] as String?,
      peakBpm: (r['peak_bpm'] as num?)?.toInt(),
      avgBpm: (r['avg_bpm'] as num?)?.toInt(),
    );
  }
}

// ══════════════════ THE REVIEW SCREEN ══════════════════

/// Where "Did you work out?" lands. Every active bout, each with the two
/// answers that are honest — it happened, or it didn't — and the third that
/// matters more than either: the window is wrong.
class WorkoutSuggestionScreen extends StatefulWidget {
  const WorkoutSuggestionScreen({super.key, this.preloaded});

  /// Injected in tests and goldens. Null means read the table.
  final List<Suggestion>? preloaded;

  @override
  State<WorkoutSuggestionScreen> createState() =>
      _WorkoutSuggestionScreenState();
}

class _WorkoutSuggestionScreenState extends State<WorkoutSuggestionScreen> {
  List<Suggestion>? _items;

  /// Tracked SEPARATELY from [_items]. A failed query rendered as "nothing to
  /// review" tells the user a still-active suggestion was already handled,
  /// which is the one thing this screen must never say by accident.
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloaded != null) {
      _items = widget.preloaded;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final rows = await LocalDb.activeWorkoutSuggestions();
      if (!mounted) return;
      setState(() => _items = [for (final r in rows) ?Suggestion.from(r)]);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Log it, over the window the detector proposed.
  Future<void> _confirm(Suggestion s) async {
    final repo = repoOf(context);
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    var message = '';
    try {
      await repo.logManualWorkout(
        startTs: s.startTs,
        endTs: s.endTs,
        type: s.activity?.typeKey ?? 'other',
      );
      // The repo retires every suggestion the saved window covers, this one
      // included — nothing to dismiss here.
    } on ManualWindowException catch (e) {
      // A REFUSAL, not a failure to retry differently. The commonest is an
      // overlap: those minutes are already in the log, so the bout is spent.
      message = e.error.message;
      try {
        await LocalDb.dismissWorkoutSuggestion(s.id);
      } catch (_) {/* the reason is already on screen */}
    } catch (_) {
      message = 'Could not log this one — try again.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (message.isNotEmpty) _say(message);
    await _afterAction();
  }

  Future<void> _dismiss(Suggestion s) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await LocalDb.dismissWorkoutSuggestion(s.id);
    } catch (_) {
      if (mounted) _say('Could not dismiss this one — try again.');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _afterAction();
  }

  /// Open the form on the detected window so the athlete can widen it to the
  /// session they actually did, then save that instead.
  Future<void> _adjust(Suggestion s) async {
    final nav = Navigator.of(context);
    final saved = await nav.push<bool>(MaterialPageRoute<bool>(
      builder: (_) => LogWorkout(
        start: DateTime.fromMillisecondsSinceEpoch(s.startTs * 1000),
        end: DateTime.fromMillisecondsSinceEpoch(s.endTs * 1000),
        activity: s.activity,
        title: 'Adjust the times',
      ),
    ));
    if (saved == true) await _afterAction();
  }

  void _say(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  /// Re-read, then close once there is nothing left to review — the tab
  /// underneath is where the now-logged session is.
  Future<void> _afterAction() async {
    await _load();
    if (!mounted) return;
    bumpInsights(context);
    if (!_failed && (_items?.isEmpty ?? false)) {
      await Navigator.maybePop(context);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final items = _items;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Detected activity', sub: 'YOURS TO CONFIRM'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                if (_failed)
                  StatusCard(
                    'Could not read your detected activity',
                    'The store did not answer. Nothing has been logged or '
                        'dismissed.',
                    fix: 'Try again',
                    icon: LucideIcons.refreshCw,
                    onFix: _load,
                  )
                else if (items == null)
                  const NoData(message: 'Reading what the band spotted…')
                else if (items.isEmpty)
                  const StatusCard(
                    'Nothing to review',
                    'This one may already have been logged or dismissed.',
                    icon: LucideIcons.circleCheck,
                  )
                else
                  for (final s in items) ...[
                    _SuggestionCard(
                      s,
                      onConfirm: _busy ? null : () => _confirm(s),
                      onDismiss: _busy ? null : () => _dismiss(s),
                      onAdjust: _busy ? null : () => _adjust(s),
                    ),
                    const SizedBox(height: S.x3),
                  ],
                const SizedBox(height: S.x3),
                const StatusCard(
                  'These are the hard minutes, not the whole session',
                  'Detection reports the sustained effort it could see, so a '
                      'warm-up and the rest between sets fall outside it. '
                      'Adjust the times before logging if the window is short.',
                  icon: LucideIcons.scissors,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// One detected bout: what was seen, and the three answers to it.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard(
    this.s, {
    this.onConfirm,
    this.onDismiss,
    this.onAdjust,
  });

  final Suggestion s;
  final VoidCallback? onConfirm, onDismiss, onAdjust;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final a = s.activity;
    final colour = a?.color ?? C.purple;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.wash(colour), borderRadius: R.rMd),
            child: Icon(a?.icon ?? LucideIcons.activity,
                size: 19, color: p.on(colour)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${s.durationMin} min of effort',
                      style: F.body
                          .copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                  Text(windowLabel(s.startTs, s.endTs),
                      style: F.over.copyWith(color: p.ink3)),
                ]),
          ),
        ]),
        const SizedBox(height: S.x3),
        // What was actually measured. No strain and no calories: neither has
        // been scored yet — the scoring happens on the write, over whatever
        // window is finally saved, and printing one here would be a number
        // this screen made up.
        InlineMetrics([
          if (s.avgBpm != null) ('Avg HR', '${s.avgBpm} bpm', p.on(C.red)),
          if (s.peakBpm != null) ('Peak HR', '${s.peakBpm} bpm', p.on(C.orange)),
          if (a != null) ('Looks like', a.name, p.on(colour)),
        ]),
        const SizedBox(height: S.x4),
        BigButton('Log it', icon: LucideIcons.check, onTap: onConfirm),
        const SizedBox(height: S.x2),
        Row(children: [
          Expanded(
            child: BigButton('Adjust the times',
                icon: LucideIcons.clock,
                color: C.blue,
                soft: true,
                onTap: onAdjust),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: BigButton('Not a workout',
                icon: LucideIcons.x, color: C.red, soft: true, onTap: onDismiss),
          ),
        ]),
      ]),
    );
  }
}

/// "Today · 6:30 PM – 7:31 PM". The WINDOW, never just the start — the whole
/// reason someone opens this screen is to check whether the detector clipped
/// it, and a start time alone cannot show that.
String windowLabel(int startTs, int endTs) {
  final s = DateTime.fromMillisecondsSinceEpoch(startTs * 1000);
  final e = DateTime.fromMillisecondsSinceEpoch(endTs * 1000);
  return '${dayLabel(s)} · ${formatMinuteOfDay(s.hour * 60 + s.minute)} – '
      '${formatMinuteOfDay(e.hour * 60 + e.minute)}';
}

/// Today / Yesterday / "Mon 11 Aug", against the real calendar day rather than
/// a 24-hour subtraction — the day after a spring-forward is 23 hours long.
String dayLabel(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(at.year, at.month, at.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${wd[d.weekday - 1]} ${d.day} ${mo[d.month - 1]}';
}

// ══════════════════ THE FORM ══════════════════

/// Log a past session, or fix the window on one already in the log.
///
/// [sessionId] is the whole difference between the two: with it the save is a
/// RETIME (`setWorkoutWindow`, same id, so the row's GPS route and its rating
/// stay attached), without it a new manual entry (`logManualWorkout`). The
/// type is not editable on a retime — it belongs to the row already, and this
/// screen is about the times.
///
/// Pops `true` when something was written, so the caller can re-read.
class LogWorkout extends StatefulWidget {
  const LogWorkout({
    super.key,
    this.sessionId,
    this.start,
    this.end,
    this.activity,
    this.title = 'Log a past workout',
    this.spans,
    this.now,
  });

  final String? sessionId;
  final DateTime? start, end;
  final Activity? activity;
  final String title;

  /// The windows already in the log, for the live overlap check. Injected in
  /// tests; null means read them from the repo.
  final List<SessionSpan>? spans;

  /// Injected in tests so "that hasn't happened yet" is deterministic.
  final DateTime? now;

  @override
  State<LogWorkout> createState() => _LogWorkoutState();
}

class _LogWorkoutState extends State<LogWorkout> {
  late DateTime _start;
  late DateTime _end;
  late Activity _activity;
  List<SessionSpan> _spans = const [];
  bool _saving = false;
  String? _wrote;

  @override
  void initState() {
    super.initState();
    final now = widget.now ?? DateTime.now();
    // An hour, ending on the last whole hour. A form that opens on "now to
    // now" is a form whose first state is invalid.
    final defaultEnd = DateTime(now.year, now.month, now.day, now.hour);
    _end = widget.end ?? defaultEnd;
    _start = widget.start ?? _end.subtract(Motion.tick * 3600);
    _activity = widget.activity ?? quickStart.first;
    if (widget.spans != null) {
      _spans = widget.spans!;
    } else {
      _loadSpans();
    }
  }

  Future<void> _loadSpans() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final s = await repo.savedSessionSpans();
      if (mounted) setState(() => _spans = s);
    } catch (_) {/* the write seam re-checks anyway */}
  }

  int get _startSec => _start.millisecondsSinceEpoch ~/ 1000;
  int get _endSec => _end.millisecondsSinceEpoch ~/ 1000;

  /// The live verdict, from the SAME pure function the repo refuses on. Null
  /// means the window is acceptable.
  ManualWindowError? get _invalid => validateManualWindow(
        startSec: _startSec,
        endSec: _endSec,
        nowSec:
            (widget.now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
        existing: _spans,
        // A retime must not collide with itself; a new entry's id is derived
        // from its start second, so re-logging the same window updates that
        // row rather than colliding with it.
        editingId: widget.sessionId ?? manualSessionId(_startSec),
      );

  Future<void> _pickDate() async {
    final now = widget.now ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    final span = _end.difference(_start);
    setState(() {
      _start = DateTime(
          picked.year, picked.month, picked.day, _start.hour, _start.minute);
      _end = _start.add(span);
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final at = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: at.hour, minute: at.minute),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        final span = _end.difference(_start);
        _start = DateTime(_start.year, _start.month, _start.day, picked.hour,
            picked.minute);
        _end = _start.add(span);
      } else {
        var e = DateTime(
            _start.year, _start.month, _start.day, picked.hour, picked.minute);
        // Past midnight. A late run that finishes at 00:20 is an ordinary
        // session, not an invalid window — the alternative is asking the user
        // for a second date to express it.
        if (!e.isAfter(_start)) e = e.add(Motion.tick * 86400);
        _end = e;
      }
    });
  }

  Future<void> _pickActivity() async {
    final picked = await showModalBottomSheet<Activity>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: sheetMotion(context),
      backgroundColor: P.of(context).card,
      shape: const RoundedRectangleBorder(borderRadius: R.rXl),
      builder: (_) => const _TypeSheet(),
    );
    if (picked != null) setState(() => _activity = picked);
  }

  Future<void> _save() async {
    final repo = repoOf(context);
    if (repo == null || _saving || _invalid != null) return;
    final nav = Navigator.of(context);
    final app = appOf(context);
    setState(() {
      _saving = true;
      _wrote = null;
    });
    try {
      final r = widget.sessionId == null
          ? await repo.logManualWorkout(
              startTs: _startSec, endTs: _endSec, type: _activity.typeKey)
          : await repo.setWorkoutWindow(widget.sessionId!,
              startTs: _startSec, endTs: _endSec);
      // Say what was actually banked. A window with no 1 Hz substrate left
      // behind it — anything past the ~3-day retention, or a stretch the band
      // was off — is saved UNSCORED, and a screen that pops silently would let
      // the athlete believe a strain was computed for it.
      app?.insightsRevision.value++;
      if (r['unscored'] == true) {
        if (!mounted) return;
        setState(() {
          _saving = false;
          _wrote = 'Saved. No heart rate was recorded over that window, so it '
              'has no strain and no calorie figure — the times are all this '
              'one carries.';
        });
        return;
      }
      nav.pop(true);
    } on ManualWindowException catch (e) {
      if (mounted) setState(() { _saving = false; _wrote = e.error.message; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _wrote = 'Could not save that — try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final bad = _invalid;
    final mins = _end.difference(_start).inMinutes;
    final retime = widget.sessionId != null;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(widget.title,
                sub: retime ? 'THE WINDOW, RE-SCORED' : 'YOUR OWN TIMES'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                settingsGroup(c, 'When', [
                  if (!retime)
                    SetRow(_activity.icon, _activity.color, 'Activity',
                        value: _activity.name, onTap: _pickActivity),
                  SetRow(LucideIcons.calendar, C.blue, 'Date',
                      value: dayLabel(_start, now: widget.now),
                      onTap: _pickDate),
                  SetRow(LucideIcons.play, C.green, 'Started',
                      value:
                          formatMinuteOfDay(_start.hour * 60 + _start.minute),
                      onTap: () => _pickTime(isStart: true)),
                  SetRow(LucideIcons.square, C.orange, 'Ended',
                      value: formatMinuteOfDay(_end.hour * 60 + _end.minute),
                      sub: _end.day != _start.day ? 'the next morning' : '',
                      onTap: () => _pickTime(isStart: false)),
                  SetRow(LucideIcons.timer, C.purple, 'Length',
                      value: mins > 0 ? '$mins min' : '—',
                      chevron: false),
                ]),
                const SizedBox(height: S.x4),
                if (bad != null)
                  StatusCard('That window will not save', bad.message,
                      icon: LucideIcons.triangleAlert)
                else if (_wrote != null)
                  StatusCard(retime ? 'Times updated' : 'Workout logged',
                      _wrote!, icon: LucideIcons.circleCheck)
                else
                  StatusCard(
                    'Scored from what the band recorded',
                    'Strain and calories come from the 1-second heart rate '
                        'inside these times, through the same method the day '
                        'uses. Nothing is estimated from the duration.',
                    icon: LucideIcons.heartPulse,
                  ),
                const SizedBox(height: S.x4),
                BigButton(
                  _saving
                      ? 'Saving…'
                      : retime
                          ? 'Save the new times'
                          : 'Log it',
                  icon: LucideIcons.check,
                  onTap: bad == null && !_saving ? _save : null,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// The activity list, searchable. The picker proper (`ActivityPicker`) starts a
/// LIVE session; this one only names a window that has already happened.
class _TypeSheet extends StatefulWidget {
  const _TypeSheet();
  @override
  State<_TypeSheet> createState() => _TypeSheetState();
}

class _TypeSheetState extends State<_TypeSheet> {
  String _q = '';

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? allActivities
        : [
            for (final a in allActivities)
              if (a.name.toLowerCase().contains(q)) a,
          ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x2),
            child: TextField(
              autofocus: false,
              style: F.body.copyWith(color: p.ink),
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'Search activities',
                hintStyle: F.body.copyWith(color: p.ink3),
                filled: true,
                fillColor: p.card2,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: S.x4, vertical: S.x3),
                border: const OutlineInputBorder(
                    borderRadius: R.rPill, borderSide: BorderSide.none),
              ),
            ),
          ),
          Flexible(
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(S.x6),
                    child: NoData(message: 'No activity by that name'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x6),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final a = items[i];
                      return SetRow(a.icon, a.color, a.name,
                          chevron: false,
                          onTap: () => Navigator.of(c).pop(a));
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════ THE WORKOUTS-TAB ENTRY ══════════════════

/// Tell the app a session was written, so the Workouts tab re-reads. Null-safe
/// for a golden or a widget test, which have no AppState above them.
void bumpInsights(BuildContext c) => appOf(c)?.insightsRevision.value++;

/// The AppState, or null when there is none — same shape as [repoOf].
AppState? appOf(BuildContext c) {
  try {
    return c.read<AppState>();
  } catch (_) {
    return null;
  }
}

/// Active suggestions for the History tab, or empty when the user has switched
/// auto-detection off. Read here rather than in the screen so the switch is
/// honoured at ONE place for both surfaces it has.
Future<List<Suggestion>> activeSuggestions() async {
  try {
    if (!(await NotificationPrefs.load()).autoDetectEnabled) return const [];
    return [
      for (final r in await LocalDb.activeWorkoutSuggestions())
        ?Suggestion.from(r),
    ];
  } catch (_) {
    return const [];
  }
}

// Lift Log inside the WHOOP workout (build 86): the set logger that lives on
// the live Lift screen, the split choice in Lift setup, the summary card and
// the Splits editor. One Start, one clock, one Finish: the WHOOP session owns
// time, heart rate, strain and calories; this file owns exercises and sets.
//
// Every mutation is saved whole before the screen shows it (LiftLogDb.save),
// serialized so two taps cannot interleave. Rest timing, repeat-last-set and
// records are conveniences — nothing here pauses the WHOOP session, prices
// calories, or counts a prefilled set as performed.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/lift_log.dart';
import '../../gps/workout_clock.dart';
import '../../notify/notification_event.dart';
import '../../notify/notification_service.dart';
import '../../notify/tap_router.dart' show kRouteWorkoutIdle, datedRoute;
import '../../data/day_label.dart' show todayLabel;
import '../grammar.dart';
import '../theme.dart';
import '../screens/journal_compose.dart' show OsTextField;

String _hm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _md(DateTime t) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${m[t.month - 1]} ${t.day}';
}

// ── the choice made in Lift setup ──────────────────────────────────────────

/// What a lift session logs: a saved split, an empty workout, or time only.
sealed class LiftChoice {
  const LiftChoice();
  static const empty = _Empty();
  static const trackOnly = _TrackOnly();
  String get key;

  static const _prefKey = 'lift.choice';

  static Future<String?> last() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_prefKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> remember(LiftChoice c) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_prefKey, c.key);
    } catch (_) {}
  }
}

class LiftSplitChoice extends LiftChoice {
  const LiftSplitChoice(this.split);
  final LiftSplit split;
  @override
  String get key => 'split:${split.id}';
}

class _Empty extends LiftChoice {
  const _Empty();
  @override
  String get key => 'empty';
}

class _TrackOnly extends LiftChoice {
  const _TrackOnly();
  @override
  String get key => 'track';
}

/// Create the set log for a just-started WHOOP session. Tracking only makes
/// none (sets can still be started later from the live screen).
Future<void> beginLiftLog(
  LiftChoice choice, {
  required String sessionId,
  required DateTime startedAt,
}) async {
  await LiftChoice.remember(choice);
  if (choice is _TrackOnly) return;
  if (await LiftLogDb.forSession(sessionId) != null) return;
  final w = LiftWorkout(startedAt: startedAt, sessionId: sessionId);
  if (choice is LiftSplitChoice) w.syncWith(choice.split);
  await LiftLogDb.save(w);
  await LiftReminders.update(w);
}

/// End the log of a finished WHOOP session at its saved end. A log with no
/// sets is removed: the WHOOP workout itself stays, untouched.
Future<void> finishLiftLogFor(String sessionId, DateTime end) async {
  final w = await LiftLogDb.forSession(sessionId);
  if (w == null) return;
  await LiftReminders.cancel();
  if (!w.isActive) return;
  if (w.setCount == 0) {
    await LiftLogDb.delete(w.id);
    return;
  }
  w.finish(end);
  await LiftLogDb.save(w);
}

/// A log still open although its WHOOP session ended (the app was killed
/// between the two writes): finish it at the session's own end.
Future<void> reconcileLiftLogs(
  Future<DateTime?> Function(String sessionId) sessionEnd,
) async {
  final w = await LiftLogDb.active();
  final id = w?.sessionId;
  if (w == null || id == null) return;
  final end = await sessionEnd(id);
  if (end != null) await finishLiftLogFor(id, end);
}

// ── reminders: inactivity and rest ─────────────────────────────────────────

/// Lift Log's one-hour "Still working out?" and the optional rest timer, as
/// OS-scheduled one-shots so they arrive while the app is suspended. While a
/// session has a set log, this replaces the 20-minute heart-rate quiet nudge
/// (one coordinated policy, never two asks).
class LiftReminders {
  LiftReminders._();

  /// Sessions whose forgotten-workout ask belongs to this file.
  static final Set<String> loggingSessions = {};

  static Future<void> update(LiftWorkout w) async {
    final id = w.sessionId;
    if (id == null || !w.isActive) return cancel();
    loggingSessions.add(id);
    final due = w.lastActivity.add(LiftWorkout.inactivityDelay);
    final now = DateTime.now();
    await NotificationService.instance.scheduleOnce(
      id: NotificationService.idLiftInactivity,
      category: NotifCategory.reminders,
      title: 'Still working out?',
      body:
          'Nothing logged for an hour. Open the workout to finish it now or '
          'at your last set.',
      at: due.isAfter(now) ? due : now.add(LiftWorkout.inactivityDelay),
      route: datedRoute(kRouteWorkoutIdle, todayLabel(), id: id),
    );
  }

  static Future<void> cancel() async {
    loggingSessions.clear();
    await NotificationService.instance.cancel(
      NotificationService.idLiftInactivity,
    );
    await RestTimer.skip();
  }
}

/// A rest countdown held as a durable deadline, not a running process: the
/// lock screen or a relaunch shows the right remaining time, and the alert
/// is an OS one-shot. It never pauses the WHOOP session.
class RestTimer {
  RestTimer._();
  static const _deadlineKey = 'lift.rest.deadline';
  static const _defaultKey = 'lift.rest.default_sec';
  static const _perKey = 'lift.rest.per.';

  /// Choices offered; 0 is Off.
  static const choices = [0, 60, 90, 120, 180];

  static Future<SharedPreferences?> _p() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  static Future<int> defaultSec() async => (await _p())?.getInt(_defaultKey) ?? 0;

  static Future<void> setDefault(int sec) async =>
      (await _p())?.setInt(_defaultKey, sec);

  static Future<int> forExercise(String name) async {
    final p = await _p();
    return p?.getInt('$_perKey${liftNameKey(name)}') ??
        p?.getInt(_defaultKey) ??
        0;
  }

  static Future<void> setForExercise(String name, int? sec) async {
    final p = await _p();
    if (sec == null) {
      await p?.remove('$_perKey${liftNameKey(name)}');
    } else {
      await p?.setInt('$_perKey${liftNameKey(name)}', sec);
    }
  }

  static Future<DateTime?> deadline() async {
    final ms = (await _p())?.getInt(_deadlineKey);
    if (ms == null) return null;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return d.isAfter(DateTime.now()) ? d : null;
  }

  static Future<void> start(int sec, {String? sessionId}) async {
    if (sec <= 0) return;
    final d = DateTime.now().add(Duration(seconds: sec));
    await (await _p())?.setInt(_deadlineKey, d.millisecondsSinceEpoch);
    await NotificationService.instance.scheduleOnce(
      id: NotificationService.idRestTimer,
      category: NotifCategory.reminders,
      title: 'Rest is up',
      body: 'Time for the next set.',
      at: d,
      route: sessionId == null
          ? null
          : datedRoute(kRouteWorkoutIdle, todayLabel(), id: sessionId),
    );
  }

  static Future<void> add(Duration extra, {String? sessionId}) async {
    final d = await deadline();
    if (d == null) return;
    final left = d.difference(DateTime.now()) + extra;
    await start(left.inSeconds, sessionId: sessionId);
  }

  static Future<void> skip() async {
    await (await _p())?.remove(_deadlineKey);
    await NotificationService.instance.cancel(NotificationService.idRestTimer);
  }
}

// ── the controller ─────────────────────────────────────────────────────────

/// One live session's set log. Mutations run one at a time; each is applied
/// to a copy, saved, and only then shown. A failed save keeps what was shown
/// before and says so.
class LiftLogController extends ChangeNotifier {
  LiftLogController(this.sessionId);
  final String sessionId;

  LiftWorkout? workout;
  List<LiftSplit> splits = const [];
  final Map<String, LiftPerformance?> last = {};
  List<LiftExercise> recent = const [];
  String? message;
  bool loaded = false;
  Future<void> _tail = Future.value();
  bool _disposed = false;

  LiftSplit? get split {
    final w = workout;
    if (w == null) return null;
    return splits.where((s) => s.id == w.splitId).firstOrNull ??
        splits.where((s) => s.name == w.splitName).firstOrNull;
  }

  Future<void> load() async {
    try {
      workout = await LiftLogDb.forSession(sessionId);
      splits = await LiftLogDb.splits();
      recent = await LiftLogDb.recentExercises();
      await _refreshLast();
    } catch (e) {
      message = 'Your sets could not be read: $e';
    }
    loaded = true;
    _notify();
  }

  Future<void> _refreshLast() async {
    final w = workout;
    if (w == null) return;
    for (final e in w.exercises) {
      final k = '${liftNameKey(e.name)}|${e.loadMode.name}';
      if (last.containsKey(k)) continue;
      last[k] = await LiftLogDb.lastPerformance(
        e.name,
        e.loadMode,
        excludingId: w.id,
      );
    }
  }

  LiftPerformance? lastFor(LiftExercise e) =>
      last['${liftNameKey(e.name)}|${e.loadMode.name}'];

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Start logging on a tracking-only session.
  Future<void> startLogging({LiftSplit? from}) => _serial(() async {
    if (workout != null) return;
    final start = WorkoutClock.current?.start ?? DateTime.now();
    final w = LiftWorkout(startedAt: start, sessionId: sessionId);
    if (from != null) w.syncWith(from);
    await LiftLogDb.save(w);
    workout = w;
    await _refreshLast();
    await LiftReminders.update(w);
  });

  Future<void> _serial(Future<void> Function() body) {
    final run = _tail.then((_) async {
      try {
        await body();
        message = null;
      } on LiftLogError catch (e) {
        message = e.message;
      } catch (e) {
        message = 'That was not saved. Please try again.';
      }
      _notify();
    });
    _tail = run;
    return run;
  }

  /// Apply [f] to a copy, save it, then show it.
  Future<void> mutate(void Function(LiftWorkout w) f, {bool activity = true}) =>
      _serial(() async {
        final cur = workout;
        if (cur == null) return;
        final next = cur.copy();
        f(next);
        await LiftLogDb.save(next);
        workout = next;
        await _refreshLast();
        if (activity) await LiftReminders.update(next);
      });

  Future<void> logSet(String exerciseId, {required int reps, required double load}) async {
    await mutate((w) => w.addSet(exerciseId, reps: reps, load: load, at: DateTime.now()));
    if (message != null) return;
    final e = workout?.exercises.where((x) => x.id == exerciseId).firstOrNull;
    if (e == null) return;
    await RestTimer.start(await RestTimer.forExercise(e.name), sessionId: sessionId);
    _notify();
  }

  Future<void> saveSplits(List<LiftSplit> next) => _serial(() async {
    await LiftLogDb.saveSplits(next);
    splits = LiftSplit.validatedList(next);
    final w = workout;
    final s = split;
    if (w != null && s != null) {
      final synced = w.copy()..syncWith(s);
      await LiftLogDb.save(synced);
      workout = synced;
      await _refreshLast();
    }
  });

  /// Add an exercise today and, when the workout came from a split, to the
  /// split as well (linked by name if it is already there).
  Future<void> addExercise(String name, LiftLoadMode mode, String note) =>
      _serial(() async {
        final cur = workout;
        if (cur == null) return;
        if (cur.exercises.any((e) => sameLiftName(e.name, name))) {
          throw LiftLogError('${name.trim()} is already in this workout.');
        }
        String? link;
        final s = split?.copy();
        if (s != null) {
          final existing = s.exercises.where((e) => sameLiftName(e.name, name)).firstOrNull;
          if (existing != null) {
            link = existing.id;
          } else if (s.exercises.length < LiftSplit.maxExercises) {
            final added = LiftSplitExercise(name: name.trim(), loadMode: mode, equipmentNote: note);
            s.exercises.add(added);
            final all = [for (final x in splits) x.id == s.id ? s : x];
            await LiftLogDb.saveSplits(all);
            splits = LiftSplit.validatedList(all);
            link = added.id;
          }
        }
        final next = cur.copy();
        if (link != null) next.skipped.remove(link);
        next.addExercise(name: name, loadMode: mode, equipmentNote: note, splitExerciseId: link);
        await LiftLogDb.save(next);
        workout = next;
        await _refreshLast();
        await LiftReminders.update(next);
      });

  Future<void> removeExercise(String exerciseId, {required bool fromSplit}) =>
      _serial(() async {
        final cur = workout;
        if (cur == null) return;
        final next = cur.copy();
        final removed = next.removeExercise(exerciseId);
        final link = removed.splitExerciseId;
        final s = split?.copy();
        if (link != null && s != null) {
          if (fromSplit) {
            s.exercises.removeWhere((e) => e.id == link);
            final all = [for (final x in splits) x.id == s.id ? s : x];
            await LiftLogDb.saveSplits(all);
            splits = LiftSplit.validatedList(all);
          } else {
            next.skipped.add(link);
          }
        }
        await LiftLogDb.save(next);
        workout = next;
        await LiftReminders.update(next);
      });
}

// ── Lift setup: choose what to log ─────────────────────────────────────────

class LiftChoicePicker extends StatefulWidget {
  const LiftChoicePicker({super.key, required this.onChanged});
  final ValueChanged<LiftChoice> onChanged;

  @override
  State<LiftChoicePicker> createState() => _LiftChoicePickerState();
}

class _LiftChoicePickerState extends State<LiftChoicePicker> {
  List<LiftSplit> _splits = const [];
  String _selected = 'empty';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await LiftLogDb.splits();
      final last = await LiftChoice.last();
      if (!mounted) return;
      setState(() {
        _splits = s;
        if (last != null &&
            (last == 'empty' ||
                last == 'track' ||
                s.any((x) => 'split:${x.id}' == last))) {
          _selected = last;
        }
      });
      widget.onChanged(_choice);
    } catch (_) {}
  }

  LiftChoice get _choice {
    if (_selected == 'track') return LiftChoice.trackOnly;
    for (final s in _splits) {
      if ('split:${s.id}' == _selected) return LiftSplitChoice(s);
    }
    return LiftChoice.empty;
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget option(String key, String title, String sub) => Pressable(
      semanticLabel: _selected == key ? '$title, selected' : title,
      onTap: () {
        setState(() => _selected = key);
        widget.onChanged(_choice);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Icon(
              _selected == key ? LucideIcons.circleDot : LucideIcons.circle,
              size: 18,
              color: _selected == key ? p.on(C.purple) : p.ink3,
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: F.body.copyWith(color: p.ink)),
                  if (sub.isNotEmpty)
                    Text(sub, style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Section(
      'Sets',
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(
          children: [
            for (final s in _splits)
              option(
                'split:${s.id}',
                s.name,
                s.exercises.isEmpty
                    ? 'No exercises yet'
                    : s.exercises.take(3).map((e) => e.name).join(', ') +
                          (s.exercises.length > 3 ? '…' : ''),
              ),
            option('empty', 'Empty workout', 'Add exercises as you go'),
            option('track', 'Time only', 'No sets; you can start logging later'),
          ],
        ),
      ),
      action: 'Splits',
      onAction: () async {
        await Navigator.of(c).push(
          MaterialPageRoute<void>(builder: (_) => const LiftSplitsScreen()),
        );
        _load();
      },
    );
  }
}

// ── the live panel ─────────────────────────────────────────────────────────

class LiftLivePanel extends StatefulWidget {
  const LiftLivePanel({super.key, required this.sessionId, this.onFinishAt});
  final String sessionId;

  /// Finish the WHOOP session, at [end] when given (a reviewed last-set end),
  /// otherwise now.
  final Future<void> Function(DateTime? end)? onFinishAt;

  @override
  State<LiftLivePanel> createState() => _LiftLivePanelState();
}

class _LiftLivePanelState extends State<LiftLivePanel> {
  late final LiftLogController ctl = LiftLogController(widget.sessionId)
    ..addListener(_changed);
  final _search = TextEditingController();
  final _expanded = <String>{};
  final _loadText = <String, TextEditingController>{};
  final _repsText = <String, TextEditingController>{};
  Timer? _restTick;
  DateTime? _restUntil;
  bool _keepGoing = false;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    ctl.load();
    _search.addListener(() => setState(() {}));
    _readRest();
    _restTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_restUntil != null && !_restUntil!.isAfter(DateTime.now())) {
        _restUntil = null;
        HapticFeedback.mediumImpact();
      }
      if (_restUntil != null) setState(() {});
    });
  }

  Future<void> _readRest() async {
    final d = await RestTimer.deadline();
    if (mounted) setState(() => _restUntil = d);
  }

  @override
  void dispose() {
    _restTick?.cancel();
    ctl.removeListener(_changed);
    ctl.dispose();
    _search.dispose();
    for (final t in [..._loadText.values, ..._repsText.values]) {
      t.dispose();
    }
    super.dispose();
  }

  TextEditingController _load(String id) => _loadText[id] ??= TextEditingController();
  TextEditingController _reps(String id) => _repsText[id] ??= TextEditingController();

  /// Fill the entry from the set before (today) or the first set last time.
  /// Only a suggestion: nothing is logged until Log set is pressed.
  void _repeat(LiftExercise e) {
    final s = e.sets.isNotEmpty ? e.sets.last : ctl.lastFor(e)?.exercise.sets.firstOrNull;
    if (s == null) return;
    _load(e.id).text = liftWeightText(s.load);
    _reps(e.id).text = '${s.reps}';
    setState(() {});
  }

  Future<void> _log(LiftExercise e) async {
    final load = double.tryParse(_load(e.id).text.trim().replaceAll(',', '.'));
    final reps = int.tryParse(_reps(e.id).text.trim());
    if (load == null || reps == null) {
      _say('Enter the weight and the reps.');
      return;
    }
    await ctl.logSet(e.id, reps: reps, load: load);
    if (ctl.message != null) {
      _say(ctl.message!);
    } else {
      await _readRest();
    }
  }

  void _say(String t) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t), duration: Motion.notice));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    if (!ctl.loaded) return const SizedBox(height: S.x4);
    final w = ctl.workout;
    if (w == null) {
      return Padding(
        padding: const EdgeInsets.only(top: S.x6),
        child: Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sets', style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              const SizedBox(height: S.x1),
              Text(
                'This workout records time and heart rate only.',
                style: F.cap.copyWith(color: p.ink3),
              ),
              const SizedBox(height: S.x3),
              BigButton(
                'Log sets',
                icon: LucideIcons.dumbbell,
                color: C.purple,
                soft: true,
                onTap: () => ctl.startLogging(),
              ),
            ],
          ),
        ),
      );
    }
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final e in w.exercises)
        if (q.isEmpty || e.name.toLowerCase().contains(q)) e,
    ];
    final extra = q.isEmpty
        ? const <LiftExercise>[]
        : [
            for (final r in ctl.recent)
              if (r.name.toLowerCase().contains(q) &&
                  !w.exercises.any((e) => sameLiftName(e.name, r.name)))
                r,
          ];
    final idle = DateTime.now().difference(w.lastActivity) >= LiftWorkout.inactivityDelay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: S.x6),
        if (idle && !_keepGoing && widget.onFinishAt != null)
          _forgotten(c, p, w),
        Row(
          children: [
            Expanded(
              child: Text(
                w.splitName ?? 'Empty workout',
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
              ),
            ),
            Text('${w.setCount} ${w.setCount == 1 ? 'set' : 'sets'}',
                style: F.cap.copyWith(color: p.ink3)),
            const SizedBox(width: S.x3),
            Pressable(
              semanticLabel: 'Rest timer',
              onTap: () => _restSheet(c),
              child: Icon(LucideIcons.timer, size: 20, color: p.ink2),
            ),
            const SizedBox(width: S.x3),
            Pressable(
              semanticLabel: 'Splits',
              onTap: () async {
                await Navigator.of(c).push(MaterialPageRoute<void>(
                  builder: (_) => LiftSplitsScreen(controller: ctl),
                ));
              },
              child: Icon(LucideIcons.listOrdered, size: 20, color: p.ink2),
            ),
          ],
        ),
        if (_restUntil != null) ...[
          const SizedBox(height: S.x3),
          _restBar(p),
        ],
        const SizedBox(height: S.x3),
        OsTextField(controller: _search, label: 'Find or add an exercise', hint: 'Bench, row…'),
        const SizedBox(height: S.x3),
        for (final e in shown) _card(c, p, w, e),
        for (final r in extra)
          _addRow(p, r.name, '${r.loadMode.title} · logged before',
              () => ctl.addExercise(r.name, r.loadMode, r.equipmentNote).then((_) => _search.clear())),
        if (q.isNotEmpty && !w.exercises.any((e) => sameLiftName(e.name, q)) &&
            !extra.any((r) => sameLiftName(r.name, q)))
          _addRow(p, 'Add "${_search.text.trim()}"', 'New exercise',
              () => _addSheet(c, name: _search.text.trim())),
        if (q.isEmpty)
          Pressable(
            semanticLabel: 'Add exercise',
            onTap: () => _addSheet(c),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: Row(children: [
                Icon(LucideIcons.plus, size: 18, color: p.on(C.purple)),
                const SizedBox(width: S.x2),
                Text('Add exercise', style: F.body.copyWith(color: p.on(C.purple))),
              ]),
            ),
          ),
        if (ctl.message != null)
          Text(ctl.message!, style: F.cap.copyWith(color: p.on(C.red))),
      ],
    );
  }

  Widget _forgotten(BuildContext c, P p, LiftWorkout w) {
    final last = w.lastActivity;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x4),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Still working out?', style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            const SizedBox(height: S.x1),
            Text(
              'Nothing logged since ${_hm(last)}. Finishing at your last set '
              'ends the workout then; its heart rate and calories stop there too.',
              style: F.cap.copyWith(color: p.ink3),
            ),
            const SizedBox(height: S.x3),
            BigButton('Finish at ${_hm(last)}', color: C.purple, onTap: () => widget.onFinishAt!(last)),
            const SizedBox(height: S.x2),
            BigButton('Finish now', color: C.purple, soft: true, onTap: () => widget.onFinishAt!(null)),
            const SizedBox(height: S.x2),
            BigButton('Keep going', soft: true, color: C.n500, onTap: () => setState(() => _keepGoing = true)),
          ],
        ),
      ),
    );
  }

  Widget _restBar(P p) {
    final left = _restUntil!.difference(DateTime.now());
    final s = left.inSeconds.clamp(0, 3600);
    return Surface(
      color: p.card2,
      elevation: 0,
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      child: Row(
        children: [
          Icon(LucideIcons.timer, size: 18, color: p.ink2),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(
              'Rest ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
              style: F.n17.copyWith(color: p.ink),
            ),
          ),
          Pressable(
            semanticLabel: 'Add 30 seconds',
            onTap: () async {
              await RestTimer.add(const Duration(seconds: 30), sessionId: widget.sessionId);
              await _readRest();
            },
            child: Text('+30 s', style: F.cap.copyWith(color: p.ink2)),
          ),
          const SizedBox(width: S.x4),
          Pressable(
            semanticLabel: 'Skip rest',
            onTap: () async {
              await RestTimer.skip();
              await _readRest();
            },
            child: Text('Skip', style: F.cap.copyWith(color: p.ink2)),
          ),
        ],
      ),
    );
  }

  Widget _addRow(P p, String title, String sub, VoidCallback onTap) => Pressable(
    semanticLabel: title,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Icon(LucideIcons.plus, size: 18, color: p.on(C.purple)),
        const SizedBox(width: S.x2),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: F.body.copyWith(color: p.ink)),
            Text(sub, style: F.over.copyWith(color: p.ink3)),
          ]),
        ),
      ]),
    ),
  );

  Widget _card(BuildContext c, P p, LiftWorkout w, LiftExercise e) {
    final idx = w.exercises.indexOf(e);
    final open = e.sets.isNotEmpty || _expanded.contains(e.id);
    final lastP = ctl.lastFor(e);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Pressable(
                    semanticLabel: e.name,
                    onTap: () => setState(() => open && e.sets.isEmpty
                        ? _expanded.remove(e.id)
                        : _expanded.add(e.id)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name, style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
                        Text(
                          [e.loadMode.title, if (e.equipmentNote.isNotEmpty) e.equipmentNote].join(' · '),
                          style: F.over.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ),
                if (idx > 0)
                  Pressable(
                    semanticLabel: 'Move ${e.name} up',
                    onTap: () => ctl.mutate((x) => x.moveExercise(idx, idx - 1), activity: false),
                    child: Padding(
                      padding: const EdgeInsets.all(S.x1),
                      child: Icon(LucideIcons.arrowUp, size: 17, color: p.ink3),
                    ),
                  ),
                Pressable(
                  semanticLabel: 'Remove ${e.name}',
                  onTap: () => _removeSheet(c, w, e),
                  child: Padding(
                    padding: const EdgeInsets.all(S.x1),
                    child: Icon(LucideIcons.x, size: 17, color: p.ink3),
                  ),
                ),
              ],
            ),
            if (lastP != null) ...[
              const SizedBox(height: S.x2),
              Text(
                'Last time ${_md(lastP.date)}: ${[
                  for (var i = 0; i < lastP.exercise.sets.length; i++)
                    'S${i + 1} ${lastP.exercise.setText(lastP.exercise.sets[i])}',
                ].join(' · ')}',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
            if (e.sets.isNotEmpty) ...[
              const SizedBox(height: S.x3),
              Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                children: [
                  for (var i = 0; i < e.sets.length; i++)
                    Pressable(
                      semanticLabel: 'Set ${i + 1}: ${e.setText(e.sets[i])}. Edit',
                      onTap: () => _editSet(c, e, e.sets[i]),
                      child: Pill('S${i + 1} ${e.setText(e.sets[i])}', C.purple),
                    ),
                ],
              ),
            ],
            if (open) ...[
              const SizedBox(height: S.x3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: OsTextField(
                      controller: _load(e.id),
                      label: e.loadMode.shortUnit,
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  Expanded(
                    child: OsTextField(
                      controller: _reps(e.id),
                      label: 'Reps',
                      keyboard: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Row(
                children: [
                  Expanded(
                    child: BigButton('Log set', icon: LucideIcons.check, color: C.purple,
                        onTap: () => _log(e)),
                  ),
                  if (e.sets.isNotEmpty || lastP != null) ...[
                    const SizedBox(width: S.x2),
                    Pressable(
                      semanticLabel: 'Repeat last set',
                      onTap: () => _repeat(e),
                      child: Padding(
                        padding: const EdgeInsets.all(S.x3),
                        child: Icon(LucideIcons.repeat, size: 20, color: p.ink2),
                      ),
                    ),
                  ],
                  if (e.sets.isNotEmpty)
                    Pressable(
                      semanticLabel: 'Undo last set',
                      onTap: () => ctl.mutate((x) => x.removeLastSet(e.id)),
                      child: Padding(
                        padding: const EdgeInsets.all(S.x3),
                        child: Icon(LucideIcons.undo2, size: 20, color: p.ink2),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editSet(BuildContext c, LiftExercise e, LiftSet s) async {
    final load = TextEditingController(text: liftWeightText(s.load));
    final reps = TextEditingController(text: '${s.reps}');
    final r = await _sheet<String>(c, (sc) => [
      Text('Edit set', style: F.head.copyWith(color: P.of(sc).ink)),
      const SizedBox(height: S.x1),
      Text('${e.name} · logged ${_hm(s.completedAt)}',
          style: F.cap.copyWith(color: P.of(sc).ink3)),
      const SizedBox(height: S.x4),
      OsTextField(controller: load, label: e.loadMode.shortUnit,
          keyboard: const TextInputType.numberWithOptions(decimal: true)),
      const SizedBox(height: S.x3),
      OsTextField(controller: reps, label: 'Reps', keyboard: TextInputType.number),
      const SizedBox(height: S.x4),
      BigButton('Save', color: C.purple, onTap: () => Navigator.of(sc).pop('save')),
      const SizedBox(height: S.x2),
      BigButton('Delete set', icon: LucideIcons.trash2, color: C.red, soft: true,
          onTap: () => Navigator.of(sc).pop('delete')),
    ]);
    if (r == 'save') {
      final l = double.tryParse(load.text.trim().replaceAll(',', '.'));
      final n = int.tryParse(reps.text.trim());
      if (l == null || n == null) return _say('Enter the weight and the reps.');
      await ctl.mutate((x) => x.updateSet(e.id, s.id, reps: n, load: l));
    } else if (r == 'delete') {
      await ctl.mutate((x) => x.removeSet(e.id, s.id));
    }
    if (ctl.message != null) _say(ctl.message!);
  }

  Future<void> _removeSheet(BuildContext c, LiftWorkout w, LiftExercise e) async {
    final split = ctl.split;
    final inSplit = split != null && e.splitExerciseId != null;
    final r = await _sheet<String>(c, (sc) => [
      Text('Remove ${e.name}?', style: F.head.copyWith(color: P.of(sc).ink)),
      if (e.sets.isNotEmpty) ...[
        const SizedBox(height: S.x1),
        Text('Its ${e.sets.length} logged ${e.sets.length == 1 ? 'set goes' : 'sets go'} with it.',
            style: F.cap.copyWith(color: P.of(sc).on(C.red))),
      ],
      const SizedBox(height: S.x4),
      BigButton('Remove from today', color: C.red, soft: true,
          onTap: () => Navigator.of(sc).pop('today')),
      if (inSplit) ...[
        const SizedBox(height: S.x2),
        BigButton('Remove from today and ${split.name}', color: C.red,
            onTap: () => Navigator.of(sc).pop('split')),
      ],
      const SizedBox(height: S.x2),
      BigButton('Keep it', soft: true, color: C.n500, onTap: () => Navigator.of(sc).pop()),
    ]);
    if (r == null) return;
    await ctl.removeExercise(e.id, fromSplit: r == 'split');
    if (ctl.message != null) _say(ctl.message!);
  }

  Future<void> _addSheet(BuildContext c, {String name = ''}) async {
    final picked = await editLiftExercise(c, name: name);
    if (picked == null) return;
    await ctl.addExercise(picked.name, picked.loadMode, picked.equipmentNote);
    _search.clear();
    if (ctl.message != null) _say(ctl.message!);
  }

  Future<void> _restSheet(BuildContext c) async {
    final cur = await RestTimer.defaultSec();
    if (!c.mounted) return;
    final r = await _sheet<int>(c, (sc) => [
      Text('Rest timer', style: F.head.copyWith(color: P.of(sc).ink)),
      const SizedBox(height: S.x1),
      Text('Starts after each logged set. It does not pause the workout.',
          style: F.cap.copyWith(color: P.of(sc).ink3)),
      const SizedBox(height: S.x4),
      for (final s in RestTimer.choices)
        Pressable(
          semanticLabel: s == 0 ? 'Off' : '$s seconds',
          onTap: () => Navigator.of(sc).pop(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(children: [
              Icon(s == cur ? LucideIcons.circleDot : LucideIcons.circle, size: 18,
                  color: P.of(sc).ink2),
              const SizedBox(width: S.x3),
              Text(s == 0 ? 'Off' : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}',
                  style: F.body.copyWith(color: P.of(sc).ink)),
            ]),
          ),
        ),
    ]);
    if (r != null) await RestTimer.setDefault(r);
  }
}

Future<T?> _sheet<T>(BuildContext c, List<Widget> Function(BuildContext) body) =>
    showModalBottomSheet<T>(
      context: c,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (sc) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sc).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: body(sc),
          ),
        ),
      ),
    );

/// Name, load meaning (with its guidance) and an optional equipment note.
Future<LiftSplitExercise?> editLiftExercise(
  BuildContext c, {
  String name = '',
  LiftSplitExercise? existing,
}) async {
  final n = TextEditingController(text: existing?.name ?? name);
  final note = TextEditingController(text: existing?.equipmentNote ?? '');
  var mode = existing?.loadMode ?? LiftLoadMode.platesPerSide;
  final ok = await showModalBottomSheet<bool>(
    context: c,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: P.of(c).card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (sc) => StatefulBuilder(
      builder: (sc, set) {
        final p = P.of(sc);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sc).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(S.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'Add exercise' : 'Edit exercise',
                    style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: S.x4),
                OsTextField(controller: n, label: 'Name', hint: 'Dumbbell bench press'),
                const SizedBox(height: S.x4),
                Text('HOW THE WEIGHT IS ENTERED', style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x2),
                for (final m in LiftLoadMode.values)
                  Pressable(
                    semanticLabel: m == mode ? '${m.title}, selected' : m.title,
                    onTap: () => set(() => mode = m),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(m == mode ? LucideIcons.circleDot : LucideIcons.circle,
                              size: 18, color: m == mode ? p.on(C.purple) : p.ink3),
                          const SizedBox(width: S.x3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.title, style: F.body.copyWith(color: p.ink)),
                                if (m == mode)
                                  Text(m.guidance, style: F.over.copyWith(color: p.ink3)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: S.x3),
                OsTextField(controller: note, label: 'Equipment note (optional)',
                    hint: 'Which machine, or base resistance unknown'),
                const SizedBox(height: S.x5),
                BigButton('Save', color: C.purple, onTap: () {
                  if (n.text.trim().isEmpty) return;
                  Navigator.of(sc).pop(true);
                }),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (ok != true) return null;
  return LiftSplitExercise(
    id: existing?.id,
    name: n.text.trim(),
    loadMode: mode,
    equipmentNote: note.text.trim(),
  );
}

// ── the summary card ───────────────────────────────────────────────────────

class LiftSummaryCard extends StatefulWidget {
  const LiftSummaryCard({super.key, required this.sessionId});
  final String sessionId;
  @override
  State<LiftSummaryCard> createState() => _LiftSummaryCardState();
}

class _LiftSummaryCardState extends State<LiftSummaryCard> {
  LiftWorkout? _w;
  List<LiftRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = await LiftLogDb.forSession(widget.sessionId);
      final records = w == null ? const <LiftRecord>[] : liftRecords(w, await LiftLogDb.finished());
      if (mounted) setState(() => (_w = w, _records = records));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final w = _w;
    if (w == null || w.setCount == 0) return const SizedBox.shrink();
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.only(top: S.x4),
      child: Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: Text(w.splitName ?? 'Sets',
                    style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
              ),
              Text('${w.setCount} ${w.setCount == 1 ? 'set' : 'sets'}',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
            for (final e in w.exercises) ...[
              const SizedBox(height: S.x3),
              Text(e.name, style: F.body.copyWith(color: p.ink)),
              Text(
                [for (var i = 0; i < e.sets.length; i++) 'S${i + 1} ${e.setText(e.sets[i])}']
                    .join(' · '),
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
            if (_records.isNotEmpty) ...[
              const SizedBox(height: S.x4),
              Text('NEW BESTS', style: F.over.copyWith(color: p.ink3)),
              for (final r in _records)
                Text('${r.exercise}: ${r.text}', style: F.cap.copyWith(color: p.ink2)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Splits ─────────────────────────────────────────────────────────────────

class LiftSplitsScreen extends StatefulWidget {
  const LiftSplitsScreen({super.key, this.controller});

  /// The live workout's controller, so an edit reaches the open workout.
  final LiftLogController? controller;

  @override
  State<LiftSplitsScreen> createState() => _LiftSplitsScreenState();
}

class _LiftSplitsScreenState extends State<LiftSplitsScreen> {
  List<LiftSplit> _splits = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await LiftLogDb.splits();
    if (mounted) setState(() => _splits = s);
  }

  Future<void> _save(List<LiftSplit> next) async {
    try {
      final ctl = widget.controller;
      if (ctl != null) {
        await ctl.saveSplits(next);
        if (ctl.message != null) throw LiftLogError(ctl.message!);
      } else {
        await LiftLogDb.saveSplits(next);
      }
      setState(() => (_splits = LiftSplit.validatedList(next), _error = null));
    } on LiftLogError catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<String?> _name(String title, String initial) async {
    final t = TextEditingController(text: initial);
    final ok = await _sheet<bool>(context, (sc) => [
      Text(title, style: F.head.copyWith(color: P.of(sc).ink)),
      const SizedBox(height: S.x4),
      OsTextField(controller: t, label: 'Name', hint: 'Chest day'),
      const SizedBox(height: S.x4),
      BigButton('Save', color: C.purple, onTap: () => Navigator.of(sc).pop(true)),
    ]);
    return ok == true ? t.text.trim() : null;
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Splits'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.x3),
                      child: Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
                    ),
                  for (var i = 0; i < _splits.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.x3),
                      child: Surface(
                        onTap: () async {
                          await Navigator.of(c).push(MaterialPageRoute<void>(
                            builder: (_) => _SplitEditor(
                              split: _splits[i],
                              onSave: (s) => _save([for (final x in _splits) x.id == s.id ? s : x]),
                            ),
                          ));
                          _load();
                        },
                        semanticLabel: _splits[i].name,
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_splits[i].name, style: F.body.copyWith(color: p.ink)),
                              Text('${_splits[i].exercises.length} exercises',
                                  style: F.over.copyWith(color: p.ink3)),
                            ]),
                          ),
                          if (i > 0)
                            Pressable(
                              semanticLabel: 'Move ${_splits[i].name} up',
                              onTap: () {
                                final n = [..._splits];
                                n.insert(i - 1, n.removeAt(i));
                                _save(n);
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(S.x2),
                                child: Icon(LucideIcons.arrowUp, size: 17, color: p.ink3),
                              ),
                            ),
                          Pressable(
                            semanticLabel: 'Delete ${_splits[i].name}',
                            onTap: () async {
                              final s = _splits[i];
                              if (await confirmRemove(c,
                                  title: 'Delete ${s.name}?',
                                  body: 'Past workouts keep their sets and its name.',
                                  remove: 'Delete')) {
                                await _save([for (final x in _splits) if (x.id != s.id) x]);
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(S.x2),
                              child: Icon(LucideIcons.trash2, size: 17, color: p.ink3),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  if (_splits.length < LiftSplit.maxSplits)
                    BigButton('New split', icon: LucideIcons.plus, color: C.purple, soft: true,
                        onTap: () async {
                          final n = await _name('New split', '');
                          if (n == null || n.isEmpty) return;
                          await _save([..._splits, LiftSplit(name: n)]);
                        }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitEditor extends StatefulWidget {
  const _SplitEditor({required this.split, required this.onSave});
  final LiftSplit split;
  final Future<void> Function(LiftSplit) onSave;
  @override
  State<_SplitEditor> createState() => _SplitEditorState();
}

class _SplitEditorState extends State<_SplitEditor> {
  late LiftSplit s = widget.split.copy();

  Future<void> _commit() async => widget.onSave(s.copy());

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(s.name),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Pressable(
                  semanticLabel: 'Rename split',
                  onTap: () async {
                    final t = TextEditingController(text: s.name);
                    final ok = await _sheet<bool>(c, (sc) => [
                      Text('Rename split', style: F.head.copyWith(color: P.of(sc).ink)),
                      const SizedBox(height: S.x4),
                      OsTextField(controller: t, label: 'Name'),
                      const SizedBox(height: S.x4),
                      BigButton('Save', color: C.purple, onTap: () => Navigator.of(sc).pop(true)),
                    ]);
                    if (ok == true && t.text.trim().isNotEmpty) {
                      setState(() => s.name = t.text.trim());
                      await _commit();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x3),
                    child: Text('Rename', style: F.cap.copyWith(color: p.ink2)),
                  ),
                ),
                for (var i = 0; i < s.exercises.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.x2),
                    child: Surface(
                      semanticLabel: s.exercises[i].name,
                      onTap: () async {
                        final e = await editLiftExercise(c, existing: s.exercises[i]);
                        if (e == null) return;
                        setState(() => s.exercises[i] = e);
                        await _commit();
                      },
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.exercises[i].name, style: F.body.copyWith(color: p.ink)),
                            Text(s.exercises[i].loadMode.title,
                                style: F.over.copyWith(color: p.ink3)),
                          ]),
                        ),
                        if (i > 0)
                          Pressable(
                            semanticLabel: 'Move ${s.exercises[i].name} up',
                            onTap: () async {
                              setState(() => s.exercises.insert(i - 1, s.exercises.removeAt(i)));
                              await _commit();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(S.x2),
                              child: Icon(LucideIcons.arrowUp, size: 17, color: p.ink3),
                            ),
                          ),
                        Pressable(
                          semanticLabel: 'Remove ${s.exercises[i].name}',
                          onTap: () async {
                            setState(() => s.exercises.removeAt(i));
                            await _commit();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(S.x2),
                            child: Icon(LucideIcons.x, size: 17, color: p.ink3),
                          ),
                        ),
                      ]),
                    ),
                  ),
                if (s.exercises.length < LiftSplit.maxExercises)
                  BigButton('Add exercise', icon: LucideIcons.plus, color: C.purple, soft: true,
                      onTap: () async {
                        final e = await editLiftExercise(c);
                        if (e == null) return;
                        setState(() => s.exercises.add(e));
                        await _commit();
                      }),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

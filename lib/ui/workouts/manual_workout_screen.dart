// Manual workout entry / retime — the form behind "Log a past workout" and
// the detail screen's "Edit times".
//
// The band's auto-detector reports the HARD-EFFORT CORE of a session, not its
// wall-clock (see `compute/manual_session.dart` for the gate constants). An
// hour of mixed-intensity training routinely surfaces as ~25 minutes, and
// until now the only session writer stamped `DateTime.now()` — so there was no
// way to say what actually happened. This screen is that way.
//
// It owns NO policy: validation is `validateManualWindow`, scoring is
// `computeManualSessionStats`, and the row shape is `buildManualSessionRow`,
// all pure and unit-tested. This file picks times and renders the verdict.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../compute/manual_session.dart';
import '../../state/app_state.dart';
import '../../theme/theme_switcher.dart';
import '../design/design.dart';
import 'workout_types.dart';

/// Push the manual-entry form. Returns true when a session was written.
///
/// [editing] is an existing session row (from `getWorkout`) when retiming;
/// null starts a blank entry.
Future<bool> showManualWorkoutScreen(
  BuildContext context, {
  Map<String, dynamic>? editing,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    themedRoute<bool>(
      (_) => ManualWorkoutScreen(editing: editing),
      fullscreenDialog: true,
      name: 'ManualWorkoutScreen',
    ),
  );
  return saved == true;
}

class ManualWorkoutScreen extends StatefulWidget {
  /// The session being retimed, or null for a fresh entry.
  final Map<String, dynamic>? editing;
  const ManualWorkoutScreen({super.key, this.editing});

  @override
  State<ManualWorkoutScreen> createState() => _ManualWorkoutScreenState();
}

class _ManualWorkoutScreenState extends State<ManualWorkoutScreen> {
  late DateTime _start;
  late DateTime _end;
  late String _type;

  /// Every saved span, for the overlap check. Loaded once; until it arrives the
  /// overlap rule simply cannot fire here — the repo re-validates at the write
  /// seam and throws [ManualWindowException], so a stale snapshot cannot slip
  /// an overlapping session through.
  List<SessionSpan> _spans = const [];

  bool _saving = false;

  /// Message under the form. [_savedUnscored] says which KIND it is: a write
  /// that succeeded but could not be scored, versus one that was refused.
  /// Keeping these apart matters — the button turns into "Done" only for the
  /// former; conflating them would let a REFUSED save close the form as though
  /// it had worked.
  String? _notice;
  bool _savedUnscored = false;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    final startTs = (e?['start_ts'] as num?)?.toInt();
    final endTs = (e?['end_ts'] as num?)?.toInt();
    if (startTs != null && endTs != null && endTs > startTs) {
      _start = DateTime.fromMillisecondsSinceEpoch(startTs * 1000).toLocal();
      _end = DateTime.fromMillisecondsSinceEpoch(endTs * 1000).toLocal();
    } else {
      // A blank entry defaults to "an hour, ending an hour ago" — near enough
      // to a just-finished session that most edits are one or two taps.
      final now = DateTime.now();
      _end = DateTime(now.year, now.month, now.day, now.hour, now.minute)
          .subtract(const Duration(hours: 1));
      _start = _end.subtract(const Duration(hours: 1));
    }
    _type = (e?['type'] as String?) ?? 'run';
    _loadSpans();
  }

  Future<void> _loadSpans() async {
    final api = context.read<AppState>().repo;
    if (api == null) return;
    try {
      final s = await api.savedSessionSpans();
      if (mounted) setState(() => _spans = s);
    } catch (_) {
      /* overlap check degrades to "not enforced here"; save still validates */
    }
  }

  int get _startSec => _start.millisecondsSinceEpoch ~/ 1000;
  int get _endSec => _end.millisecondsSinceEpoch ~/ 1000;

  ManualWindowError? get _error => validateManualWindow(
        startSec: _startSec,
        endSec: _endSec,
        nowSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        existing: _spans,
        editingId: widget.editing?['id'] as String?,
      );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start,
      // Back to the start of last year is plenty for back-filling; forward is
      // pointless — a future session is rejected anyway.
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: now,
      helpText: 'Which day?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Move BOTH ends by the same number of days so the duration survives the
      // date change — otherwise picking a date silently rewrites the length.
      final delta = _end.difference(_start);
      _start = DateTime(picked.year, picked.month, picked.day, _start.hour,
          _start.minute);
      _end = _start.add(delta);
      _notice = null;
      _savedUnscored = false;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final base = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: isStart ? 'When did you start?' : 'When did you finish?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        final delta = _end.difference(_start);
        _start = DateTime(
            _start.year, _start.month, _start.day, picked.hour, picked.minute);
        // Keep the duration when the start moves — the athlete is placing the
        // session, not resizing it.
        _end = _start.add(delta);
      } else {
        var e = DateTime(
            _start.year, _start.month, _start.day, picked.hour, picked.minute);
        // A finish time earlier in the clock than the start means the session
        // ran past midnight.
        if (!e.isAfter(_start)) e = e.add(const Duration(days: 1));
        _end = e;
      }
      _notice = null;
      _savedUnscored = false;
    });
  }

  Future<void> _pickType() async {
    final t = await pickWorkoutType(context, title: 'Workout type');
    if (t == null || !mounted) return;
    setState(() => _type = t);
  }

  Future<void> _save() async {
    if (_error != null || _saving) return;
    final api = context.read<AppState>().repo;
    if (api == null) return;
    setState(() {
      _saving = true;
      _notice = null;
      _savedUnscored = false;
    });
    try {
      final editingId = widget.editing?['id'] as String?;
      final res = editingId != null
          ? await api.setWorkoutWindow(editingId,
              startTs: _startSec, endTs: _endSec)
          : await api.logManualWorkout(
              startTs: _startSec, endTs: _endSec, type: _type);
      if (!mounted) return;
      if (res['unscored'] == true) {
        // Saved, but we cannot score it — say so plainly rather than showing a
        // workout with silent blanks where strain and calories should be.
        setState(() {
          _saving = false;
          _savedUnscored = true;
          _notice =
              'Saved. There is no heart-rate data left for that window, so '
              'strain and calories will stay blank — the band only keeps '
              'about three days of second-by-second data on the phone.';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } on ManualWindowException catch (e) {
      // The write seam re-validated and refused — most likely the saved-span
      // snapshot went stale mid-edit. Show the real reason, not "try again".
      if (mounted) {
        setState(() {
          _saving = false;
          _notice = e.error.message;
        });
        _loadSpans(); // refresh the snapshot so live validation agrees
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _notice = "Couldn't save that workout. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tone = ToneScope.of(context);
    final err = _error;
    final dur = _endSec > _startSec
        ? Duration(seconds: _endSec - _startSec)
        : Duration.zero;

    return AppScaffold(
      title: _isEdit ? 'Edit times' : 'Log a workout',
      subtitle: _isEdit
          ? 'Set the window this session actually covered'
          : 'For a session your strap missed',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(Sp.screen, 0, Sp.screen, Sp.x5),
        child: _SaveButton(
          label: _savedUnscored
              ? 'Done'
              : (_isEdit ? 'Save times' : 'Log workout'),
          enabled: (_savedUnscored || err == null) && !_saving,
          busy: _saving,
          onTap: () {
            // Once the unscored notice is showing the write already happened —
            // a second tap must close, not save the same window twice. A
            // REFUSED save also leaves a notice, so key this on the flag, never
            // on "a notice exists": popping there would report a success that
            // never occurred.
            if (_savedUnscored) {
              Navigator.of(context).pop(true);
            } else {
              _save();
            }
          },
        ),
      ),
      children: [
        SurfaceCard(
          child: Column(
            children: [
              if (!_isEdit)
                ListRow(
                  icon: workoutTypeIcon(_type),
                  title: 'Type',
                  value: workoutTypeLabel(_type),
                  onTap: _pickType,
                  divider: true,
                ),
              ListRow(
                icon: OsIcon.calendar,
                title: 'Date',
                value: _dateLabel(_start),
                onTap: _pickDate,
                divider: true,
              ),
              ListRow(
                icon: OsIcon.history,
                title: 'Start',
                value: _timeLabel(context, _start),
                onTap: () => _pickTime(isStart: true),
                divider: true,
              ),
              ListRow(
                icon: OsIcon.history,
                title: 'Finish',
                value: _timeLabel(context, _end) +
                    (_end.day != _start.day ? ' (next day)' : ''),
                onTap: () => _pickTime(isStart: false),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.x4),
        SurfaceCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.x2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DURATION',
                    style: AppText.overline.copyWith(color: tone.fgFaint)),
                const SizedBox(height: Sp.x1),
                Text(
                  _durationLabel(dur),
                  style: AppText.hero.copyWith(fontSize: 40, color: tone.fg),
                ),
              ],
            ),
          ),
        ),
        if (err != null) ...[
          const SizedBox(height: Sp.x3),
          _Note(err.message, tone: _NoteTone.error),
        ],
        if (_notice != null) ...[
          const SizedBox(height: Sp.x3),
          _Note(_notice!, tone: _NoteTone.info),
        ],
        const SizedBox(height: Sp.x4),
        Text(
          _isEdit
              ? 'Strain, calories and heart rate are recomputed from the '
                  'second-by-second data inside the new window.'
              : 'Strain, calories and heart rate are read from the '
                  'second-by-second data your strap already recorded for that '
                  'window — nothing is estimated from the duration alone.',
          style: AppText.captionMuted.copyWith(color: tone.fgMuted),
        ),
        const SizedBox(height: Sp.x6),
      ],
    );
  }
}

String _dateLabel(DateTime d) {
  const mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(d.year, d.month, d.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '${mon[d.month - 1]} ${d.day}';
}

String _timeLabel(BuildContext context, DateTime d) =>
    TimeOfDay.fromDateTime(d).format(context);

String _durationLabel(Duration d) {
  if (d <= Duration.zero) return '—';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

enum _NoteTone { error, info }

class _Note extends StatelessWidget {
  final String text;
  final _NoteTone tone;
  const _Note(this.text, {required this.tone});

  @override
  Widget build(BuildContext context) {
    final c = tone == _NoteTone.error ? AppColors.critical : AppColors.accent;
    return Container(
      padding: const EdgeInsets.all(Sp.x3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(R.cardSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tone == _NoteTone.error
                ? Icons.error_outline
                : Icons.info_outline,
            size: 18,
            color: c,
          ),
          const SizedBox(width: Sp.x2),
          Expanded(child: Text(text, style: AppText.caption.copyWith(color: c))),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;
  const _SaveButton({
    required this.label,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Pressable(
        pressedScale: enabled ? 0.97 : 1.0,
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: Sp.x4),
          decoration: BoxDecoration(
            color: enabled
                ? AppColors.accent
                : AppColors.accent.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Center(
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Text(label,
                    style: AppText.label.copyWith(color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

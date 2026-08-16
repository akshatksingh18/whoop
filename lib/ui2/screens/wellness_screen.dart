// Wellness — softer than Health, same system.
//
// Health tells you what your body did. Wellness is where you tell it back, and
// where the app explains itself. Five sub-tabs: Mind, Recovery, Habits,
// Medication, Cycle. Cycle is a SUB-TAB and not a sixth shell tab — see
// `app_shell.dart`; anything that feels like a sixth domain belongs inside the
// domain that owns it.
//
// Three rules this screen exists to hold:
//   · Habits are a CONSISTENCY, never a streak. "5 of 7 days" cannot reset to
//     zero, so a missed day costs a day rather than costing everything.
//   · Adherence is a COUNT with its window stated, and a dose still ahead of
//     you today is in no denominator.
//   · There is no drug-interaction checking. The screen does not carry a card
//     saying so either — a disclaimer for a feature that was never offered is
//     still an advert for it.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart';
import '../../data/day_label.dart';
import '../../data/journal_fields.dart';
import '../../data/med_store.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'calm_breathing.dart';
import 'cycle_screen.dart';
import 'journal_compose.dart';
import 'metric_detail.dart' show detailScaffold;
import 'sleep_detail.dart';

class WellnessScreen extends StatefulWidget {
  const WellnessScreen({super.key});

  @override
  State<WellnessScreen> createState() => _WellnessScreenState();
}

class _WellnessScreenState extends State<WellnessScreen> {
  int _tab = 0;
  static const _tabs = ['Mind', 'Recovery', 'Habits', 'Medication', 'Cycle'];

  /// Habit consistency is read over a fortnight: long enough that one bad week
  /// does not read as collapse, short enough to still be about now.
  static const _habitDays = 14;

  /// Read on every use, never captured once: the shell keeps this tab alive in
  /// its IndexedStack, so a field initialiser would still be yesterday after
  /// midnight and habit ticks would land on yesterday's date.
  String get _date => todayLabel();
  bool _loading = true;

  /// One journal write at a time. `putJournalMetrics` deletes the day and
  /// re-inserts it, so two quick taps both read the same day and the second
  /// erased the first.
  bool _writingField = false;

  Map<String, dynamic> _stress = const {};
  Map<String, dynamic> _insights = const {};
  Map<String, JournalMetricValue> _todayFields = {};
  List<JournalFieldSpec> _habits = const [];
  List<JournalFieldSpec> _fields = const [];
  Map<String, Map<String, JournalMetricValue>> _habitHistory = const {};
  List<Map<String, dynamic>> _breathing = const [];
  List<MedDef> _meds = const [];
  List<MedSlot> _slots = const [];
  ({int taken, int of}) _adherence = (taken: 0, of: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final repo = app.repo;
    final db = await LocalDb.instance;

    final meds = await MedDb.defs(db);
    final doses = await MedDb.dosesForDay(db, _date);
    final adherence = await MedDb.adherenceWindow(db, days: 7);
    final breathing = await app.breathingHistory(limit: 5);

    var stress = const <String, dynamic>{};
    var insights = const <String, dynamic>{};
    var fields = <String, JournalMetricValue>{};
    var specs = const <JournalFieldSpec>[];
    if (repo != null) {
      stress = await repo.getDayStress(_date);
      insights = await repo.getInsights();
      fields = await repo.getJournalMetrics(_date);
      specs = await repo.getJournalFields();
    }
    // Day arithmetic, not a subtracted duration: a DST day is 23 or 25 hours
    // long and `now - 13 days` lands on the wrong calendar date across one.
    final now = DateTime.now();
    final since = dayLabelOf(
      DateTime(now.year, now.month, now.day - (_habitDays - 1)),
    );
    final history = await LocalDb.journalMetricsByDay(sinceDaysEpoch: since);

    if (!mounted) return;
    setState(() {
      _meds = meds;
      _slots = slotsForDay(meds, _date, doses, now: DateTime.now());
      _adherence = adherence;
      _breathing = breathing;
      _stress = stress;
      _insights = insights;
      _todayFields = {...fields};
      // A habit is a custom field with a ceiling of one — a per-day yes/no.
      // That is exactly what journal_field_def already stores, which is why
      // there is no habit table.
      _habits = [
        for (final s in specs)
          if (s.custom && s.max == 1) s,
      ];
      _fields = specs;
      _habitHistory = history;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x4, S.x4, S.x16),
      children: [
        const ScreenTitle('Wellness'),
        SubTabs(_tabs, _tab, (i) => setState(() => _tab = i), color: C.domMind),
        const SizedBox(height: S.x5),
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else
          [_mind, _recovery, _habitsTab, _medication, _cycle][_tab](c),
      ],
    );
  }

  // ── MIND ─────────────────────────────────────────────────────────────────

  Widget _mind(BuildContext c) {
    final last = _breathing.isEmpty ? null : _breathing.first;
    final score = (_stress['stress'] as Map?)?['score'] as num?;
    final level = (_stress['stress'] as Map?)?['level'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActionCard(
          'Paced breathing',
          last == null
              ? 'Nothing yet'
              : 'Last: ${((last['seconds'] as num?) ?? 0) ~/ 60} min',
          'Begin',
          LucideIcons.wind,
          C.domMind,
          onTap: () async {
            await Navigator.of(c).push(
              MaterialPageRoute<void>(builder: (_) => const CalmBreathing()),
            );
            await _load();
          },
        ),
        const SizedBox(height: S.x4),
        MoodPicker(
          value: _todayFields['mood']?.value.round(),
          onChanged: (v) => _setField('mood', v.toDouble()),
        ),
        const SizedBox(height: S.x4),
        ActionCard(
          'Write the day down',
          // Named from the field specs the journal actually holds. The old
          // literal listed four fields and went stale the moment a custom one
          // was added.
          _journalSubtitle(),
          'Open',
          LucideIcons.notebookPen,
          C.blue,
          onTap: () async {
            await Navigator.of(c).push(
              MaterialPageRoute<void>(builder: (_) => const JournalCompose()),
            );
            await _load();
          },
        ),
        Section(
          'Stress last night',
          score == null
              ? const StatusCard(
                  'No stress reading last night',
                  'Needs a long enough resting stretch. Last night had none.',
                  icon: LucideIcons.activity,
                )
              : SignalCard(
                  LucideIcons.activity,
                  C.purple,
                  'Autonomic tension',
                  score.round().toString(),
                  unit: '/100',
                  sub: (level ?? '').toUpperCase(),
                ),
        ),
      ],
    );
  }

  /// What the journal will actually ask you, read off its own field specs.
  String _journalSubtitle() {
    final names = [for (final f in _fields) f.label.toLowerCase()];
    if (names.isEmpty) return 'Anything you want to remember about today';
    if (names.length <= 4) return '${names.join(', ')} and a note';
    return '${names.take(4).join(', ')} and '
        '${names.length - 4} more, plus a note';
  }

  Future<void> _setField(String key, double? v) async {
    final repo = context.read<AppState>().repo;
    if (repo == null || _writingField) return;
    setState(() => _writingField = true);
    try {
      // RE-READ THE DAY, do not write from the snapshot this tab loaded with.
      //
      // `postJournalMetrics` -> `putJournalMetrics` DELETES the whole day and
      // re-inserts what it is handed, so writing a merge of `_todayFields` — a
      // copy taken when the tab last loaded — silently deleted every journal
      // field written since. Open Wellness, go and write your journal from the
      // compose screen, come back without the tab reloading, tick one habit,
      // and the journal entry was gone.
      final next = {...await repo.getJournalMetrics(_date)};
      if (v == null) {
        next.remove(key);
      } else {
        next[key] = JournalMetricValue(v);
      }
      await repo.postJournalMetrics(_date, next);
      await _load();
    } finally {
      if (mounted) setState(() => _writingField = false);
    }
  }

  // ── RECOVERY ─────────────────────────────────────────────────────────────

  Widget _recovery(BuildContext c) {
    final drivers = (_stress['drivers'] as List?) ?? const [];
    final coach = _insights['sleep_coach'];
    final coachMap = coach is Map ? coach.cast<String, dynamic>() : null;
    final needSec = _nested(coachMap, 'need', 'need_sec');
    final bedMin = _nested(coachMap, 'bedtime', 'bedtime_min_of_day');
    final wakeMin = _nested(coachMap, 'wake', 'wake_min_of_day');
    final napMin = (coachMap?['nap_credit_min'] as num?)?.toDouble();
    final strainMin = (coachMap?['strain_bonus_min'] as num?)?.toDouble();
    final debtH = _nested(_insights, 'sleep_debt', 'debt_hours');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The one recommendation on this screen, and only when all three of
        // its inputs are real: a measured debt worth acting on, a learned need,
        // and a target bedtime to name. No debt, no card — the widget does not
        // get an invented reason so that it can appear.
        if (debtH != null && debtH >= .75 && needSec != null && bedMin != null)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x5),
            child: Recommendation(
              'Turn in by ${formatMinuteOfDay(bedMin.round())}',
              'You are ${_hm(debtH * 60)} down against your own need, and '
                  'tonight\'s is ${_hm(needSec / 60)}.',
              'See what last night cost you',
              color: C.indigo,
              onTap: () => Navigator.of(c).push(
                MaterialPageRoute<void>(builder: (_) => const SleepDetail()),
              ),
            ),
          ),
        Section(
          'What charged and drained you',
          drivers.isEmpty
              ? const StatusCard(
                  'No readiness drivers yet',
                  'Needs enough nights to know what normal looks like for you.',
                  icon: LucideIcons.sparkles,
                )
              : Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: Column(
                    children: [
                      for (final d in drivers)
                        if (d is Map)
                          DriverRow(
                            label: (d['label'] ?? '').toString(),
                            detail: (d['detail'] ?? '').toString(),
                          ),
                    ],
                  ),
                ),
        ),
        Section(
          'Sleep need tonight',
          needSec == null
              ? const StatusCard(
                  'No sleep need yet',
                  'Not enough of them yet.',
                  icon: LucideIcons.bedDouble,
                )
              : Surface(
                  child: Column(
                    children: [
                      MetricRow(
                        LucideIcons.bedDouble,
                        C.blue,
                        'Tonight\'s need',
                        _hm(needSec / 60),
                      ),
                      // Null here means "we do not know", which is why it is a
                      // missing row rather than "+0 min".
                      if (debtH != null)
                        MetricRow(
                          LucideIcons.trendingDown,
                          C.orange,
                          'Sleep debt',
                          _hm(debtH * 60),
                        ),
                      if (strainMin != null)
                        MetricRow(
                          LucideIcons.flame,
                          C.purple,
                          'Added for strain',
                          '${strainMin.round()}',
                          unit: 'min',
                        ),
                      if (napMin != null)
                        MetricRow(
                          LucideIcons.sun,
                          C.yellow,
                          'Credited from naps',
                          '${napMin.round()}',
                          unit: 'min',
                        ),
                      if (bedMin != null)
                        MetricRow(
                          LucideIcons.moon,
                          C.indigo,
                          'Target bedtime',
                          formatMinuteOfDay(bedMin.round()),
                        ),
                      if (wakeMin != null)
                        MetricRow(
                          LucideIcons.sunrise,
                          C.orange,
                          'Target wake',
                          formatMinuteOfDay(wakeMin.round()),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── CYCLE ────────────────────────────────────────────────────────────────

  /// Owns its own load: the tab is off for most users and its query touches two
  /// tables plus 120 derived days, which nobody should pay for by opening Mind.
  Widget _cycle(BuildContext c) => const CycleTab();

  // ── HABITS ───────────────────────────────────────────────────────────────

  Widget _habitsTab(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in _habits)
          Padding(
            padding: const EdgeInsets.only(bottom: S.x3),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          h.label,
                          style: F.body.copyWith(
                            color: p.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // A habit you typed had no way out short of "Delete
                      // everything": the delete path existed end to end and
                      // nothing reached it.
                      Pressable(
                        semanticLabel: 'Remove ${h.label}',
                        onTap: () => _confirmRemoveHabit(h),
                        child: Padding(
                          padding: const EdgeInsets.only(right: S.x3),
                          child: Icon(
                            LucideIcons.trash2,
                            size: 18,
                            color: p.ink3,
                          ),
                        ),
                      ),
                      _Check(
                        on: (_todayFields[h.key]?.value ?? 0) >= 1,
                        // Null while a write is in flight: the tick is a
                        // read-modify-write of the whole day, and a second tap
                        // during the first one used to erase it.
                        onTap: _writingField
                            ? null
                            : () => _setField(
                                h.key,
                                (_todayFields[h.key]?.value ?? 0) >= 1
                                    ? null
                                    : 1,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x3),
                  Consistency(
                    _habitDaysDone(h.key),
                    _habitDays,
                    'Days you did it',
                    C.domMind,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: S.x4),
        BigButton(
          'Add a habit',
          icon: LucideIcons.plus,
          color: C.domMind,
          soft: true,
          onTap: () => _addHabit(c),
        ),
        // MIND-01/04/12 — the whole dose-response and habit-difference half of
        // journal analysis, plus the weekday test, behind ONE door. It has
        // lived here computed-and-discarded for months; putting the rows on
        // this tab would bury the thing the tab is for, which is ticking.
        const SizedBox(height: S.x5),
        ActionCard(
          'What you log, against your numbers',
          'Dose, habit difference, and the day of the week',
          'Open',
          LucideIcons.scatterChart,
          C.domMind,
          onTap: () => Navigator.of(c).push(
            MaterialPageRoute<void>(builder: (_) => const JournalFindings()),
          ),
        ),
      ],
    );
  }

  int _habitDaysDone(String key) {
    var n = 0;
    for (final day in _habitHistory.values) {
      if ((day[key]?.value ?? 0) >= 1) n++;
    }
    return n;
  }

  /// Remove the habit, keep its history.
  ///
  /// `journal_field_def` deliberately keeps a deleted field's recorded values
  /// (see db.dart's note on the table) — they were real answers. A "delete"
  /// that quietly keeps data is as much of a surprise as one that quietly loses
  /// it, so the confirm says which this is.
  Future<void> _confirmRemoveHabit(JournalFieldSpec h) async {
    final ok = await confirmRemove(
      context,
      title: 'Remove ${h.label}?',
      body: 'It stops being asked. The days you already recorded stay.',
    );
    if (!ok || !mounted) return;
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    await repo.deleteCustomJournalField(h.key);
    await _load();
  }

  Future<void> _addHabit(BuildContext c) async {
    final name = await _askName(c, 'Add a habit', 'Walk after lunch');
    if (name == null || name.isEmpty || !mounted) return;
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    await repo.postCustomJournalField(
      JournalFieldSpec(
        key: customJournalFieldKey(name),
        label: name,
        kind: JournalFieldKind.rating,
        unit: '',
        max: 1,
        step: 1,
        custom: true,
      ),
    );
    await _load();
  }

  // ── MEDICATION ───────────────────────────────────────────────────────────

  Widget _medication(BuildContext c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_meds.isEmpty)
          StatusCard(
            'Nothing scheduled',
            'Add what you take and when.',
            fix: 'Add a medication',
            icon: LucideIcons.pill,
            onFix: () => _addMed(c),
          )
        else ...[
          Surface(
            pad: const EdgeInsets.symmetric(horizontal: S.x4),
            child: Column(
              children: [
                for (final s in _slots)
                  MedRow(
                    slot: s,
                    onTap: () => _markDose(s),
                    // Same exit the habits list got. A course you finished, or
                    // a name you mistyped, used to keep coming due every day
                    // and dragging adherence down with nothing but "Delete
                    // everything" to stop it.
                    onRemove: () => _confirmRemoveMed(s.def),
                  ),
              ],
            ),
          ),
          Section(
            'Adherence',
            // An empty denominator is not an adherence of nothing. Consistency
            // would print "0 of 0 days" with an empty bar under it, which reads
            // as a failure; the reason is the honest answer until a dose has
            // actually come due.
            _adherence.of == 0
                ? const StatusCard(
                    'Nothing to score yet',
                    'No scheduled doses have come due yet.',
                    icon: LucideIcons.pill,
                  )
                : Surface(
                    child: Consistency(
                      _adherence.taken,
                      _adherence.of,
                      'Taken, of those scheduled in the last seven days.',
                      C.blue,
                      // Doses, not days — three a day over a week is 21 of
                      // them inside a seven-day window.
                      unit: 'doses',
                    ),
                  ),
          ),
          const SizedBox(height: S.x4),
          BigButton(
            'Add a medication',
            icon: LucideIcons.plus,
            color: C.domMind,
            soft: true,
            onTap: () => _addMed(c),
          ),
        ],
      ],
    );
  }

  Future<void> _markDose(MedSlot s) async {
    final db = await LocalDb.instance;
    await MedDb.mark(
      db,
      medKey: s.def.key,
      date: s.date,
      slotMin: s.slotMin,
      taken: s.state != DoseState.taken,
    );
    await _load();
  }

  /// Remove the medication, keep the doses.
  ///
  /// `MedDb.deleteDef` keeps `med_dose` on purpose (see its note): those doses
  /// were taken, and the CSV export still carries them. What stops is the
  /// schedule — and with it the empty denominator that was dragging adherence
  /// down every day after the course ended.
  Future<void> _confirmRemoveMed(MedDef d) async {
    final ok = await confirmRemove(
      context,
      title: 'Remove ${d.label}?',
      body:
          'It stops being scheduled and stops counting towards adherence. '
          'The doses you already marked stay.',
    );
    if (!ok || !mounted) return;
    await MedDb.deleteDef(await LocalDb.instance, d.key);
    await _load();
  }

  Future<void> _addMed(BuildContext c) async {
    final name = await _askName(c, 'Add a medication', 'Vitamin D');
    if (name == null || name.isEmpty) return;
    if (!c.mounted) return;
    final at = await showTimePicker(
      context: c,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'When do you take it?',
    );
    if (at == null) return;
    final db = await LocalDb.instance;
    await MedDb.putDef(
      db,
      MedDef(
        key: MedDb.keyFor(name),
        label: name,
        // Dose is left null — "as directed" is a real answer, and demanding a
        // number to get a reminder is how a checklist stops being used.
        schedule: [
          MedSchedule(at.hour * 60 + at.minute, const [1, 2, 3, 4, 5, 6, 7]),
        ],
      ),
    );
    await _load();
  }

  Future<String?> _askName(BuildContext c, String title, String hint) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: c,
      builder: (d) => AlertDialog(
        backgroundColor: P.of(d).card,
        title: Text(title, style: F.head.copyWith(color: P.of(d).ink)),
        content: OsTextField(controller: ctrl, label: 'Name', hint: hint),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: Text('Cancel', style: F.body.copyWith(color: P.of(d).ink2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(ctrl.text.trim()),
            child: Text(
              'Add',
              style: F.body.copyWith(color: P.of(d).on(C.domMind)),
            ),
          ),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }
}

// ── helpers ────────────────────────────────────────────────────────────────

/// Pull a number out of a nested `Metric` envelope whose `value` is itself an
/// object — `{value: {need_sec: …}}`. Returns null rather than parsing the
/// envelope as a scalar, which would read a real value object as an absence.
double? _nested(Map<String, dynamic>? blk, String key, String field) {
  final m = blk?[key];
  if (m is! Map) return null;
  final v = m['value'];
  if (v is Map) return (v[field] as num?)?.toDouble();
  return (v as num?)?.toDouble();
}

String _hm(double minutes) {
  final sign = minutes < 0 ? '−' : '';
  final t = minutes.abs().round();
  return t < 60 ? '$sign${t}m' : '$sign${t ~/ 60}h ${t % 60}m';
}

/// One readiness driver. Label and detail only — the glass box does not emit
/// per-driver point contributions, so this row does not pretend to have them.
class DriverRow extends StatelessWidget {
  const DriverRow({super.key, required this.label, required this.detail});

  final String label, detail;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.dot, size: 18, color: p.on(C.domMind)),
          const SizedBox(width: S.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: F.body.copyWith(color: p.ink)),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: F.over.copyWith(color: p.ink3, height: 1.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One scheduled dose. A slot still ahead of you reads as upcoming, never as a
/// miss — that distinction is the whole reason `taken_ts` is nullable.
class MedRow extends StatelessWidget {
  const MedRow({super.key, required this.slot, this.onTap, this.onRemove});

  final MedSlot slot;
  final VoidCallback? onTap;

  /// Removes the whole medication, not this one dose. Null hides the control.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final taken = slot.state == DoseState.taken;
    return Pressable(
      onTap: onTap,
      semanticLabel: '${slot.def.label} at ${slot.timeLabel}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: p.wash(C.blue),
                borderRadius: R.rMd,
              ),
              child: Icon(LucideIcons.pill, size: 17, color: p.on(C.blue)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    slot.def.label,
                    style: F.body.copyWith(color: taken ? p.ink3 : p.ink),
                  ),
                  Text(
                    '${slot.def.doseLabel} · ${slot.timeLabel} · '
                    '${_stateLabel(slot.state)}',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            if (onRemove != null)
              Pressable(
                semanticLabel: 'Remove ${slot.def.label}',
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.only(right: S.x3),
                  child: Icon(LucideIcons.trash2, size: 18, color: p.ink3),
                ),
              ),
            _Check(on: taken, onTap: null),
          ],
        ),
      ),
    );
  }

  static String _stateLabel(DoseState s) => switch (s) {
    DoseState.taken => 'taken',
    DoseState.skipped => 'skipped',
    DoseState.missed => 'not taken',
    DoseState.upcoming => 'due later',
  };
}

class _Check extends StatelessWidget {
  const _Check({required this.on, required this.onTap});
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final box = AnimatedContainer(
      duration: motion(c, Motion.base),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? p.fill(C.green) : p.card2,
        border: on ? null : Border.all(color: p.line, width: 1.6),
      ),
      child: on
          ? Icon(LucideIcons.check, size: 15, color: p.inkOnFill)
          : const SizedBox.shrink(),
    );
    if (onTap == null) return box;
    return Pressable(
      semanticLabel: on ? 'Done' : 'Mark done',
      onTap: onTap,
      child: box,
    );
  }
}

// ══════════════════ WHAT YOU LOG, AGAINST YOUR NUMBERS ══════════════════
//
// MIND-01 (dose response), MIND-04 (habits), MT-06 (caffeine timing),
// MT-07 (alcohol phrasing) and MIND-12 (weekday) all answer the same question
// from the same place, so they are one screen behind one tap rather than five
// cards competing on the Habits tab.
//
// EVERYTHING HERE IS ASSOCIATION ON YOUR OWN DAYS. Never cause, never a
// recommendation, never a nudge. The confound is total and stated: the days you
// do a thing are days you were already that kind of day.
//
// The empty state is the DEFAULT outcome, not an error. 9 built-in numeric
// fields × 4 outcomes is 36 simultaneous tests, so a per-test gate manufactures
// about two findings per user out of pure noise; analytics corrects the whole
// grid with Benjamini-Hochberg and most people will see nothing. A screen that
// cannot say "nothing separated itself" is a screen that will invent something.

class JournalFindings extends StatefulWidget {
  /// Non-null skips the repository, the way every other detail screen here
  /// takes its fixture.
  final List<Map<String, dynamic>>? rows;
  final Map<String, dynamic>? weekday;

  const JournalFindings({super.key, this.rows, this.weekday});

  @override
  State<JournalFindings> createState() => _JournalFindingsState();
}

class _JournalFindingsState extends State<JournalFindings> {
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic> _weekday = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.rows != null) {
      _rows = widget.rows!;
      _weekday = widget.weekday ?? const {};
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    if (repo == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final j = await repo.getJournalInsights(range: '90d');
      final w = await repo.getWeekdayEffect();
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final e in (j['numeric_insights'] as List? ?? const []))
            if (e is Map) e.cast<String, dynamic>(),
        ];
        _weekday = w;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    if (_loading) {
      return detailScaffold(c, 'What you log', const [
        SizedBox(height: S.x8),
        Center(child: CircularProgressIndicator()),
      ]);
    }
    final p = P.of(c);
    final doses = [
      for (final r in _rows)
        if (r['binary'] != true) r,
    ];
    final habits = [
      for (final r in _rows)
        if (r['binary'] == true) r,
    ];
    return detailScaffold(c, 'What you log', [
      const SizedBox(height: S.x2),
      if (_rows.isEmpty)
        const StatusCard(
          'Nothing separated itself yet',
          'Everything you log is tested against your recovery, HRV, resting '
              'heart rate and sleep efficiency at once, and the bar is set so '
              'that running that many comparisons cannot manufacture a result. '
              'Nothing has cleared it.',
          icon: LucideIcons.scatterChart,
        )
      else ...[
        if (habits.isNotEmpty) Section('The days you did it', _list(c, habits)),
        if (doses.isNotEmpty)
          Section('How much, and what followed', _list(c, doses)),
        const SizedBox(height: S.x2),
        Text(
          'Association on your own days — never cause. The days you do a thing '
          'are days you were already that kind of day. Corrected together for '
          'the number of comparisons; anything that did not survive is simply '
          'not here.',
          style: F.over.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
      Section('Which day of the week', _weekdayCard(c)),
    ]);
  }

  Widget _list(BuildContext c, List<Map<String, dynamic>> rows) => Surface(
    pad: const EdgeInsets.symmetric(horizontal: S.x4),
    child: Column(
      children: [
        for (final r in rows)
          DriverRow(label: _headline(r), detail: _detail(r)),
      ],
    ),
  );

  // ── copy ────────────────────────────────────────────────────────────────

  /// MT-07's whole change: the outcome's own units on the days she logged it,
  /// not a rank correlation read out loud. "On the 11 nights you logged
  /// alcohol, your resting HR ran 6 bpm higher" is the same finding the rho
  /// carried and a sentence a person can check against their own memory.
  String _headline(Map<String, dynamic> r) {
    final field = (r['field_label'] ?? '').toString();
    final outcome = (r['outcome_label'] ?? '').toString();
    final unit = (r['unit'] ?? '').toString();
    if (r['binary'] == true) {
      final delta = (r['delta'] as num?)?.toDouble() ?? 0;
      return 'On the ${r['n_with']} days you logged $field, $outcome ran '
          '${_amount(delta.abs(), unit)} ${delta > 0 ? 'higher' : 'lower'}';
    }
    final n = r['n'];
    final slope = (r['slope_per_unit'] as num?)?.toDouble();
    final rho = (r['rho'] as num?)?.toDouble() ?? 0;
    if (slope == null) {
      return 'On the $n days you logged $field, more of it went with '
          '${rho > 0 ? 'higher' : 'lower'} $outcome';
    }
    final (per, step) = _perUnit(r);
    return 'On the $n days you logged $field, $outcome ran '
        '${_amount((slope * per).abs(), unit)} '
        '${slope > 0 ? 'higher' : 'lower'} per $step';
  }

  String _detail(Map<String, dynamic> r) {
    if (r['binary'] == true) {
      final d = (r['cohens_d'] as num?)?.toDouble();
      return 'Against the ${r['n_without']} days you did not'
          '${d == null ? '' : ' · d ${d.abs().toStringAsFixed(1)}'}.';
    }
    final lo = (r['rho_low'] as num?)?.toDouble();
    final hi = (r['rho_high'] as num?)?.toDouble();
    final rho = (r['rho'] as num?)?.toDouble();
    final ci = (lo == null || hi == null)
        ? ''
        : ' (${lo.toStringAsFixed(2)} to ${hi.toStringAsFixed(2)})';
    final base = rho == null
        ? ''
        : 'Rank correlation ${rho.toStringAsFixed(2)}$ci. ';
    // MT-06's own ceiling, said where the finding is: `at_min` is the LAST
    // occurrence, so timing cannot tell two coffees from five, and a late
    // stressful day produces both the late coffee and the bad night.
    if (r['field'] == 'caffeine_last_min') {
      return '${base}This is your LAST caffeine of the day only — two cups and '
          'five look identical here, so "later" can quietly mean "more". A '
          'long, stressful day produces both the late coffee and the poor '
          'night.';
    }
    return base.trim();
  }

  /// How to say one step of this field. Minutes-past-midnight is unreadable per
  /// minute, so caffeine timing is stated per HOUR later — a slope, never a
  /// cutoff time, which is a threshold read off a dozen self-reported points.
  (double, String) _perUnit(Map<String, dynamic> r) {
    if (r['field'] == 'caffeine_last_min') return (60.0, 'hour later');
    final u = (r['field_unit'] ?? '').toString();
    // Singular: the phrase is "per unit", "per mg", "per point".
    final one = u.isEmpty
        ? 'point'
        : (u.endsWith('s') ? u.substring(0, u.length - 1) : u);
    return (1.0, one);
  }

  String _amount(double v, String unit) {
    final n = v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
    return unit.isEmpty ? n : '$n $unit';
  }

  // ── MIND-12 ─────────────────────────────────────────────────────────────

  /// Two gates, and both of them refusing is the normal answer. Kruskal-Wallis
  /// across the seven groups, then a permutation test on the biggest gap — the
  /// second one is what pays for having looked at seven days and reported the
  /// worst. Without it this is a machine for manufacturing weekday
  /// superstitions.
  Widget _weekdayCard(BuildContext c) {
    if (_weekday['present'] != true) {
      return const StatusCard(
        'Not enough weeks yet',
        'Testing seven weekdays against each other needs at least eight weeks '
            'of derived days, with five of every weekday in them.',
        icon: LucideIcons.calendarDays,
      );
    }
    if (_weekday['meaningful'] != true) {
      return const StatusCard(
        'No day of the week stands out',
        'Your seven weekdays are not separable from each other once looking at '
            'all seven is paid for.',
        icon: LucideIcons.calendarDays,
      );
    }
    final day = (_weekday['peak_weekday'] as num?)?.toInt() ?? 1;
    final delta = (_weekday['peak_delta'] as num?)?.toDouble() ?? 0;
    final n = (_weekday['n_by_weekday'] as Map?)?['$day'];
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: DriverRow(
        label:
            '${_weekdayName(day)}s: readiness runs '
            '${delta.abs().round()} ${delta > 0 ? 'higher' : 'lower'} than '
            'your overall median',
        detail:
            'From $n of them. A weekday is a container for what you do on '
            'it, not a cause — nothing here is advice.',
      ),
    );
  }
}

const _kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _weekdayName(int weekday) => _kWeekdayNames[(weekday - 1).clamp(0, 6)];

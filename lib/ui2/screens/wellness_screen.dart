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
import '../../models/metric.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'calm_breathing.dart';
import 'cycle_screen.dart';
import 'journal_compose.dart';
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

  final String _date = todayLabel();
  bool _loading = true;

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
      _habits = [for (final s in specs) if (s.custom && s.max == 1) s];
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
                  'It is measured from a long enough resting window to read '
                      'autonomic tension, and last night did not have one. '
                      'There is deliberately no stand-in number.',
                  icon: LucideIcons.activity,
                )
              : SignalCard(
                  LucideIcons.activity,
                  C.purple,
                  'Autonomic tension',
                  score.round().toString(),
                  unit: '/100',
                  sub: (level ?? '').toUpperCase(),
                  // The block is a full envelope — value, confidence, tier.
                  conf: ConfX.of(Metric.parse(_stress['stress'])),
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
    if (repo == null) return;
    final next = {..._todayFields};
    if (v == null) {
      next.remove(key);
    } else {
      next[key] = JournalMetricValue(v);
    }
    await repo.postJournalMetrics(_date, next);
    await _load();
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
                  'They come from the cross-day readiness breakdown, which '
                      'needs enough nights to know what normal looks like for '
                      'you before it can say what moved.',
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
        if (drivers.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Text(
            'These are the inputs that moved readiness, not a points ledger — '
            'the breakdown does not emit per-driver point deltas, so none are '
            'invented here.',
            style: F.cap.copyWith(color: P.of(c).ink3, height: 1.45),
          ),
        ],
        Section(
          'Sleep need tonight',
          needSec == null
              ? const StatusCard(
                  'No sleep need yet',
                  'Your need is learned from your own unconstrained nights, '
                      'not from a rounded eight hours. Until there are enough '
                      'of them there is no honest number to show.',
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
                        conf: _confOf(coachMap, 'need'),
                      ),
                      // Null here means "we do not know", which is why it is a
                      // missing row rather than "+0 min".
                      if (debtH != null)
                        MetricRow(
                          LucideIcons.trendingDown,
                          C.orange,
                          'Sleep debt',
                          _hm(debtH * 60),
                          conf: _confOf(_insights, 'sleep_debt'),
                        ),
                      if (strainMin != null)
                        MetricRow(
                          LucideIcons.flame,
                          C.purple,
                          'Added for strain',
                          '${strainMin.round()}',
                          unit: 'min',
                          // A plain minute adjustment the coach emits beside
                          // the need it adjusts — it carries that need's tier.
                          conf: _confOf(coachMap, 'need'),
                        ),
                      if (napMin != null)
                        MetricRow(
                          LucideIcons.sun,
                          C.yellow,
                          'Credited from naps',
                          '${napMin.round()}',
                          unit: 'min',
                          conf: _confOf(coachMap, 'need'),
                        ),
                      if (bedMin != null)
                        MetricRow(
                          LucideIcons.moon,
                          C.indigo,
                          'Target bedtime',
                          formatMinuteOfDay(bedMin.round()),
                          conf: _confOf(coachMap, 'bedtime'),
                        ),
                      if (wakeMin != null)
                        MetricRow(
                          LucideIcons.sunrise,
                          C.orange,
                          'Target wake',
                          formatMinuteOfDay(wakeMin.round()),
                          conf: _confOf(coachMap, 'wake'),
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
    if (_habits.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatusCard(
            'No habits yet',
            'A habit here is a plain yes-or-no you answer once a day. It costs '
                'a row, not a new part of the app — the journal already stores '
                'exactly this shape.',
            fix: 'Add a habit',
            icon: LucideIcons.circleCheck,
            onFix: () => _addHabit(c),
          ),
          const SizedBox(height: S.x4),
          Text(
            'No streaks. A missed day never resets anything — the count '
            'repairs itself.',
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      );
    }
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
                      _Check(
                        on: (_todayFields[h.key]?.value ?? 0) >= 1,
                        onTap: () => _setField(
                          h.key,
                          (_todayFields[h.key]?.value ?? 0) >= 1 ? null : 1,
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
        const SizedBox(height: S.x2),
        Text(
          'No streaks. A missed day never resets anything — the count repairs '
          'itself.',
          style: F.cap.copyWith(color: p.ink3, height: 1.5),
        ),
        const SizedBox(height: S.x4),
        BigButton(
          'Add a habit',
          icon: LucideIcons.plus,
          color: C.domMind,
          soft: true,
          onTap: () => _addHabit(c),
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
            'Add what you take and when, and this becomes a checklist plus an '
                'honest adherence count. Nothing leaves the phone.',
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
                  ),
              ],
            ),
          ),
          Section(
            'Adherence',
            Surface(
              child: Consistency(
                _adherence.taken,
                _adherence.of,
                _adherence.of == 0
                    ? 'No dose has come due in the last seven days'
                    : 'Doses taken of those scheduled in the last seven days. '
                          'A dose still ahead of you today is not counted '
                          'against you.',
                C.blue,
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
/// The stated confidence of the envelope a nested field came out of. Every
/// Recovery row used to pass a literal `Conf.estimated` next to a number the
/// pipeline had already rated.
Conf _confOf(Map<String, dynamic>? blk, String key) {
  final m = blk?[key];
  if (m is! Map || m['value'] == null) return Conf.none;
  final env = Metric.parse(m);
  return ConfX.of(Metric(
    // The value is real — it is one field down, where Metric.parse cannot see
    // it. Only the tier and confidence are being read here.
    value: 1,
    confidence: env.confidence == 0 ? 1 : env.confidence,
    tier: env.tier,
  ));
}

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
  const MedRow({super.key, required this.slot, this.onTap});

  final MedSlot slot;
  final VoidCallback? onTap;

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

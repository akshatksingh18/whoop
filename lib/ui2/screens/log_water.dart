// Where the hydration reminder lands.
//
// One screen, one control. The notification says "tap to log a glass", so the
// destination has to be a place where the next tap logs a glass — the Nutrition
// tab is not that, because the water row sits below the day's occasions and
// needs a scroll to reach.
//
// Nothing is re-invented here: the value is the existing `water_ml` journal
// field, written through the same repo call the Nutrition row uses, and the
// stepper is the same `FieldStepper` the journal uses. This screen owns only
// the framing.
//
// Water is a reminder, not a measurement. It may be logged; nothing here — and
// nothing downstream — may ever score it, streak it, or call a number good.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../data/journal_fields.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'journal_compose.dart' show FieldStepper;

class LogWaterScreen extends StatefulWidget {
  const LogWaterScreen({super.key});

  @override
  State<LogWaterScreen> createState() => _LogWaterScreenState();
}

class _LogWaterScreenState extends State<LogWaterScreen> {
  /// Read on every use: this screen can be opened by a notification at 21:50
  /// and left standing past midnight.
  String get _date => todayLabel();

  static final JournalFieldSpec _spec = kJournalFieldsByKey['water_ml']!;

  double? _ml;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    final v =
        repo == null ? null : (await repo.getJournalMetrics(_date))['water_ml'];
    if (!mounted) return;
    setState(() {
      _ml = v?.value;
      _loading = false;
    });
  }

  /// Absent stays absent: a blank field is "did not say", and stepping down
  /// from zero returns it there rather than pinning a zero nobody asserted.
  Future<void> _set(double? next) async {
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    setState(() => _ml = next);
    final all = await repo.getJournalMetrics(_date);
    await repo.postJournalMetrics(_date, {
      ...all,
      if (next != null) 'water_ml': JournalMetricValue(next),
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x16),
          children: [
            const NavBar('Water', sub: 'TODAY'),
            const SizedBox(height: S.x2),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Surface(
                child: FieldStepper(
                  spec: _spec,
                  value: _ml,
                  onChanged: _set,
                ),
              ),
            const SizedBox(height: S.x3),
            Text(
              'A log, not a measurement. The band reads no hydration and '
              'nothing here is scored.',
              style: F.cap.copyWith(color: p.ink3, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

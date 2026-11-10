// Naps and durable user corrections, projected onto retained detector proposals.
// Manual entries are self reports without invented stages or confidence. A
// rejected detector window remains reversible. Corrections appear immediately;
// sleep-need recalculation runs separately and exposes its own pending/error state.

import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/nap_edits.dart';
import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/metric.dart' show whyFromNote;
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show clockOfTs, hm, repoOf;
import 'metric_detail.dart' show dayNavRow, detailScaffold;

class NapsData {
  const NapsData({
    this.day,
    this.days = const [],
    this.naps = const [],
    this.napMin,
    this.note,
    this.judged = false,
    this.rejected = const [],
  });

  final String? day;
  final List<String> days;

  /// The MERGED list — detected naps with the user's edits replayed over them,
  /// which is the same list `nap_min` is summed from.
  final List<Map<String, dynamic>> naps;

  final int? napMin;

  /// The detector's own reason, when it had one. Never a sentence written here.
  final String? note;

  /// Whether the day produced a nap answer at all. An empty [naps] on a judged
  /// day is the measured "no naps"; on an unjudged day it is "we could not
  /// tell", and the two must not read the same.
  final bool judged;

  /// The windows the user has rejected — kept visible so a removal is
  /// reversible. A suppression nobody can see is one nobody can undo.
  final List<Map<String, dynamic>> rejected;

  static Future<NapsData> load(LocalRepository repo, {String? want}) async {
    final days = List<String>.of(await repo.availableDays());
    final day = want ?? todayLabel();
    if (!days.contains(day)) days.insert(0, day);
    final d = await repo.getDayNaps(day);
    return NapsData(
      day: day,
      days: days,
      naps: [
        for (final n in (d['naps'] as List?) ?? const [])
          (n as Map).cast<String, dynamic>(),
      ],
      napMin: (d['nap_min'] as num?)?.round(),
      note: d['note'] as String?,
      judged: d['naps'] is List,
      rejected: [
        for (final r in await LocalDb.napEdits(day))
          if (r['source'] == 'rejected') r,
      ],
    );
  }
}

class NapsScreen extends StatefulWidget {
  const NapsScreen({super.key, this.day});

  final String? day;

  @override
  State<NapsScreen> createState() => _NapsScreenState();
}

class _NapsScreenState extends State<NapsScreen> with RevisionReload {
  NapsData? _d;
  String? _day;
  bool _busy = false;
  String? _failed;

  @override
  void initState() {
    super.initState();
    _day = widget.day;
    _load();
  }

  @override
  void reload() => _load();
  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      if (mounted) setState(() => _failed = 'Naps could not load. Try again.');
      return;
    }
    final token = beginRead(#naps);
    try {
      final d = await NapsData.load(repo, want: _day);
      if (stillNewest(#naps, token)) setState(() => (_d = d, _failed = null));
    } catch (_) {
      if (stillNewest(#naps, token))
        setState(
          () =>
              _failed = 'Naps could not load. Your edits are saved. Try again.',
        );
    }
  }

  void _goDay(String day) {
    setState(() {
      _day = day;
      _d = null;
    });
    _load();
  }

  Future<void> _edit(Future<void> Function() write) async {
    if (_busy) return;
    final app = context.read<AppState>();
    final day = _d?.day ?? _day ?? todayLabel();
    setState(() => (_busy = true, _failed = null));
    try {
      await write();
      // Do not hold the UI behind a full derivation. This read projects the
      // saved correction onto retained detector proposals, including restore.
      if (mounted) await _load();
      unawaited(app.reanalyzeForNapEdit(day).catchError((Object e) {}));
    } catch (_) {
      if (mounted)
        setState(() => _failed = 'The edit could not save. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(String day, Map<String, dynamic> nap) => _edit(() async {
    final start = nap['start'] as int, end = nap['end'] as int;
    // Their own entry is DELETED; the detector's is SUPPRESSED. Storing a
    // rejection for something the user typed would leave two rows fighting
    // over the same afternoon, and re-logging it later would land on a
    // window that is still being suppressed.
    if (nap['source'] == 'manual') {
      await LocalDb.deleteNapEdit(day, start);
    } else {
      await LocalDb.putNapEdit(
        dayId: day,
        startTs: start,
        endTs: end,
        source: 'rejected',
      );
    }
  });

  Future<void> _restore(
    String day,
    Map<String, dynamic> rejected,
  ) => _edit(() async {
    final start = rejected['start_ts'] as int;
    final repo = repoOf(context)!;
    final proposals = (await repo.getDayNaps(day))['proposals'];
    final end = rejected['end_ts'] as int;
    final hasProposal =
        proposals is List &&
        proposals.any(
          (p) =>
              p is Map &&
              p['start'] is num &&
              p['end'] is num &&
              (p['start'] as num) < end &&
              start < (p['end'] as num),
        );
    if (!hasProposal) {
      // Pre-73 removal may have discarded the detector proposal. The user now
      // confirms this window: restore as their report, without invented stages.
      await LocalDb.putNapEdit(
        dayId: day,
        startTs: start,
        endTs: rejected['end_ts'] as int,
        source: 'manual',
      );
    } else {
      await LocalDb.deleteNapEdit(day, start);
    }
  });

  /// Two pickers on the day being shown. Deliberately not a duration: people
  /// remember when they lay down and when they got up, not how long it was.
  Future<void> _log(String day) async {
    final base = DateTime.tryParse(day);
    if (base == null) return;
    final l = AppLocalizations.of(context);
    final from = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 14, minute: 0),
      helpText: withEnglishFallback(l).napsFellAsleepHelp,
    );
    if (from == null || !mounted) return;
    final to = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (from.hour + 1) % 24, minute: from.minute),
      helpText: withEnglishFallback(l).napsWokeUpHelp,
    );
    if (to == null || !mounted) return;

    final start = DayClock.onDate(day, from.hour, from.minute);
    // An end at or before the start crossed midnight. `day + 1`, not a
    // Duration: this is calendar arithmetic over a possible DST boundary.
    var end = DayClock.wallTime(
      start,
      start.year,
      start.month,
      start.day,
      to.hour,
      to.minute,
    );
    if (!end.isAfter(start)) {
      end = DayClock.wallTime(
        start,
        start.year,
        start.month,
        start.day + 1,
        to.hour,
        to.minute,
      );
    }
    final s = start.millisecondsSinceEpoch ~/ 1000;
    final e = end.millisecondsSinceEpoch ~/ 1000;

    // Both refusals are the shared rules, not a second copy written here.
    if (!manualNapWindowIsValid(s, e)) {
      setState(
        () => _failed =
            withEnglishFallback(l).napsInvalidWindow,
      );
      return;
    }
    // Build 93 (Codex audit): only a nap that has ended can be logged; a
    // future hour would count as sleep that did not happen.
    if (end.isAfter(clock.now())) {
      setState(
        () => _failed = 'That nap has not ended yet. Log it once you are up.',
      );
      return;
    }
    if (napOverlapsExisting(s, e, _d?.naps ?? const [])) {
      setState(
        () => _failed =
            withEnglishFallback(l).napsOverlap,
      );
      return;
    }
    await _edit(
      () => LocalDb.putNapEdit(
        dayId: day,
        startTs: s,
        endTs: e,
        source: 'manual',
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final status = napUpdateState(c);
    final d = _d;
    if (d == null) {
      return detailScaffold(c, withEnglishFallback(l).napsTitle, [
        if (_failed != null)
          StatusCard(
            'Naps could not load',
            _failed!,
            fix: 'Retry',
            onFix: _load,
          )
        else
          Padding(
            padding: EdgeInsets.only(top: S.x8),
            child: Center(child: CircularProgressIndicator()),
          ),
      ]);
    }
    final day = d.day;

    return detailScaffold(c, withEnglishFallback(l).napsTitle, [
      ...dayNavRow(day, d.days, _goDay),
      if (!d.judged)
        // THE DETECTOR'S OWN REASON when it left one — 'too little 1 Hz data
        // to assess naps', 'nap detection failed for this day'. The sentence
        // below is only for a day that recorded no reason at all.
        StatusCard(
          withEnglishFallback(l).napsNoReadingTitle,
          whyFromNote(d.note, unit: 'days') ??
              l?.napsNoReadingBody ??
              'Naps are worked out from the same 1 Hz recording the rest of '
                  'the day is, and this day does not have enough of it.',
          icon: LucideIcons.circleHelp,
        )
      else if (d.naps.isEmpty)
        StatusCard(
          withEnglishFallback(l).napsEmptyTitle,
          withEnglishFallback(l).napsEmptyBody,
          icon: LucideIcons.sun,
        )
      else ...[
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < d.naps.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: S.x3),
                  Divider(color: p.line, height: 1),
                  const SizedBox(height: S.x3),
                ],
                _nap(c, p, day!, d.naps[i]),
              ],
            ],
          ),
        ),
        if (d.napMin != null) ...[
          const SizedBox(height: S.x3),
          Text(
            // The number that MOVES, said plainly, because that is why the
            // edit is a recompute: these minutes come off tonight's sleep
            // need, subject to its physiological bounds.
            l?.napsCountsToward(hm(d.napMin)) ??
                '${hm(d.napMin)} of nap counts toward tonight’s sleep need.',
            style: F.cap.copyWith(color: p.ink3, height: 1.5),
          ),
        ],
      ],
      if (status.$2 != null) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          status.$1 ? 'Updating sleep calculations' : 'Nap edit saved',
          status.$2!,
          fix: status.$1 ? '' : 'Retry update',
          onFix: status.$1
              ? null
              : () => unawaited(
                  context
                      .read<AppState>()
                      .reanalyzeForNapEdit(day)
                      .catchError((Object e) {}),
                ),
        ),
      ],
      if (_failed != null) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          withEnglishFallback(l).napsNotAppliedTitle,
          _failed!,
          icon: LucideIcons.triangleAlert,
        ),
      ],
      const SizedBox(height: S.x4),
      BigButton(
        _busy
            ? (withEnglishFallback(l).napsWorking)
            : (withEnglishFallback(l).napsLogANap),
        icon: LucideIcons.plus,
        color: C.domHealth,
        onTap: _busy || day == null ? null : () => _log(day),
      ),
      if (d.rejected.isNotEmpty) ...[
        Section(
          withEnglishFallback(l).napsRemovedSection,
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in d.rejected) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${clockOfTs(r['start_ts'] as num)} – '
                          '${clockOfTs(r['end_ts'] as num)}',
                          style: F.body.copyWith(color: p.ink2),
                        ),
                      ),
                      Pressable(
                        onTap: _busy ? null : () => _restore(day!, r),
                        semanticLabel:
                            withEnglishFallback(l).napsPutBackSemantic,
                        child: Text(
                          withEnglishFallback(l).napsPutBackLabel,
                          style: F.cap.copyWith(
                            color: p.on(C.blue),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: S.x2),
        Text(
          withEnglishFallback(l).napsRemovalKept,
          style: F.cap.copyWith(color: p.ink3, height: 1.5),
        ),
      ],
    ]);
  }

  Widget _nap(BuildContext c, P p, String day, Map<String, dynamic> nap) {
    final l = AppLocalizations.of(c);
    final mine = nap['source'] == 'manual';
    final mins = nap['duration_min'] as int?;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: S.x1),
          child: Icon(
            mine ? LucideIcons.userCheck : LucideIcons.moon,
            size: 16,
            color: p.on(mine ? C.green : C.indigo),
          ),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${clockOfTs(nap['start'] as num)} – '
                '${clockOfTs(nap['end'] as num)}',
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.x1),
              Text(
                // A logged nap has no measured asleep/in-bed split, so it says
                // what it is instead of borrowing the detector's language.
                // `hm(null)` is the empty string, and a row whose only caption
                // is ' · detected' is the silent nothing this app does not do.
                mins == null
                    ? (mine
                          ? (withEnglishFallback(l).napsYouLoggedThis)
                          : (withEnglishFallback(l).napsDetected))
                    : (mine
                          ? (l?.napsLoggedWithMins(hm(mins)) ??
                                '${hm(mins)} · you logged this')
                          : (l?.napsDetectedWithMins(hm(mins)) ??
                                '${hm(mins)} asleep · detected')),
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
        const SizedBox(width: S.x2),
        Pressable(
          onTap: _busy ? null : () => _remove(day, nap),
          semanticLabel: mine
              ? (withEnglishFallback(l).napsDeleteSemantic)
              : (withEnglishFallback(l).napsNotANapSemantic),
          child: Text(
            mine
                ? (withEnglishFallback(l).napsDeleteLabel)
                : (withEnglishFallback(l).napsNotANapLabel),
            style: F.cap.copyWith(
              color: p.on(C.blue),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

(bool, String?) napUpdateState(BuildContext c) {
  try {
    return c.select<AppState, (bool, String?)>(
      (a) => (a.napRebuilding, a.napRebuildMessage),
    );
  } catch (_) {
    return (false, null);
  }
}

/// Shared pending/error status for nap-dependent sleep calculations.
Widget? napCalculationStatus(BuildContext c) {
  try {
    final state = c.select<AppState, (bool, String?)>(
      (a) => (a.napRebuilding, a.napRebuildMessage),
    );
    if (state.$2 == null) return null;
    return StatusCard(
      state.$1 ? 'Updating sleep calculations' : 'Nap edit saved',
      state.$2!,
      fix: state.$1 ? '' : 'Retry update',
      onFix: state.$1
          ? null
          : () => unawaited(
              c.read<AppState>().reanalyzeForNapEdit().catchError(
                (Object e) {},
              ),
            ),
    );
  } catch (_) {
    return null;
  }
}

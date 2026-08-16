// Step one of onboarding.
//
// Two things happen here and they are deliberately equal in weight: setting up
// a band, and bringing your history with you. Import is not a settings page
// you find six months later — a health app that starts at zero on day one is
// a health app you delete on day three.
//
// An import that silently drops rows is worse than one that refuses them, so
// [ImportOutcome] carries what the source cost us and [WelcomeView] renders it.

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../ui2.dart';

/// What an import actually achieved, including what it could NOT use.
class ImportOutcome {
  final String source;
  final int days;

  /// Rows whose day had already been derived and pruned before they arrived.
  final int lateRows;

  /// Dates the source presented out of order — folded in as context for the
  /// following day, but never derived in their own right.
  final int strandedDays;

  final String? error;

  const ImportOutcome({
    required this.source,
    this.days = 0,
    this.lateRows = 0,
    this.strandedDays = 0,
    this.error,
  });

  bool get lostSomething => lateRows > 0 || strandedDays > 0;
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;
  ImportOutcome? _outcome;

  Future<void> _import() async {
    final app = context.read<AppState>();
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform
          .pickFiles(allowMultiple: true, withReadStream: false);
    } catch (e) {
      if (mounted) {
        setState(() =>
            _outcome = ImportOutcome(source: 'File picker', error: '$e'));
      }
      return;
    }
    final paths = (picked?.files ?? const [])
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return; // cancelled — not a failure, say nothing

    setState(() {
      _busy = true;
      _outcome = null;
    });
    try {
      final outcome = await runImport(app, paths);
      if (!mounted) return;
      setState(() => _outcome = outcome);
      if (outcome.days > 0) await app.completeImportOnboard();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _outcome = ImportOutcome(source: 'Import', error: '$e'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => WelcomeView(
        busy: _busy,
        outcome: _outcome,
        onNew: () => context.read<AppState>().chooseNewUser(),
        onImport: _import,
      );
}

/// Route [paths] to the importer that understands them and normalise the
/// result. Pure enough to test: the only collaborator is [AppState]'s import
/// surface.
Future<ImportOutcome> runImport(AppState app, List<String> paths) async {
  final db = paths.where((p) => p.toLowerCase().endsWith('.db')).toList();
  if (db.isNotEmpty) {
    var days = 0;
    for (final p in db) {
      days += await app.importEdgeBackup(p);
    }
    return ImportOutcome(source: 'OpenStrap backup', days: days);
  }
  final raw = paths
      .where((p) =>
          p.toLowerCase().endsWith('.noopbak') ||
          p.toLowerCase().endsWith('.zip'))
      .toList();
  if (raw.isNotEmpty) {
    var days = 0, late = 0, stranded = 0;
    for (final p in raw) {
      days += await app.importNoopCsv(p);
      final r = app.lastNoopImport;
      if (r != null) {
        late += r.lateRows;
        stranded += r.strandedDates.length;
      }
    }
    return ImportOutcome(
        source: 'Raw sensor export',
        days: days,
        lateRows: late,
        strandedDays: stranded);
  }
  final days = await app.importWhoopCsvs(paths);
  return ImportOutcome(source: 'Vendor CSV export', days: days);
}

class WelcomeView extends StatelessWidget {
  final bool busy;
  final ImportOutcome? outcome;
  final VoidCallback onNew;
  final VoidCallback onImport;

  const WelcomeView({
    super.key,
    required this.onNew,
    required this.onImport,
    this.busy = false,
    this.outcome,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final o = outcome;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x8, S.x4, S.x8),
          children: [
            Icon(LucideIcons.activity, size: 40, color: p.on(C.green)),
            const SizedBox(height: S.x5),
            Text('Your band, decoded here',
                style: F.display.copyWith(color: p.ink)),
            const SizedBox(height: S.x3),
            Text(
              'Every number is computed on this phone from the raw signal. '
              'There is no account and no server to sign in to.',
              style: F.body.copyWith(color: p.ink2),
            ),
            const SizedBox(height: S.x6),
            const Pill('Local · no cloud', C.green, icon: LucideIcons.shieldCheck),
            const SizedBox(height: S.x8),
            BigButton('Set up my band',
                icon: LucideIcons.bluetooth,
                color: C.green,
                onTap: busy ? null : onNew),
            const SizedBox(height: S.x3),
            BigButton(busy ? 'Importing…' : 'Bring my history first',
                icon: LucideIcons.upload,
                color: C.blue,
                soft: true,
                onTap: busy ? null : onImport),
            const SizedBox(height: S.x3),
            Text(
              // Was: "imported days are marked as imported — they are never
              // mixed into days this app measured itself". There is no source
              // column on day_result or metric_series, two of the four
              // importers write no marker at all, and imported values do feed
              // the same rolling baselines. What IS true is the half that
              // protects data: no import overwrites a day this band measured.
              'Raw sensor exports, an OpenStrap backup, or a vendor CSV. '
              'Imported days sit alongside days this app measured and feed '
              'the same baselines — but a day the band already measured is '
              'never overwritten.',
              style: F.cap.copyWith(color: p.ink3),
            ),
            if (busy) ...[
              const SizedBox(height: S.x6),
              Center(child: CircularProgressIndicator(color: p.on(C.blue))),
            ],
            if (o != null) ...[
              const SizedBox(height: S.x6),
              ImportReport(o),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the import got, and what it could not use. The second half is the
/// point — "imported 412 days" beside a silently dropped fortnight is a lie
/// of omission.
class ImportReport extends StatelessWidget {
  final ImportOutcome o;
  const ImportReport(this.o, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    if (o.error != null) {
      return StatusCard(
        '${o.source} could not be read',
        o.error!,
        fix: 'Try another file',
        icon: LucideIcons.triangleAlert,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        child: Row(children: [
          Icon(LucideIcons.check, size: 20, color: p.on(C.green)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${o.days} day${o.days == 1 ? '' : 's'} imported',
                  style: F.head.copyWith(color: p.ink)),
              Text(o.source, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
        ]),
      ),
      if (o.lostSomething) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          'Part of that file could not be used',
          [
            if (o.strandedDays > 0)
              '${o.strandedDays} day${o.strandedDays == 1 ? '' : 's'} arrived '
                  'out of order and were only used as context for the day '
                  'that followed.',
            if (o.lateRows > 0)
              '${o.lateRows} row${o.lateRows == 1 ? '' : 's'} arrived after '
                  'their day had already been scored and closed.',
          ].join(' '),
          fix: 'Export again in date order',
          icon: LucideIcons.fileWarning,
        ),
      ],
    ]);
  }
}

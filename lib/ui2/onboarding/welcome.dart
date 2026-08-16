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

  /// Sessions written. A vendor export whose workouts CSV is the only file
  /// selected lands 60 of these and 0 days, and reporting only the days made
  /// that read as an import that did nothing.
  final int workouts;

  /// Days present in the source that were NOT written because this device
  /// already holds a measured day for that date. Never overwritten, and never
  /// silently dropped from the report either.
  final int skippedDays;

  /// Rows whose day had already been derived and pruned before they arrived.
  final int lateRows;

  /// Dates the source presented out of order — folded in as context for the
  /// following day, but never derived in their own right.
  final int strandedDays;

  final String? error;

  /// The rows landed and the cross-day rebuild over them threw. Not an error:
  /// the data is in the database, the summaries built from it are not.
  final String? rollupError;

  /// Part of a mixed selection could not be read while the rest imported.
  final String? readError;

  const ImportOutcome({
    required this.source,
    this.days = 0,
    this.workouts = 0,
    this.skippedDays = 0,
    this.lateRows = 0,
    this.strandedDays = 0,
    this.error,
    this.rollupError,
    this.readError,
  });

  bool get lostSomething => lateRows > 0 || strandedDays > 0;

  /// Nothing at all landed. A zero under a green tick is a no-op that reads as
  /// a success, which is the one thing an import report must never do.
  bool get nothingLanded => days == 0 && workouts == 0 && skippedDays == 0;
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
      // Anything that landed counts as bringing history in — a workouts-only
      // vendor export writes sessions and no days, and the gate used to sit
      // there as though the import had not happened.
      if (!outcome.nothingLanded) await app.completeImportOnboard();
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
  // EVERY group runs, not the first one that matches. The picker is
  // multi-select and this used to return inside the winning branch, so a
  // backup selected alongside a vendor CSV imported the backup and threw the
  // CSV away without a word.
  final db = paths.where(_isDbBackup).toList();
  final raw = paths.where(_isRawExport).toList();
  final csv =
      paths.where((p) => !_isDbBackup(p) && !_isRawExport(p)).toList();

  final sources = <String>[];
  var days = 0, workouts = 0, skipped = 0, late = 0, stranded = 0;
  String? rollupError;

  if (db.isNotEmpty) {
    sources.add('OpenStrap backup');
    for (final p in db) {
      days += await app.importEdgeBackup(p);
      // The rows are in and the rollup rebuild threw. AppState's own note:
      // reporting the row count alone claims a success the user does not have
      // — which is exactly what this path did until now.
      rollupError ??= app.importRollupError;
    }
  }
  if (raw.isNotEmpty) {
    sources.add('Raw sensor export');
    for (final p in raw) {
      days += await app.importNoopCsv(p);
      final r = app.lastNoopImport;
      if (r != null) {
        late += r.lateRows;
        stranded += r.strandedDates.length;
      }
    }
  }
  String? readError;
  if (csv.isNotEmpty) {
    // The catch-all group: anything that is not a backup or a raw export is
    // handed to the vendor importer, so it is also where junk in a mixed
    // selection lands. Throwing from here would report an OpenStrap backup
    // that HAS just landed as a failed import, so it is caught and named
    // instead — unless it is the only thing that was picked.
    try {
      days += await app.importWhoopCsvs(csv);
      sources.add('Vendor CSV export');
      final r = app.lastWhoopImport;
      if (r != null) {
        workouts += r.workouts;
        skipped += r.skippedExistingDays;
      }
    } catch (e) {
      if (db.isEmpty && raw.isEmpty) rethrow;
      readError = '$e';
    }
  }

  return ImportOutcome(
    source: sources.isEmpty ? 'Nothing selected' : sources.join(' + '),
    days: days,
    workouts: workouts,
    skippedDays: skipped,
    lateRows: late,
    strandedDays: stranded,
    rollupError: rollupError,
    readError: readError,
  );
}

bool _isDbBackup(String path) {
  final p = path.toLowerCase();
  // `.db.unopenable-<ms>` is what a corrupt-database rebuild quarantines the
  // old file as, and the rebuilt card points the user straight at it. Matching
  // only the `.db` suffix handed that SQLite file to the vendor-CSV importer.
  return p.endsWith('.db') || p.contains('.db.unopenable-');
}

bool _isRawExport(String path) {
  final p = path.toLowerCase();
  return p.endsWith('.noopbak') || p.endsWith('.zip');
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
              'Every number is computed on this phone from the raw signal.',
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
    // A zero is not a success. Same tick, same words, nothing in the database.
    if (o.nothingLanded) {
      return StatusCard(
        'Nothing was imported',
        o.readError ??
            'The file was read but there was nothing in it this app could '
                'use, or every day in it was one this band had already '
                'measured.',
        fix: 'Try another file',
        icon: LucideIcons.fileWarning,
      );
    }
    final also = [
      if (o.workouts > 0)
        '${o.workouts} workout${o.workouts == 1 ? '' : 's'}',
      if (o.skippedDays > 0)
        '${o.skippedDays} day${o.skippedDays == 1 ? '' : 's'} already measured '
            'here and left alone',
    ];
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
              if (also.isNotEmpty)
                Text(also.join(' · '), style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
        ]),
      ),
      if (o.readError != null) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          'One of those files could not be read',
          'The rest imported. ${o.readError}',
          icon: LucideIcons.fileWarning,
        ),
      ],
      if (o.rollupError != null) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          'The days landed, the summaries did not',
          'Every imported row is in the database, but rebuilding the cross-day '
              'summaries over them threw (${o.rollupError}), so trends and '
              'insights still describe the data you had before. Re-analyze '
              'everything from Your data rebuilds them.',
          icon: LucideIcons.triangleAlert,
        ),
      ],
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

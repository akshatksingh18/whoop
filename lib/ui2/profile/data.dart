// Your data — getting it out, keeping a copy, bringing one back.
//
// Everything here was already written, tested, and reachable from nothing.
// `csv_export.dart`, `LocalDb.exportCopy`, `auto_backup.dart` and the four
// importers all existed; the only code that read the whole database out of
// the app was the UPLOAD path. So the app told the user to "export first"
// immediately before the one destructive action in it, and there was no
// export; and the automatic backup defaulted to off with no way to turn it
// on, which made the foreground hook a permanent no-op and the new-phone
// story "you don't have one".
//
// A local-first app whose data cannot leave is not local-first, it is trapped.

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/auto_backup.dart';
import '../../data/csv_export.dart';
import '../../data/db.dart';
import '../../state/app_state.dart';
import '../activity/share.dart' show shareOrigin;
import '../onboarding/welcome.dart' show ImportOutcome, runImport;
import '../screens/home_screen.dart' show dbRebuiltCard;
import '../ui2.dart';
import 'profile.dart';

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;
  String? _note;
  ImportOutcome? _outcome;

  void _say(String s) {
    if (mounted) setState(() => _note = s);
  }

  /// Run [job] with the screen locked, reporting whatever it says or throws.
  ///
  /// Every action on this screen is slow, destructive-adjacent or both, and a
  /// second tap while one is running would race the first over the same files.
  Future<void> _run(Future<String> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
      _outcome = null;
    });
    try {
      _say(await job());
    } catch (e) {
      _say('Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _exportCsv() async {
    // Read before the export runs: an anchor taken after a multi-second await
    // may be measuring a screen the user has already left.
    final origin = shareOrigin(context);
    final res = await exportCsvFiles(kCsvExportSets);
    if (res.paths.isEmpty) {
      return res.hasFailures
          ? 'Nothing exported (${res.failed.join(', ')} failed).'
          : 'Nothing to export yet.';
    }
    await Share.shareXFiles([for (final p in res.paths) XFile(p)],
        subject: 'OpenStrap export', sharePositionOrigin: origin);
    final n = res.paths.length;
    final failed = res.hasFailures
        ? ' ${res.failed.length} set(s) failed: ${res.failed.join(', ')}.'
        : '';
    return '$n file${n == 1 ? '' : 's'} shared.$failed';
  }

  Future<String> _exportDb() async {
    final origin = shareOrigin(context);
    // VACUUM INTO — a transactionally consistent snapshot, not a file copy.
    final path = await LocalDb.exportCopy();
    await Share.shareXFiles([XFile(path)],
        subject: 'OpenStrap database', sharePositionOrigin: origin);
    return 'Database shared. It is the complete copy — keep it somewhere safe.';
  }

  Future<String> _reanalyze(AppState app) async {
    final n = await app.reanalyzeAll();
    return '$n day${n == 1 ? '' : 's'} re-analyzed.';
  }

  Future<String> _backupNow(AppState app) async {
    final outcome = await app.runBackupNow();
    if (outcome.error != null) return 'Backup failed: ${outcome.error}';
    if (!outcome.succeeded) return 'Backup skipped.';
    return 'Backed up to ${outcome.path}';
  }

  Future<String> _import(AppState app) async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform
          .pickFiles(allowMultiple: true, withReadStream: false);
    } catch (e) {
      return 'Could not open the file picker: $e';
    }
    final paths = (picked?.files ?? const [])
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) return ''; // cancelled — not a failure, say nothing
    final outcome = await runImport(app, paths);
    if (mounted) setState(() => _outcome = outcome);
    return '';
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final p = P.of(c);
    final last = app.lastBackupAt;
    final o = _outcome;
    final rebuilt = dbRebuiltCard(app.dbRebuild);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Your data'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                // Home shows this too, on the launch it happened. It belongs
                // here as well because this is the screen someone opens when
                // they notice their food log is empty, and it is the only
                // screen where the card is ALSO an instruction: the
                // quarantined file it names is a .db, and "Import a file"
                // three rows down is what reads one back.
                if (rebuilt != null) ...[
                  rebuilt,
                  const SizedBox(height: S.x5),
                ],
                settingsGroup(c, 'Export', [
                  SetRow(LucideIcons.fileSpreadsheet, C.green,
                      'Export as spreadsheets',
                      sub: '${kCsvExportSets.length} CSV files — daily metrics, '
                          'workouts, sleep, journal, labs, and everything you '
                          'typed in',
                      onTap: _busy ? null : () => _run(_exportCsv)),
                  SetRow(LucideIcons.database, C.blue, 'Export the database',
                      sub: 'One .db file. Lossless, and the only format that '
                          'restores onto another phone',
                      onTap: _busy ? null : () => _run(_exportDb)),
                ]),
                const SizedBox(height: S.x5),
                settingsGroup(c, 'Automatic backup', [
                  SetRow(LucideIcons.calendarClock, C.purple, 'How often',
                      sub: 'Writes a compressed copy to '
                          '$kBackupDirName, keeping the last $kBackupsKept',
                      value: app.backupCadence.label,
                      onTap: _busy
                          ? null
                          : () => app.setBackupCadence(_nextCadence(
                              app.backupCadence))),
                  SetRow(LucideIcons.clock, C.n500, 'Last backup',
                      value: last == null ? 'Never' : _stamp(last),
                      chevron: false),
                  SetRow(LucideIcons.hardDriveDownload, C.teal, 'Back up now',
                      onTap: _busy ? null : () => _run(() => _backupNow(app))),
                ]),
                const SizedBox(height: S.x5),
                settingsGroup(c, 'Bring data in', [
                  SetRow(LucideIcons.upload, C.orange, 'Import a file',
                      sub: 'An OpenStrap backup, a raw sensor export, or a '
                          'vendor CSV. Days this band already measured are '
                          'never overwritten',
                      onTap: _busy ? null : () => _run(() => _import(app))),
                ]),
                const SizedBox(height: S.x5),
                settingsGroup(c, 'Rebuild', [
                  // The engine puts days on hold after a ≥3 h timezone jump
                  // "until Re-analyze data runs" — and nothing in the app ran
                  // it. A flight abroad quietly stopped days updating with no
                  // control anywhere to release them.
                  SetRow(LucideIcons.refreshCcw, C.blue, 'Re-analyze everything',
                      sub: 'Scores every day again from what is stored. Needed '
                          'after a long-haul flight, and after an import that '
                          'landed days out of order',
                      value: app.reanalyzeProgress,
                      onTap: _busy || app.reanalyzing
                          ? null
                          : () => _run(() => _reanalyze(app))),
                ]),
                if (_busy) ...[
                  const SizedBox(height: S.x6),
                  Center(child: CircularProgressIndicator(color: p.on(C.blue))),
                ],
                if (_note != null && _note!.isNotEmpty) ...[
                  const SizedBox(height: S.x5),
                  StatusCard('Done', _note!, icon: LucideIcons.check),
                ],
                if (app.importRollupError != null) ...[
                  const SizedBox(height: S.x5),
                  StatusCard(
                    'The days landed, the summaries did not',
                    'Every imported row is in the database, but rebuilding the '
                        'cross-day summaries over them threw '
                        '(${app.importRollupError}), so trends and insights '
                        'still describe the data you had before.',
                    fix: 'Re-analyze everything',
                    icon: LucideIcons.triangleAlert,
                    onFix: _busy ? null : () => _run(() => _reanalyze(app)),
                  ),
                ],
                if (o != null) ...[
                  const SizedBox(height: S.x5),
                  StatusCard(
                    o.error != null ? 'Import failed' : o.source,
                    o.error ??
                        '${o.days} day${o.days == 1 ? '' : 's'} imported.'
                            '${o.lostSomething ? ' ${o.lateRows} row(s) '
                                'arrived too late and ${o.strandedDays} '
                                'day(s) could not be derived on their own.' : ''}',
                    icon: o.error != null
                        ? LucideIcons.triangleAlert
                        : LucideIcons.check,
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Off → Daily → Weekly → Off. Three states cycle in a row; a picker for three
/// options is a sheet nobody needs.
BackupCadence _nextCadence(BackupCadence c) => BackupCadence
    .values[(c.index + 1) % BackupCadence.values.length];

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}';
}

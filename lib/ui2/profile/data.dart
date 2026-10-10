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
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../build_profile.dart';
import '../../data/auto_backup.dart';
import '../../data/csv_export.dart';
import '../../data/db.dart';
import '../../data/lift_log.dart';
import '../../data/body_log.dart';
import '../../data/photo_encode.dart';
import '../../data/media_backup.dart';
import '../../import/backup_crypto.dart';
import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../activity/share.dart' show shareOrigin;
import '../onboarding/welcome.dart'
    show
        ImportOutcome,
        ImportReport,
        PassphraseCancelled,
        askBackupPassphrase,
        runImport;
import '../screens/home_screen.dart' show dbRebuiltCard;
import '../ui2.dart';
import 'phone_import.dart';
import 'profile.dart';

/// What an action has to say for itself: the line to show, and whether it is a
/// failure. Without the second half every outcome rendered as "Done ✓".
typedef _Note = (String text, bool failed);

class DataScreen extends StatefulWidget {
  const DataScreen({super.key});

  @override
  State<DataScreen> createState() => _DataScreenState();
}

class _DataScreenState extends State<DataScreen> {
  bool _busy = false;
  String? _note;

  /// Whether [_note] is a failure. Every outcome used to render as "Done" with
  /// a green check — a thrown FileSystemException from the export included.
  bool _noteFailed = false;
  ImportOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().refreshBackupPassphraseState();
  }

  void _say(String s, {bool failed = false}) {
    if (mounted) {
      setState(() {
        _note = s;
        _noteFailed = failed;
      });
    }
  }

  /// Run [job] with the screen locked, reporting whatever it says or throws.
  ///
  /// Every action on this screen is slow, destructive-adjacent or both, and a
  /// second tap while one is running would race the first over the same files.
  Future<void> _run(Future<_Note> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _note = null;
      _outcome = null;
    });
    try {
      final (text, failed) = await job();
      _say(text, failed: failed);
    } on PassphraseCancelled {
      // Closing the passphrase prompt is a decision. "Failed:" over it would
      // report the user's own choice back to them as a fault.
    } catch (e) {
      _say(AppLocalizations.of(context)?.dataFailed(e.toString()) ?? 'Failed: $e',
          failed: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<_Note> _exportCsv() async {
    final l = AppLocalizations.of(context);
    // Read before the export runs: an anchor taken after a multi-second await
    // may be measuring a screen the user has already left.
    final origin = shareOrigin(context);
    final res = await exportCsvFiles(kCsvExportSets);
    if (res.paths.isEmpty) {
      return res.hasFailures
          ? (l?.dataNothingExportedFailed(res.failed.join(', ')) ??
                  'Nothing exported (${res.failed.join(', ')} failed).',
              true)
          : (l?.dataNothingToExportYet ?? 'Nothing to export yet.', false);
    }
    await Share.shareXFiles([for (final p in res.paths) XFile(p)],
        subject: '$kAppName export', sharePositionOrigin: origin);
    final n = res.paths.length;
    final failed = res.hasFailures
        ? ' ${l?.dataSetsFailed(res.failed.length, res.failed.join(', ')) ?? '${res.failed.length} set(s) failed: ${res.failed.join(', ')}.'}'
        : '';
    return (
      (l?.dataFilesShared(n) ?? '$n file${n == 1 ? '' : 's'} shared.') + failed,
      res.hasFailures
    );
  }

  Future<_Note> _importLiftLog() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null) return ('', false);
    final plan = await planLiftImport(await File(path).readAsString());
    if (!mounted) return ('', false);
    if (plan.add.isEmpty) {
      return (
        'Nothing new: ${plan.unchanged} already here'
            '${plan.conflicts.isEmpty ? '' : ', ${plan.conflicts.length} differ and were left alone'}.',
        false,
      );
    }
    final sets = plan.add.fold<int>(0, (n, w) => n + w.setCount);
    final ok = await confirmRemove(
      context,
      title: 'Import ${plan.add.length} workouts?',
      body:
          '$sets sets from ${_stamp(plan.add.last.startedAt)} to '
          '${_stamp(plan.add.first.startedAt)}. ${plan.unchanged} already here'
          '${plan.conflicts.isEmpty ? '' : ', ${plan.conflicts.length} differ and stay as they are'}. '
          'They join your lift history for last-time and records only.',
      remove: 'Import',
      keep: 'Cancel',
    );
    if (!ok) return ('', false);
    var useSplits = false;
    if (plan.splits != null && mounted) {
      useSplits = await confirmRemove(
        context,
        title: 'Use its splits too?',
        body:
            'Replaces your WHOOP splits with the ${plan.splits!.length} in the '
            'backup. Past workouts keep their split names either way.',
        remove: 'Use them',
        keep: 'Keep mine',
      );
    }
    final n = await applyLiftImport(plan, replaceSplits: useSplits);
    return ('$n workouts imported.', false);
  }

  Future<_Note> _importBody() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    final files = {
      for (final f in picked?.files ?? const <PlatformFile>[])
        if (f.path != null) f.name: f.path!,
    };
    final manifestName = files.keys
        .where((n) => n.toLowerCase().endsWith('.json'))
        .firstOrNull;
    if (manifestName == null) {
      return files.isEmpty
          ? ('', false)
          : ('Select body-log.json (or the body-history file) with the photos.', true);
    }
    final plan = await planBodyImport(
      await File(files[manifestName]!).readAsString(),
      files: files,
    );
    if (!mounted) return ('', false);
    if (plan.isEmpty) {
      return (
        'Nothing new: ${plan.alreadyHere} already here'
            '${plan.sameDayConflicts.isEmpty ? '' : ', ${plan.sameDayConflicts.length} days hold a different weight and were left alone'}.',
        false,
      );
    }
    final lines = [
      if (plan.weights.isNotEmpty)
        '${plan.weights.length} weights (${plan.weights.first.date} to ${plan.weights.last.date}) as history only.',
      if (plan.measures.isNotEmpty) '${plan.measures.length} tape sessions.',
      if (plan.photos.isNotEmpty) '${plan.photos.length} photos.',
      if (plan.missingPhotoFiles.isNotEmpty)
        '${plan.missingPhotoFiles.length} photos listed but not selected: they will be missing.',
      if (plan.sameDayConflicts.isNotEmpty)
        '${plan.sameDayConflicts.length} days already hold a different weight; those stay as they are.',
      if (plan.alreadyHere > 0) '${plan.alreadyHere} already here.',
    ];
    final ok = await confirmRemove(
      context,
      title: 'Import from ${plan.source == 'akshatos' ? 'AkshatOS Body' : plan.source}?',
      body: lines.join(' '),
      remove: 'Import',
      keep: 'Cancel',
    );
    if (!ok) return ('', false);
    final app = context.read<AppState>();
    final n = await applyBodyImport(
      plan,
      encode: encodeProgressPhotoFile,
      applyWeekday: true,
    );
    app.bumpInsights();
    return (
      '$n records imported.'
          '${plan.missingPhotoFiles.isEmpty ? '' : ' ${plan.missingPhotoFiles.length} photos were not in the selection.'}',
      plan.missingPhotoFiles.isNotEmpty,
    );
  }

  Future<_Note> _exportBody() async {
    final origin = shareOrigin(context);
    final dir = await Directory.systemTemp.createTemp('body');
    final f = File('${dir.path}/body-log.csv')
      ..writeAsStringSync(await BodyLogDb.csv());
    await Share.shareXFiles([XFile(f.path)],
        subject: '$kAppName Body', sharePositionOrigin: origin);
    return ('Body CSV shared.', false);
  }

  Future<_Note> _exportLiftLog() async {
    final origin = shareOrigin(context);
    final dir = await Directory.systemTemp.createTemp('liftlog');
    final json = File('${dir.path}/lift-log.json')
      ..writeAsStringSync(await exportLiftLogBackup());
    final csv = File('${dir.path}/lift-log.csv')
      ..writeAsStringSync(await LiftLogDb.csv());
    await Share.shareXFiles([XFile(json.path), XFile(csv.path)],
        subject: '$kAppName Lift Log', sharePositionOrigin: origin);
    return ('Lift Log shared.', false);
  }

  Future<_Note> _exportDb() async {
    final l = AppLocalizations.of(context);
    final origin = shareOrigin(context);
    // VACUUM INTO — a transactionally consistent snapshot, not a file copy.
    final path = await LocalDb.exportCopy();
    await Share.shareXFiles([XFile(path)],
        subject: '$kAppName database', sharePositionOrigin: origin);
    return (
      l?.dataDatabaseShared ?? 'Database shared. It is the complete copy.',
      false
    );
  }

  /// The same VACUUM'd snapshot as [_exportDb], sealed with AES-256-GCM under
  /// a key derived from a passphrase this app never stores.
  ///
  /// The plaintext intermediate is deleted whatever happens: an encrypted
  /// backup that leaves a readable copy of the whole health record in the
  /// share directory has encrypted nothing.
  Future<_Note> _exportEncrypted() async {
    final pass = await askBackupPassphrase(context, creating: true);
    if (pass == null) return ('', false); // cancelled
    if (!mounted) return ('', false);
    final l = AppLocalizations.of(context);
    final origin = shareOrigin(context);
    final plain = await LocalDb.exportCopy();
    final dest = '$plain.osbk';
    // Build 86: with progress photos to carry, the sealed payload is the
    // database plus photos (format 2); otherwise the database alone (1).
    final photos = await BodyLogDb.photos();
    final photoDir = (await BodyLogDb.photoDir()).path;
    String? zip;
    try {
      if (photos.isNotEmpty) zip = await packMediaBackup(plain, photoDir);
      final src = zip ?? plain;
      final version =
          zip == null ? kBackupFormatVersion : kBackupFormatVersionMedia;
      // 210 000 PBKDF2 rounds is seconds of solid CPU. On the UI isolate that
      // is a frozen app; nothing in the crypto path touches a plugin, which is
      // what makes the worker legal.
      await Isolate.run(() => encryptBackupFile(File(src), File(dest), pass,
          version: version));
    } finally {
      for (final f in [plain, ?zip]) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
    }
    await Share.shareXFiles([XFile(dest)],
        subject: '$kAppName encrypted backup', sharePositionOrigin: origin);
    return (
      l?.dataEncryptedBackupShared ??
          'Encrypted backup shared. Without that passphrase nobody can open it — '
              'including this app, and including us.',
      false
    );
  }

  Future<_Note> _reanalyze(AppState app) async {
    final l = AppLocalizations.of(context);
    final n = await app.reanalyzeAll();
    return (
      l?.dataDaysReanalyzed(n) ?? '$n day${n == 1 ? '' : 's'} re-analyzed.',
      false
    );
  }

  /// Ask for a new backup passphrase and store it in the keychain. Null when
  /// the prompt was closed or the keychain refused it (then [_say] has said so).
  Future<bool> _choosePassphrase(AppState app) async {
    final pass = await askBackupPassphrase(context, creating: true);
    if (pass == null) return false;
    final ok = await app.setBackupPassphrase(pass);
    if (!ok) {
      _say(
          'The passphrase could not be saved to this phone\'s keychain, so '
          'automatic backups cannot run yet. Try again.',
          failed: true);
    }
    return ok;
  }

  Future<_Note> _setPassphrase(AppState app) async {
    if (!await _choosePassphrase(app)) return ('', false);
    return (
      'Saved. The next automatic backup is sealed with it; backups already '
          'written keep the passphrase they were made with. Keep it somewhere '
          'of your own — a restore on another phone asks for it.',
      false
    );
  }

  /// Off → Daily → Weekly → Off, but never ON without a passphrase: an
  /// automatic backup that cannot be sealed writes nothing.
  Future<_Note> _cycleCadence(AppState app) async {
    final l = AppLocalizations.of(context);
    final next = _nextCadence(app.backupCadence);
    if (next != BackupCadence.off && app.hasBackupPassphrase != true) {
      await app.refreshBackupPassphraseState();
      if (!mounted) return ('', false);
      if (app.hasBackupPassphrase != true && !await _choosePassphrase(app)) {
        return ('', false);
      }
    }
    // Turning it on runs the first backup straight away, so its result is
    // what gets reported.
    await app.setBackupCadence(next);
    if (next == BackupCadence.off) return ('', false);
    final err = app.lastBackupError;
    return err == null
        ? ('Automatic backup is on. The first one is written.', false)
        : (l?.dataBackupFailed(err) ?? 'Backup failed: $err', true);
  }

  Future<_Note> _backupNow(AppState app) async {
    final l = AppLocalizations.of(context);
    if (app.hasBackupPassphrase != true) {
      await app.refreshBackupPassphraseState();
      if (!mounted) return ('', false);
      if (app.hasBackupPassphrase != true && !await _choosePassphrase(app)) {
        return ('', false);
      }
    }
    final outcome = await app.runBackupNow();
    if (outcome.error != null) {
      return (l?.dataBackupFailed(outcome.error!) ?? 'Backup failed: ${outcome.error}', true);
    }
    if (!outcome.succeeded) return (l?.dataBackupSkipped ?? 'Backup skipped.', false);
    return (l?.dataBackedUpTo(outcome.path!) ?? 'Backed up to ${outcome.path}', false);
  }

  Future<_Note> _import(AppState app) async {
    final l = AppLocalizations.of(context);
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform
          .pickFiles(allowMultiple: true, withReadStream: false);
    } catch (e) {
      return (
        l?.dataCouldNotOpenPicker(e.toString()) ??
            'Could not open the file picker: $e',
        true
      );
    }
    final paths = (picked?.files ?? const [])
        .map((f) => f.path)
        .whereType<String>()
        .toList();
    // cancelled — not a failure, say nothing
    if (paths.isEmpty) return ('', false);
    final outcome = await runImport(app, paths,
        askPassphrase: () => askBackupPassphrase(context));
    if (mounted) setState(() => _outcome = outcome);
    return ('', false);
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final last = app.lastBackupAt;
    final o = _outcome;
    final rebuilt = dbRebuiltCard(app.dbRebuild);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.dataNavTitle ?? 'Your data'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                // Home shows this too, on the launch it happened. It belongs
                // here as well because this is the screen someone opens when
                // they notice their food log is empty, and it is the only
                // screen where the card is ALSO an instruction: "Import a
                // file" three rows down reads the quarantined file back.
                // (It is named `openstrap.db.unopenable-<ms>`, not `.db` —
                // `runImport` matches that shape explicitly, because routing
                // on the suffix alone sent a SQLite file into the vendor-CSV
                // importer.)
                if (rebuilt != null) ...[
                  rebuilt,
                  const SizedBox(height: S.x5),
                ],
                settingsGroup(c, l?.dataExportGroup ?? 'Export', [
                  SetRow(LucideIcons.fileSpreadsheet, C.green,
                      l?.dataExportSpreadsheets ?? 'Export as spreadsheets',
                      // export-provenance: the daily file now carries `source`
                      // and `algo_version` per day, so an imported vendor
                      // snapshot and a day derived from 1 Hz rows stop being
                      // byte-identical. An empty source cell is unknown
                      // provenance — never back-filled to 'band'.
                      sub: l?.dataExportSpreadsheetsSub(kCsvExportSets.length) ??
                          '${kCsvExportSets.length} CSV files — daily metrics, '
                              'workouts, sleep, journal, labs, and everything you '
                              'typed in. Each day carries where it came from and '
                              'which algorithm version scored it',
                      onTap: _busy ? null : () => _run(_exportCsv)),
                  SetRow(LucideIcons.database, C.blue,
                      l?.dataExportDatabase ?? 'Export the database',
                      sub: l?.dataExportDatabaseSub ??
                          'One .db file. Lossless, and the only format that '
                              'restores onto another phone. Readable by anything '
                              'that opens SQLite — including anyone who gets the '
                              'file',
                      onTap: _busy ? null : () => _run(_exportDb)),
                  SetRow(LucideIcons.lock, C.purple,
                      l?.dataExportEncrypted ?? 'Export an encrypted backup',
                      sub: l?.dataExportEncryptedSub ??
                          'The same complete copy, sealed with a passphrase, '
                              'for somewhere like iCloud. Forget the passphrase '
                              'and that file is gone — there is no recovery, '
                              'because there is no account holding a key',
                      onTap: _busy ? null : () => _run(_exportEncrypted)),
                ]),
                const SizedBox(height: S.x5),
                settingsGroup(c, l?.dataAutoBackupGroup ?? 'Automatic backup', [
                  // Encrypted, always: sealed with the stored passphrase, and
                  // decrypted once to check before it is kept. It lives inside
                  // the app, so it does NOT survive deleting the app — that
                  // still needs a copy moved off the phone.
                  SetRow(LucideIcons.calendarClock, C.purple,
                      l?.dataHowOften ?? 'How often',
                      sub: 'Writes an encrypted, checked copy to '
                          '$kBackupDirName when you open the app, keeping the '
                          'last $kBackupsKept. It is deleted with the app, so '
                          'copy one off the phone now and then',
                      value: app.backupCadence.label,
                      onTap: _busy ? null : () => _run(() => _cycleCadence(app))),
                  SetRow(LucideIcons.keyRound, C.purple, 'Backup passphrase',
                      sub: 'Stored in this phone\'s keychain so backups can run '
                          'on their own. There is no recovery if you forget it',
                      value: switch (app.hasBackupPassphrase) {
                        true => 'Set',
                        false => 'Not set',
                        null => '',
                      },
                      onTap: _busy ? null : () => _run(() => _setPassphrase(app))),
                  SetRow(LucideIcons.clock, C.n500,
                      l?.dataLastBackup ?? 'Last backup',
                      sub: app.lastBackupError == null
                          ? ''
                          : 'The last attempt failed: ${app.lastBackupError}',
                      value: last == null
                          ? (l?.dataNever ?? 'Never')
                          : _stamp(last),
                      chevron: false),
                  SetRow(LucideIcons.hardDriveDownload, C.teal,
                      l?.dataBackUpNow ?? 'Back up now',
                      onTap: _busy ? null : () => _run(() => _backupNow(app))),
                ]),
                const SizedBox(height: S.x5),
                settingsGroup(c, l?.dataBringDataInGroup ?? 'Bring data in', [
                  SetRow(LucideIcons.upload, C.orange,
                      l?.dataImportFile ?? 'Import a file',
                      sub: l?.dataImportFileSub ??
                          'A $kAppName backup (encrypted or not), a journal '
                              'CSV you edited, a raw sensor export, or a vendor '
                              'CSV. Days this band already measured are never '
                              'overwritten',
                      onTap: _busy ? null : () => _run(() => _import(app))),
                  // Progressive disclosure: two health-store reads, each with
                  // its own consent and its own ceiling, behind one row rather
                  // than two more rows on this screen.
                  if (!kPersonalSideload)
                    SetRow(LucideIcons.smartphone, C.blue,
                        l?.dataFromYourPhone ?? 'From your phone',
                        sub: l?.dataFromYourPhoneSub ??
                            'Resting heart rate, blood pressure, glucose and '
                                'body temperature',
                        onTap:
                            _busy ? null : () => goto(c, const PhoneImport())),
                ]),
                const SizedBox(height: S.x5),
                // Build 86: the set log that now lives in the Lift workout.
                settingsGroup(c, 'Lift Log and Body', [
                  SetRow(LucideIcons.dumbbell, C.purple, 'Import from AkshatOS',
                      sub: 'A lift-log.json from Lift Log or its full backup. '
                          'Previewed first; workouts already here are skipped, '
                          'and imported history has no strain or calories',
                      onTap: _busy ? null : () => _run(_importLiftLog)),
                  SetRow(LucideIcons.scale, C.teal, 'Import body history',
                      sub: 'AkshatOS Body: select body-log.json and its photos '
                          'together. Or a body-history file. Weights become '
                          'history only, so past calories never change; a day '
                          'that already has a weight is never overwritten',
                      onTap: _busy ? null : () => _run(_importBody)),
                  SetRow(LucideIcons.fileSpreadsheet, C.teal, 'Export Body CSV',
                      sub: 'One row per day: weight in pounds and each tape site '
                          'in inches, as AkshatOS Body writes it',
                      onTap: _busy ? null : () => _run(_exportBody)),
                  SetRow(LucideIcons.fileSpreadsheet, C.purple, 'Export Lift Log',
                      sub: 'A JSON backup AkshatOS can read, and a CSV with one '
                          'row per set and its load meaning',
                      onTap: _busy ? null : () => _run(_exportLiftLog)),
                ]),
                const SizedBox(height: S.x5),
                settingsGroup(c, l?.dataRebuildGroup ?? 'Rebuild', [
                  // The engine puts days on hold after a ≥3 h timezone jump
                  // "until Re-analyze data runs" — and nothing in the app ran
                  // it. A flight abroad quietly stopped days updating with no
                  // control anywhere to release them.
                  SetRow(LucideIcons.refreshCcw, C.blue,
                      l?.dataReanalyzeEverything ?? 'Re-analyze everything',
                      sub: l?.dataReanalyzeEverythingSub ??
                          'Scores every day again from what is stored. Needed '
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
                  StatusCard(
                      _noteFailed
                          ? (l?.dataThatDidNotWork ?? 'That did not work')
                          : (l?.actionDone ?? 'Done'),
                      _note!,
                      icon: _noteFailed
                          ? LucideIcons.triangleAlert
                          : LucideIcons.check),
                ],
                if (app.importRollupError != null) ...[
                  const SizedBox(height: S.x5),
                  StatusCard(
                    l?.welcomeSummariesDidNotTitle ??
                        'The days landed, the summaries did not',
                    l?.dataSummariesDidNotBodyShort(
                            '${app.importRollupError}') ??
                        'Every imported row is in the database, but rebuilding the '
                            'cross-day summaries over them threw '
                            '(${app.importRollupError}), so trends and insights '
                            'still describe the data you had before.',
                    fix: l?.dataReanalyzeEverything ?? 'Re-analyze everything',
                    icon: LucideIcons.triangleAlert,
                    onFix: _busy ? null : () => _run(() => _reanalyze(app)),
                  ),
                ],
                // The onboarding report, not a second copy of it. This
                // screen used to render its own paraphrase, which had already
                // drifted: it lost the rollup error entirely and stated the
                // loss counts in one run-on sentence.
                if (o != null) ...[
                  const SizedBox(height: S.x5),
                  ImportReport(o),
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

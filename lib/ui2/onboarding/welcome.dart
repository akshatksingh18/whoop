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
import 'dart:io';
import 'dart:isolate';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../import/backup_crypto.dart';
import '../../import/import_container.dart';
import '../../import/journal_csv_import.dart';
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

  /// Journal days written by the hand-entered CSV path (csv-reimport). Its own
  /// counter: those rows REPLACE the journal for the dates they name, which is
  /// a different promise from "a day the band measured is never overwritten",
  /// and folding them into [days] would hide that.
  final int journalRows;

  /// Journal CSV lines that were REJECTED, never clamped — "line 12: note is
  /// 40122 characters". Shown up to a cap, because a validation the user
  /// cannot see is a silent drop.
  final List<String> rejectedRows;

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
    this.journalRows = 0,
    this.rejectedRows = const [],
    this.error,
    this.rollupError,
    this.readError,
  });

  bool get lostSomething => lateRows > 0 || strandedDays > 0;

  /// Nothing at all landed. A zero under a green tick is a no-op that reads as
  /// a success, which is the one thing an import report must never do.
  bool get nothingLanded =>
      days == 0 && workouts == 0 && skippedDays == 0 && journalRows == 0;
}

/// Raised when an encrypted backup was picked and the user closed the
/// passphrase prompt. Not a failure to report as one — they cancelled.
class PassphraseCancelled implements Exception {}

/// Shortest passphrase we will write a file with. Not a policy for its own
/// sake: PBKDF2 buys time against a guess, and four characters is guessed
/// before the derivation finishes no matter how many iterations it runs.
const int kMinPassphraseChars = 8;

/// Ask for the passphrase. Null when the user closed it.
///
/// [creating] switches this between the two halves of the same promise.
/// Writing a file asks twice and says out loud that a forgotten passphrase is
/// the end of that backup; opening one asks once. There is deliberately NO
/// hint field and NO recovery code: both would make it feel safer while being
/// the thing that lets someone else open the file.
Future<String?> askBackupPassphrase(BuildContext c, {bool creating = false}) =>
    showDialog<String>(
      context: c,
      builder: (_) => _PassphraseDialog(creating: creating),
    );

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.creating});
  final bool creating;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _a = TextEditingController();
  final _b = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _a.text;
    if (widget.creating) {
      if (v.length < kMinPassphraseChars) {
        setState(() => _error = 'At least $kMinPassphraseChars characters.');
        return;
      }
      if (v != _b.text) {
        setState(() => _error = 'The two do not match.');
        return;
      }
    } else if (v.isEmpty) {
      setState(() => _error = 'Enter the passphrase.');
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext c) {
    final creating = widget.creating;
    return AlertDialog(
      title: Text(creating ? 'Choose a passphrase' : 'Passphrase'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(creating
            // Both halves, in the same breath. The second half is not a
            // warning bolted onto a feature — it IS the feature: nothing can
            // open this file without the passphrase, including us, because
            // there is no account and no server holding a key.
            ? 'The file is unreadable without it. And a forgotten passphrase '
                'means that backup is gone — there is no recovery, because '
                'there is no account and no server holding a key. That is the '
                'same thing that keeps it private.'
            : 'The one you chose when this backup was written.'),
        const SizedBox(height: S.x4),
        TextField(
          controller: _a,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
          onSubmitted: creating ? null : (_) => _submit(),
        ),
        if (creating) ...[
          const SizedBox(height: S.x3),
          TextField(
            controller: _b,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Repeat it'),
            onSubmitted: (_) => _submit(),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: S.x3),
          Text(_error!, style: F.cap.copyWith(color: P.of(c).on(C.red))),
        ],
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancel')),
        TextButton(
            onPressed: _submit, child: Text(creating ? 'Encrypt' : 'Unlock')),
      ],
    );
  }
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
      final outcome = await runImport(app, paths,
          askPassphrase: () => askBackupPassphrase(context));
      if (!mounted) return;
      setState(() => _outcome = outcome);
      // Anything that landed counts as bringing history in — a workouts-only
      // vendor export writes sessions and no days, and the gate used to sit
      // there as though the import had not happened.
      if (!outcome.nothingLanded) await app.completeImportOnboard();
    } on PassphraseCancelled {
      // Closing the prompt is a decision, not a failure. Say nothing.
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
Future<ImportOutcome> runImport(
  AppState app,
  List<String> paths, {
  Future<String?> Function()? askPassphrase,
}) async {
  // An encrypted backup is identified by its MAGIC, not its extension: it comes
  // back off iCloud Drive or a mail attachment with whatever name that round
  // trip gave it, and routing a ciphertext into the vendor-CSV importer would
  // report "nothing in it this app could use" for a file that is the user's
  // entire history.
  final decrypted = <String>[];
  final sources = <String>[];
  var days = 0, workouts = 0, skipped = 0, late = 0, stranded = 0;
  var journalRows = 0;
  final rejected = <String>[];
  String? rollupError;
  String? cryptoError;

  final plain = <String>[];
  for (final p in paths) {
    if (!await isEncryptedBackup(p)) {
      plain.add(p);
      continue;
    }
    if (askPassphrase == null) {
      cryptoError = 'That file is an encrypted backup. Open it from '
          'Settings → Your data, where the passphrase can be asked for.';
      continue;
    }
    final pass = await askPassphrase();
    if (pass == null) {
      // Shred here, not in the `finally` below. The picker is multi-select, so
      // an EARLIER encrypted file in the same selection may already be sitting
      // in the temp directory as the whole health record in plaintext — and
      // this throw jumps past the try/finally that would normally delete it,
      // because that try has not been entered yet. Cancelling the second
      // passphrase prompt used to leave the first backup decrypted on disk.
      for (final d in decrypted) {
        try {
          await File(d).delete();
        } catch (_) {}
      }
      throw PassphraseCancelled();
    }
    try {
      decrypted.add(await decryptToTemp(p, pass));
    } on BackupFormatException catch (e) {
      // ONE message for a wrong passphrase and a tampered file, because GCM
      // cannot tell them apart and pretending otherwise would be a guess.
      cryptoError = e.message;
    }
  }

  // EVERY group runs, not the first one that matches. The picker is
  // multi-select and this used to return inside the winning branch, so a
  // backup selected alongside a vendor CSV imported the backup and threw the
  // CSV away without a word.
  final db = [...plain.where(_isDbBackup), ...decrypted];
  // Raw-vs-vendor is decided by what the file HOLDS, not by what it is called.
  // See [isNoopExport]: routing on the extension sent NOOP's raw-sensor `.csv`
  // to the vendor importer and WHOOP's `.zip` to the NOOP one — both files
  // fine, both refused, both with advice for the other file.
  final raw = <String>[];
  final csv = <String>[];
  for (final p in plain) {
    if (_isDbBackup(p)) continue;
    (await isNoopExport(p) ? raw : csv).add(p);
  }

  if (decrypted.isNotEmpty) sources.add('Encrypted backup');
  if (plain.any(_isDbBackup)) sources.add('OpenStrap backup');
  try {
    for (final p in db) {
      days += await app.importEdgeBackup(p);
      // The rows are in and the rollup rebuild threw. AppState's own note:
      // reporting the row count alone claims a success the user does not have
      // — which is exactly what this path did until now.
      rollupError ??= app.importRollupError;
    }
  } finally {
    // The decrypted copy is the whole health record in plaintext. It exists
    // for the length of one import and no longer — leaving it in the temp
    // directory would undo the reason the backup was encrypted.
    for (final p in decrypted) {
      try {
        await File(p).delete();
      } catch (_) {}
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
  // csv-reimport: OUR OWN journal export, coming back after a spreadsheet edit.
  // Routed on the header signature rather than the filename — `parseJournalCsv`
  // reads and validates the whole file before a single row is written, so a
  // file that is not one throws without touching the database and falls
  // through to the vendor importer below.
  final vendor = <String>[];
  for (final p in csv) {
    // Only a TEXT file can be a journal export, and `importJournalCsvFile`
    // reads it as a string. Vendor exports arrive here as ZIPs now that routing
    // is by content, and reading one as a string is #199 all over again — it
    // comes back as `FileSystemException: Failed to decode data using encoding
    // 'utf-8'`, which no catch below was going to turn into advice. The vendor
    // path unwraps archives (and gzip) properly, so hand them straight over.
    if (await sniffFile(p) != ImportContainer.text) {
      vendor.add(p);
      continue;
    }
    try {
      final r = await importJournalCsvFile(p);
      journalRows += r.imported;
      rejected.addAll(r.rejected.map((x) => x.toString()));
      if (!sources.contains('Journal CSV')) sources.add('Journal CSV');
    } on JournalCsvFormatException {
      vendor.add(p);
    } on FormatException {
      // Text, but not UTF-8 — a latin1/cp1252 CSV out of a spreadsheet. The
      // sniff above cannot see that, and the vendor importer decodes leniently.
      vendor.add(p);
    }
  }

  String? readError;
  if (vendor.isNotEmpty) {
    // The catch-all group: anything that is not a backup or a raw export is
    // handed to the vendor importer, so it is also where junk in a mixed
    // selection lands. Throwing from here would report an OpenStrap backup
    // that HAS just landed as a failed import, so it is caught and named
    // instead — unless it is the only thing that was picked.
    try {
      days += await app.importWhoopCsvs(vendor);
      sources.add('Vendor CSV export');
      final r = app.lastWhoopImport;
      if (r != null) {
        workouts += r.workouts;
        skipped += r.skippedExistingDays;
      }
    } catch (e) {
      if (db.isEmpty && raw.isEmpty && journalRows == 0) rethrow;
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
    journalRows: journalRows,
    rejectedRows: rejected,
    rollupError: rollupError,
    // A file that would not decrypt is reported the same way a file that would
    // not parse is: named, alongside whatever else did land.
    readError: readError ?? cryptoError,
  );
}

/// True when [path] starts with the encrypted-backup magic. Four bytes, so a
/// mis-picked file costs one read and not a key derivation.
Future<bool> isEncryptedBackup(String path) async {
  try {
    final raf = await File(path).open();
    try {
      return _sameBytes(await raf.read(kBackupMagic.length), kBackupMagic);
    } finally {
      await raf.close();
    }
  } catch (_) {
    return false;
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Decrypt [path] into the temp directory and return the plaintext path.
///
/// PBKDF2 at 210 000 iterations is a multi-second block by design, so it runs
/// on a worker isolate — on the UI isolate it is a frozen app that looks
/// crashed. Nothing here touches a plugin, which is what makes that legal.
Future<String> decryptToTemp(String path, String passphrase) async {
  final tmp = await getTemporaryDirectory();
  final dest =
      '${tmp.path}/restore-${DateTime.now().millisecondsSinceEpoch}.db';
  await Isolate.run(
      () => decryptBackupFile(File(path), File(dest), passphrase));
  return dest;
}

bool _isDbBackup(String path) {
  final p = path.toLowerCase();
  // `.db.unopenable-<ms>` is what a corrupt-database rebuild quarantines the
  // old file as, and the rebuilt card points the user straight at it. Matching
  // only the `.db` suffix handed that SQLite file to the vendor-CSV importer.
  // `.db.gz` is what the app's own automatic backup writes (auto_backup.dart's
  // kBackupExtension). Leaving it out sent a user restoring their own backup
  // down the vendor-CSV path, which is the one import that has to work.
  return p.endsWith('.db') ||
      p.endsWith('.db.gz') ||
      p.contains('.db.unopenable-');
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
              'Raw sensor exports, an OpenStrap backup (encrypted or not), '
              'or a vendor CSV. '
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
        // Every row refused is its own answer to "why is it empty?", and it
        // has to survive the empty case or the validation is invisible.
        o.rejectedRows.isNotEmpty
            ? 'Every row was refused: ${_rejects(o)}'
            : o.readError ??
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
    // A journal CSV writes no days, so the old headline read "0 days imported"
    // over a successful import of 300 notes.
    final headline = o.days > 0
        ? '${o.days} day${o.days == 1 ? '' : 's'} imported'
        : '${o.journalRows} journal '
            'day${o.journalRows == 1 ? '' : 's'} written';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Surface(
        child: Row(children: [
          Icon(LucideIcons.check, size: 20, color: p.on(C.green)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(headline, style: F.head.copyWith(color: p.ink)),
              Text(o.source, style: F.over.copyWith(color: p.ink3)),
              if (also.isNotEmpty)
                Text(also.join(' · '), style: F.over.copyWith(color: p.ink3)),
              if (o.days > 0 && o.journalRows > 0)
                Text(
                    '${o.journalRows} journal '
                    'day${o.journalRows == 1 ? '' : 's'} replaced',
                    style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
        ]),
      ),
      // REJECTED, never clamped. A row outside its declared range is not
      // salvageable by trimming it — that would store a value the user never
      // wrote — so it is refused by line number and the other 300 land.
      if (o.rejectedRows.isNotEmpty) ...[
        const SizedBox(height: S.x3),
        StatusCard(
          '${o.rejectedRows.length} '
              'row${o.rejectedRows.length == 1 ? ' was' : 's were'} refused',
          '${_rejects(o)} Nothing was trimmed to fit — fix those lines and '
              'import again.',
          icon: LucideIcons.fileWarning,
        ),
      ],
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

/// The first few refusals, with a count for the rest. Six is where a
/// StatusCard stops being read.
String _rejects(ImportOutcome o) {
  final shown = o.rejectedRows.take(6).join('; ');
  final more = o.rejectedRows.length - 6;
  return more > 0 ? '$shown; and $more more.' : '$shown.';
}

// Automatic local backup of the database.
//
// The manual export already exists and is complete; this is the same snapshot
// on a schedule, because a backup you have to remember to take is a backup
// most people do not have. Discussion #214 asked for exactly this: years of
// health data living in one place on one phone.
//
// WHERE IT WRITES, and why not a folder you pick. Somewhere the user can
// actually reach — see [backupDirectory], which is per-platform for exactly
// that reason. Anything that syncs a folder (iCloud Drive, Synology Drive,
// Nextcloud) can be pointed at it. A user-chosen folder would need a persisted
// SAF tree URI or a security-scoped bookmark, both of which silently expire,
// and a backup that quietly stopped working is worse than one that lives
// somewhere slightly less convenient.
//
// WHEN IT RUNS. On foreground, when due. There is no background scheduler that
// works on both platforms — Workmanager is Android-only here and iOS's
// BGProcessingTask is best-effort — and a backup that fires when you open the
// app is honest about that. The alternative is a schedule that claims "daily"
// and delivers whenever the OS feels like it.
//
// ENCRYPTED, ALWAYS. Every automatic backup is the same `OSBK` file the manual
// "Export an encrypted backup" writes (`backup_crypto.dart`), sealed under the
// backup passphrase the user stored in the platform keychain. There is no
// plaintext automatic path any more: with no stored passphrase a run reports
// [BackupOutcome.needsPassphrase] and writes nothing. The snapshot is gzipped
// BEFORE sealing — roughly a third of the bytes through the ~1.5 MB/s pure-Dart
// AES-GCM — and `LocalDb.importFromDbFile` already inflates gzip by magic
// bytes, so the existing encrypted-restore path opens these unchanged.
//
// VERIFIED BEFORE PUBLISHED. A sealed file is decrypted again (GCM tag and
// all) and compared before it gets its final name, so a published backup is
// one this code has already opened once. All of it runs on a worker isolate.
//
// NOT OFF-DEVICE. The folder lives inside the app container: uninstalling the
// app deletes it with the database. These copies cover a bad upgrade, a
// corrupt database or a mistaken delete; surviving a lost phone or an
// uninstall still needs a copy moved off the phone.

import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../import/backup_crypto.dart';
import 'db.dart';

/// How often a backup is taken. Off is the default: turning it on needs a
/// backup passphrase, and that is a choice to make deliberately.
enum BackupCadence {
  off,
  daily,
  weekly;

  String get label => switch (this) {
    BackupCadence.off => 'Off',
    BackupCadence.daily => 'Daily',
    BackupCadence.weekly => 'Weekly',
  };

  Duration? get interval => switch (this) {
    BackupCadence.off => null,
    BackupCadence.daily => const Duration(days: 1),
    BackupCadence.weekly => const Duration(days: 7),
  };

  static BackupCadence fromName(String? name) => BackupCadence.values
      .firstWhere((c) => c.name == name, orElse: () => BackupCadence.off);
}

/// Folder name. Spelled out so it is obvious what it is when someone finds it
/// in Files or a file manager.
const kBackupDirName = 'OpenStrap Backups';

/// How many backups are kept. Enough to survive noticing a problem a few days
/// late, few enough that the folder does not grow without bound — each file is
/// a full copy of the database.
const kBackupsKept = 5;

/// Whether a backup is due.
///
/// Pure, and the only place the schedule is decided. A null [lastRun] means
/// one has never been taken, which is always due — otherwise switching the
/// setting on would do nothing visible until tomorrow, and the user would
/// reasonably conclude it was broken.
bool backupIsDue({
  required BackupCadence cadence,
  required DateTime? lastRun,
  required DateTime now,
}) {
  final interval = cadence.interval;
  if (interval == null) return false;
  if (lastRun == null) return true;
  // A clock that moved backwards (timezone change, NTP correction, a user
  // setting the date) must not park the schedule in the future forever.
  if (lastRun.isAfter(now)) return true;
  return now.difference(lastRun) >= interval;
}

/// Extension for a backup written by the CURRENT code: an `OSBK` encrypted
/// file whose plaintext is the gzipped database snapshot.
const kBackupExtension = '.osbk';

/// Filename for a backup taken at [when].
///
/// Seconds are included: two runs inside the same minute would otherwise land
/// on one name and the second would overwrite the first.
String backupFileName(DateTime when) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'openstrap-${when.year}${two(when.month)}${two(when.day)}'
      '-${two(when.hour)}${two(when.minute)}${two(when.second)}$kBackupExtension';
}

/// EXACTLY the shapes this file has ever emitted, and nothing else.
///
/// Retention DELETES what this matches, and it runs in a directory the user
/// can put files into. A loose `openstrap-*.db` glob would happily eat
/// someone's `openstrap-notes.db`.
///
/// Covers these shapes deliberately:
///   • `.osbk` — what is written now (encrypted).
///   • `.db.gz` / `.db` — the PLAINTEXT backups earlier versions wrote. They
///     stay matchable so retention sees them, and [prunePlaintextBackups]
///     deletes them once an encrypted backup has been published.
///   • a `-N` collision suffix — [_uniqueDestination] emits these when two runs
///     land in the same second.
final _backupNamePattern =
    RegExp(r'^openstrap-\d{8}-\d{6}(-\d+)?(\.db(\.gz)?|\.osbk)$');

/// The plaintext shapes older builds wrote.
final _plaintextBackupPattern =
    RegExp(r'^openstrap-\d{8}-\d{6}(-\d+)?\.db(\.gz)?$');

/// Appended while a backup is still being written. Chosen so
/// [_backupNamePattern] does NOT match it: a partial file must be invisible to
/// retention, or a process killed mid-write would let a truncated backup evict
/// a good one.
const kBackupStagingSuffix = '.partial';

/// True when [basename] is one of OUR staging files.
///
/// The suffix alone is not enough. This directory is app-specific external
/// storage on Android and the file-sharing Documents directory on iOS — the
/// whole point of picking it is that users and sync clients can reach it, and
/// `.partial` is exactly what a half-finished Nextcloud or iCloud download is
/// called. Deleting on the suffix alone reached outside this feature's own
/// files, for the same reason [_backupNamePattern] is strict rather than a
/// loose `openstrap-*` glob.
bool _isOurStagingFile(String basename) {
  if (!basename.endsWith(kBackupStagingSuffix)) return false;
  final published = basename.substring(
    0,
    basename.length - kBackupStagingSuffix.length,
  );
  return _backupNamePattern.hasMatch(published);
}

/// Delete staging files left by a run that was killed mid-write.
///
/// Retention cannot do this — it only sees names it matches, and the whole
/// point of the staging suffix is that it does not. Best-effort: a leftover
/// costs disk, never correctness.
Future<void> pruneStagingFiles(Directory dir) async {
  try {
    for (final f in dir.listSync().whereType<File>()) {
      if (_isOurStagingFile(p.basename(f.path))) await f.delete();
    }
  } catch (_) {
    /* housekeeping only */
  }
}

/// Sort key for a backup filename: its timestamp, then its collision index.
///
/// NOT the raw basename. Names sort chronologically as text right up until a
/// same-second collision suffix appears, because `-` (0x2D) sorts before `.`
/// (0x2E): `…-000000-2.db.gz` compares LESS than `…-000000.db.gz`, so the
/// second backup of that second was ranked as the older one and retention
/// would evict it first. A higher index is always the later write —
/// [_uniqueDestination] only reaches `-2` because `-1`'s name was taken.
(String, int) _backupSortKey(String basename) {
  final m = _backupNamePattern.firstMatch(basename);
  if (m == null) return ('', 0);
  final stamp = basename.substring(0, 'openstrap-00000000-000000'.length);
  final collision = m.group(1);
  return (stamp, collision == null ? 1 : (int.tryParse(collision.substring(1)) ?? 1));
}

/// Existing backups, newest first.
List<File> sortBackupsNewestFirst(Iterable<FileSystemEntity> entries) {
  final files = entries
      .whereType<File>()
      .where((f) => _backupNamePattern.hasMatch(p.basename(f.path)))
      .toList();
  files.sort((a, b) {
    final ka = _backupSortKey(p.basename(a.path));
    final kb = _backupSortKey(p.basename(b.path));
    final byStamp = kb.$1.compareTo(ka.$1);
    if (byStamp != 0) return byStamp;
    final byCollision = kb.$2.compareTo(ka.$2);
    if (byCollision != 0) return byCollision;
    // Same second, same index — an upgraded install can hold both the old
    // `.db` and the new `.db.gz`. Any stable order will do; pick one.
    return p.basename(b.path).compareTo(p.basename(a.path));
  });
  return files;
}

/// What a backup attempt did.
class BackupOutcome {
  const BackupOutcome({
    this.path,
    this.error,
    this.skipped = false,
    this.needsPassphrase = false,
  });

  /// The file written, or null when nothing was.
  final String? path;

  /// Why it failed, or null. A failure is REPORTED rather than swallowed —
  /// a backup silently not happening is the failure mode this whole feature
  /// exists to prevent.
  final String? error;

  /// Not due yet. Distinct from both success and failure.
  final bool skipped;

  /// No backup passphrase is stored, so nothing was written. Also carries an
  /// [error] so a caller that only checks for failure still reports it.
  final bool needsPassphrase;

  bool get succeeded => path != null;
}

/// The backup directory, created if missing.
///
/// PLATFORM SPLIT, and it decides whether this feature works at all:
///   iOS — the app's Documents directory, which `UIFileSharingEnabled` +
///   `LSSupportsOpeningDocumentsInPlace` expose in Files.
///   Android — app-specific EXTERNAL storage. `getApplicationDocumentsDirectory`
///   resolves to `/data/user/0/<pkg>/app_flutter` there, which no file manager
///   and no sync app can reach, so backups would have been written somewhere
///   the user could never get at them. External storage needs no permission on
///   modern Android and is browsable.
///
/// Falls back to the documents directory if external storage is unavailable
/// (no shared volume) — a backup somewhere awkward beats no backup.
Future<Directory> backupDirectory() async {
  Directory? root;
  if (Platform.isAndroid) {
    try {
      root = await getExternalStorageDirectory();
    } catch (_) {
      root = null;
    }
  }
  root ??= await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(root.path, kBackupDirName));
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir;
}

/// The whole backup transaction runs under this, one at a time.
///
/// It has to cover MORE than the export. Reading `lastRun`, deciding whether a
/// backup is due, writing the file, pruning, and persisting the new `lastRun`
/// are one indivisible sequence: a guard that ended when the export finished
/// still left a window where a second trigger read the stale timestamp, judged
/// it due, and started another export. A resume can fire more than once, and a
/// cadence change lands on the same path.
Future<void> _tail = Future<void>.value();

Future<T> _serialize<T>(Future<T> Function() body) {
  final result = _tail.then((_) => body());
  // The queue must survive a failed run, or one error wedges every later
  // backup for the life of the process.
  _tail = result.then((_) {}, onError: (_) {});
  return result;
}

/// What a run without a stored passphrase reports.
const kBackupNeedsPassphrase =
    'no backup passphrase is set, so no backup was written';

/// Take a backup now, regardless of schedule, and prune old ones.
///
/// [passphrase] is read INSIDE the lock, like the schedule in
/// [runBackupIfDue]. [iterations] is a test seam only; production takes the
/// default KDF cost.
///
/// Serialized against every other backup path.
Future<BackupOutcome> runBackup({
  required Future<String?> Function() passphrase,
  DateTime? now,
  Future<String> Function()? exportSnapshot,
  int iterations = kDefaultIterations,
}) =>
    _serialize(() => _runBackup(
        passphrase: passphrase,
        now: now,
        exportSnapshot: exportSnapshot,
        iterations: iterations));

Future<BackupOutcome> _runBackup({
  required Future<String?> Function() passphrase,
  DateTime? now,
  // Test seam. A failing export is otherwise unreachable from a test, which
  // left the queue-recovery case unverifiable.
  Future<String> Function()? exportSnapshot,
  int iterations = kDefaultIterations,
}) async {
  final when = now ?? DateTime.now();
  try {
    final pass = await passphrase();
    if (pass == null || pass.isEmpty) {
      return const BackupOutcome(
          error: kBackupNeedsPassphrase, needsPassphrase: true);
    }
    final dir = await backupDirectory();
    // Destination FIRST. Exporting before checking meant a failure here left a
    // full copy of the database sitting in temp, once per attempt.
    final dest = _uniqueDestination(dir, when);
    if (dest == null) {
      return const BackupOutcome(
        error: 'no free backup filename for this second',
      );
    }
    // `exportCopy` is VACUUM INTO — a transactionally consistent snapshot,
    // not a file copy of a database that may be mid-write.
    final snapshot = await (exportSnapshot ?? LocalDb.exportCopy)();
    // STAGE, then publish by rename. The staging name is one retention does
    // NOT match, and rename is atomic within the directory, so `dest.path`
    // only ever exists as a complete, verified file — a process killed
    // mid-seal leaves a `.partial` that [pruneStagingFiles] sweeps later.
    final staging = File('${dest.path}$kBackupStagingSuffix');
    try {
      final stagingPath = staging.path;
      // Nothing in here touches a plugin, which is what makes the worker
      // legal; minutes of pure-Dart crypto on the UI isolate is a frozen app.
      await Isolate.run(() =>
          sealAndVerifyBackup(snapshot, stagingPath, pass, iterations));
      await staging.rename(dest.path);
    } catch (_) {
      try {
        if (await staging.exists()) await staging.delete();
      } catch (_) {}
      rethrow;
    } finally {
      try {
        final tmp = File(snapshot);
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }

    await pruneStagingFiles(dir);
    await prunePlaintextBackups(dir);
    await pruneBackups(dir, keep: kBackupsKept);
    return BackupOutcome(path: dest.path);
  } catch (e) {
    return BackupOutcome(error: e.toString());
  }
}

/// gzip [snapshotPath], seal it into [stagingPath], then decrypt the sealed
/// file once and require it to reproduce the compressed bytes exactly.
///
/// Every intermediate lives beside the snapshot (temp) and is deleted whatever
/// happens. Throws on any failure; the caller discards the staging file.
Future<void> sealAndVerifyBackup(String snapshotPath, String stagingPath,
    String passphrase, int iterations) async {
  final gz = File('$snapshotPath.gz');
  final check = File('$snapshotPath.verify');
  try {
    await File(snapshotPath)
        .openRead()
        .transform(gzip.encoder)
        .pipe(gz.openWrite());
    await encryptBackupFile(gz, File(stagingPath), passphrase,
        iterations: iterations);
    // The GCM tag already proves integrity on a good decrypt; comparing the
    // bytes as well catches a sealing bug that authenticates the wrong input.
    await decryptBackupFile(File(stagingPath), check, passphrase);
    if (!await _sameContent(gz, check)) {
      throw const BackupFormatException(
          'the sealed backup did not decrypt back to its own snapshot');
    }
  } finally {
    for (final f in [gz, check]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}

Future<bool> _sameContent(File a, File b) async {
  if (await a.length() != await b.length()) return false;
  final ra = await a.open(), rb = await b.open();
  try {
    while (true) {
      final x = await ra.read(1 << 20);
      final y = await rb.read(1 << 20);
      if (x.length != y.length) return false;
      if (x.isEmpty) return true;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
    }
  } finally {
    await ra.close();
    await rb.close();
  }
}

/// Delete every PLAINTEXT automatic backup an older build left in [dir].
///
/// Called only after an encrypted backup has been published, so there is
/// always a newer, verified copy when these go. Leaving them would keep an
/// unencrypted health record in a Files-visible folder after the user chose
/// encryption. Matches only this feature's exact names.
Future<void> prunePlaintextBackups(Directory dir) async {
  try {
    for (final f in dir.listSync().whereType<File>()) {
      if (_plaintextBackupPattern.hasMatch(p.basename(f.path))) {
        await f.delete();
      }
    }
  } catch (_) {
    /* housekeeping only */
  }
}

/// Delete all but the [keep] newest backups.
Future<void> pruneBackups(Directory dir, {required int keep}) async {
  try {
    final files = sortBackupsNewestFirst(dir.listSync());
    for (final old in files.skip(keep)) {
      await old.delete();
    }
  } catch (_) {
    // Housekeeping only — never fail a backup over cleanup.
  }
}

/// A FREE filename in [dir] for a backup taken at [when], or null when the
/// bounded search found none.
///
/// Seconds make a collision rare, not impossible — two manual runs inside one
/// second would otherwise share a name and the second would overwrite the
/// first. Null rather than the last candidate: returning an occupied path
/// would hand back a real snapshot for the next backup to overwrite, which is
/// the exact data loss this function exists to prevent.
File? _uniqueDestination(Directory dir, DateTime when) {
  final base = backupFileName(when);
  final stem = base.substring(0, base.length - kBackupExtension.length);
  for (var i = 1; i < 100; i++) {
    final candidate = File(
      p.join(dir.path, i == 1 ? base : '$stem-$i$kBackupExtension'),
    );
    if (!candidate.existsSync()) return candidate;
  }
  return null;
}

/// Run a backup if [cadence] says one is due.
///
/// [cadence], [lastRun] and [markRun] are all CALLBACKS rather than values, so
/// reading the setting and the timestamp, deciding, exporting and persisting
/// happen inside the same lock. Passing either in as a value would reintroduce
/// exactly the race this serialization exists to close: the caller would have
/// read it before queueing, and both a backup that finished in the meantime
/// and a setting the user changed in the meantime would be invisible to the
/// decision.
///
/// Returns a skipped outcome when nothing was due, so the caller can tell
/// "not yet" from "it broke".
Future<BackupOutcome> runBackupIfDue({
  required BackupCadence Function() cadence,
  required DateTime? Function() lastRun,
  required Future<void> Function(DateTime) markRun,
  required Future<String?> Function() passphrase,
  DateTime? now,
  Future<String> Function()? exportSnapshot,
  int iterations = kDefaultIterations,
}) => _serialize(() async {
  final when = now ?? DateTime.now();
  // Cadence is read here too, for the same reason as the timestamp: a call
  // that waits behind an export would otherwise act on the setting as it was
  // when it queued. Someone who switches backup OFF while one is running would
  // still get another copy of their health data written after they disabled
  // it.
  if (!backupIsDue(cadence: cadence(), lastRun: lastRun(), now: when)) {
    return const BackupOutcome(skipped: true);
  }
  final outcome = await _runBackup(
      passphrase: passphrase,
      now: when,
      exportSnapshot: exportSnapshot,
      iterations: iterations);
  if (outcome.succeeded) await markRun(when);
  return outcome;
});

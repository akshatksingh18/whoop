// A full set of same-second names must leave every snapshot intact.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/data/db.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('backup-filename-exhaustion', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  test(
    'an occupied backup second refuses before exporting and permits retry',
    () async {
      final when = DateTime(2021, 4, 6, 11, 12, 13);
      final dir = await backupDirectory();
      final base = backupFileName(when);
      final stem = base.substring(0, base.length - kBackupExtension.length);
      final occupied = <File, List<int>>{};
      for (var i = 1; i < 100; i++) {
        final name = i == 1 ? base : '$stem-$i$kBackupExtension';
        final bytes = [i, 42];
        occupied[await File(path.join(dir.path, name)).writeAsBytes(bytes)] =
            bytes;
      }
      final observations = <DateTime>[];
      var exports = 0;
      Future<BackupOutcome> save(DateTime now) => runBackup(
        passphrase: () async => 'authored backup passphrase',
        now: now,
        iterations: 1000,
        exportSnapshot: () {
          exports++;
          return LocalDb.exportCopy();
        },
        markRun: (date) async => observations.add(date),
      );

      final refused = await save(when);
      expect(refused.succeeded, isFalse);
      expect(refused.error, 'no free backup filename for this second');
      expect(exports, 0);
      expect(observations, isEmpty);
      expect(await dir.list().length, occupied.length);
      for (final e in occupied.entries) {
        expect(await e.key.readAsBytes(), e.value);
      }

      final nextSecond = when.add(const Duration(seconds: 1));
      final retry = await save(nextSecond);
      expect(retry.succeeded, isTrue);
      expect(exports, 1);
      expect(observations, [nextSecond]);
      expect(path.basename(retry.path!), backupFileName(nextSecond));
      expect(await File(retry.path!).length(), greaterThan(0));
    },
  );
}

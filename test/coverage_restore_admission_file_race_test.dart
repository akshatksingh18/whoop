// A restore admitted before a wipe cannot cross the first asynchronous file read.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('restore-admission-file-race', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final compressed in [false, true]) {
    test(
      'wipe invalidates an in-flight file selection with gzip $compressed',
      () async {
        const day = '2021-04-06';
        const note = 'Authored backup note';
        await LocalDb.putJournal(day, '["travel"]', note);
        final exported = File(await LocalDb.exportCopy());
        final source = compressed
            ? await File(
                '${exported.path}.gz',
              ).writeAsBytes(gzip.encode(await exported.readAsBytes()))
            : exported;
        final bytes = await source.readAsBytes();

        final restore = LocalDb.importFromDbFile(source.path);
        final rejected = expectLater(
          restore,
          throwsA(
            isA<DbImportException>().having(
              (e) => e.records,
              'written rows',
              0,
            ),
          ),
        );
        final wipe = LocalDb.wipeAll();
        await rejected;
        await wipe;

        expect(await LocalDb.journalRows(date: day), isEmpty);
        expect(await source.readAsBytes(), bytes);
        await LocalDb.importFromDbFile(source.path);
        final row = (await LocalDb.journalRows(date: day)).single;
        expect(row['note'], note);
        expect(row['tags_json'], '["travel"]');
        expect(await source.readAsBytes(), bytes);
      },
    );
  }
}

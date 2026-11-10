// Strict journal decoding and mixed-picker fallback over authored small files.
// Expensive vendor/backup work uses its existing AppState boundary substitute.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/journal_csv_import.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import 'coverage_import_partial_results_test.dart' show App;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUpAll(() => coverageStore('import-encoding-recovery'));
  setUp(() async {
    await resetCoverageStore();
    root = await (await Directory(
      'build/coverage-remainder/import-encoding-recovery',
    ).absolute.create(recursive: true)).createTemp('authored-');
  });
  tearDownAll(LocalDb.close);
  Future<File> bytes(String name, List<int> value) =>
      File('${root.path}/$name').writeAsBytes(value);

  test(
    'invalid journal UTF-8 is a format refusal before any row is written',
    () async {
      final original = latin1.encode('date,tags,note\n2021-04-06,,café\n');
      final file = await bytes('invalid.csv', original);
      await expectLater(importJournalCsvFile(file.path), throwsFormatException);
      expect(await LocalDb.journalRows(), isEmpty);
      expect(await file.readAsBytes(), original);
    },
  );
  test(
    'missing source remains an I/O failure rather than a format fallback',
    () async {
      final path = '${root.path}/not-created.csv';
      await expectLater(
        importJournalCsvFile(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await LocalDb.journalRows(), isEmpty);
    },
  );
  for (final bom in [false, true]) {
    test(
      'UTF-8 journal preserves authored accents and quoted notes with BOM $bom',
      () async {
        final original = [
          if (bom) ...[0xef, 0xbb, 0xbf],
          ...utf8.encode(
            'date,tags,note\n2021-04-06,Authored,"café, résumé"\n',
          ),
        ];
        final file = await bytes('unicode.csv', original);
        final result = await importJournalCsvFile(file.path);
        expect(result.imported, 1);
        expect(result.rejected, isEmpty);
        expect((await LocalDb.journalRows()).single['note'], 'café, résumé');
        expect(await file.readAsBytes(), original);
      },
    );
  }
  for (final refuse in [false, true]) {
    test(
      'legacy text ${refuse ? 'vendor refusal' : 'vendor routing'} retains earlier committed groups and original bytes',
      () async {
        final app = App()..refuseVendor = refuse;
        addTearDown(app.dispose);
        final backup = await bytes(
          'accepted.db',
          utf8.encode('Authored backup boundary'),
        );
        final journal = await bytes(
          'journal.csv',
          utf8.encode('date,tags,note\n2021-04-06,,Authored retained note\n'),
        );
        final original = latin1.encode('Authored vendor header\ncafé\n');
        final vendor = await bytes('legacy.csv', original);
        final outcome = await runImport(app, [
          backup.path,
          journal.path,
          vendor.path,
        ]);
        expect(app.vendor, [vendor.path]);
        expect(outcome.records, 1);
        expect(outcome.journalRows, 1);
        expect(outcome.days, refuse ? 0 : 3);
        expect(outcome.nothingLanded, false);
        expect(
          outcome.readError,
          refuse ? contains('synthetic vendor refusal') : isNull,
        );
        expect(await LocalDb.session('accepted.db'), isNotNull);
        expect(
          (await LocalDb.journalRows()).single['note'],
          'Authored retained note',
        );
        expect(await vendor.readAsBytes(), original);
      },
    );
  }
}

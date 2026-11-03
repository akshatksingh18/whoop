// Small authored CSVs and the real backup/reset queue. No full backup, KDF,
// old-name migration or heavy derivation is run on this host.
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/journal_csv_import.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('import-limits-backup-reset'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scope in ['tag length', 'tag count']) {
    test(
      'Journal $scope limit rejects only the offending row and preserves its input',
      () async {
        final tags = scope == 'tag length'
            ? List.filled(kMaxTagChars + 1, 'x').join()
            : List.generate(kMaxTagsPerDay + 1, (i) => 'tag-$i').join(';');
        final text =
            'date,tags,note\n2021-04-06,$tags,authored refusal\n'
            '2021-04-07,kept,authored valid note\n';
        final parsed = parseJournalCsv(text, today: DateTime(2021, 4, 8));
        expect(parsed.isEmpty, false);
        expect(parsed.rows.single.date, '2021-04-07');
        expect(parsed.rejected.single.line, 2);
        expect(
          parsed.rejected.single.reason,
          scope == 'tag length'
              ? 'a tag is longer than 64 characters'
              : '65 tags (limit 64)',
        );
        await LocalDb.putJournal('2021-04-06', '["old"]', 'keep original');
        await LocalDb.putJournal(
          '2021-04-05',
          '["unrelated"]',
          'keep unrelated',
        );
        final dir = await Directory(
          'build/coverage-remainder/import-limits-backup-reset',
        ).absolute.create(recursive: true);
        final file = await File(
          '${dir.path}/authored-$scope.csv',
        ).writeAsString(text);
        final bytes = await file.readAsBytes();
        final before = await (await LocalDb.instance).query(
          'journal',
          where: 'date != ?',
          whereArgs: ['2021-04-07'],
          orderBy: 'date',
        );
        final result = await importJournalCsvFile(
          file.path,
          today: DateTime(2021, 4, 8),
        );
        expect(result.imported, 1);
        expect(result.rejected.single.reason, parsed.rejected.single.reason);
        final db = await LocalDb.instance;
        expect(
          await db.query(
            'journal',
            where: 'date != ?',
            whereArgs: ['2021-04-07'],
            orderBy: 'date',
          ),
          before,
        );
        final imported = (await db.query(
          'journal',
          where: 'date = ?',
          whereArgs: ['2021-04-07'],
        )).single;
        expect(imported['tags_json'], '["kept"]');
        expect(imported['note'], 'authored valid note');
        expect(await file.readAsBytes(), bytes);
      },
    );
  }

  for (final scope in ['tag length', 'tag count']) {
    test(
      'Journal exact $scope boundary is accepted without truncating entered tags',
      () {
        final tags = scope == 'tag length'
            ? [List.filled(kMaxTagChars, 'x').join()]
            : List.generate(kMaxTagsPerDay, (i) => 'tag-$i');
        final parsed = parseJournalCsv(
          'date,tags,note\n2021-04-06,${tags.join(';')},\n',
          today: DateTime(2021, 4, 8),
        );
        expect(parsed.rejected, isEmpty);
        expect(parsed.rows.single.tags, tags);
        expect(parsed.isEmpty, false);
      },
    );
  }

  test(
    'Journal header-only is empty while a rejected-only file remains actionable',
    () {
      expect(parseJournalCsv('date,tags,note\n').isEmpty, true);
      final refused = parseJournalCsv('date,tags,note\n2021-04-06,,\n');
      expect(refused.rows, isEmpty);
      expect(refused.isEmpty, false);
      expect(
        refused.rejected.single.toString(),
        'line 2: no tags and no note — nothing to import',
      );
      expect(
        () => parseJournalCsv('wrong,header\n'),
        throwsA(
          isA<JournalCsvFormatException>().having(
            (e) => e.toString(),
            'caller diagnostic',
            startsWith(
              'JournalCsvFormatException: this is not a journal export',
            ),
          ),
        ),
      );
    },
  );

  for (final refusal in [false, true]) {
    test(
      'Backup reset refuses nesting and retains one owner through ${refusal ? 'failure' : 'success'}',
      () async {
        final entered = Completer<void>(), release = Completer<void>();
        var writes = 0, reads = 0;
        final reset = withoutBackupsDuringReset(() async {
          entered.complete();
          await release.future;
          if (refusal) throw StateError('authored reset refusal');
          return 'finished';
        });
        await entered.future;
        // Observe the original Future's failure before releasing it.
        final finish = refusal
            ? expectLater(reset, throwsStateError)
            : expectLater(reset, completion('finished'));
        try {
          await expectLater(
            withoutBackupsDuringReset(() async {
              fail('Nested reset must never start');
            }),
            throwsA(
              isA<StateError>().having(
                (e) => e.message,
                'one-owner guard',
                'Reset is already running',
              ),
            ),
          );
          final blocked = await runBackup(
            passphrase: () async {
              reads++;
              return 'authored unused';
            },
            exportSnapshot: () async {
              writes++;
              fail('Reset owns publication');
            },
          );
          expect(blocked.skipped, true);
          expect(blocked.succeeded, false);
          expect(reads, 0);
          expect(writes, 0);
        } finally {
          release.complete();
          await finish;
        }
        final retry = await runBackup(
          passphrase: () async {
            reads++;
            return null;
          },
        );
        expect(reads, 1);
        expect(retry.skipped, false);
        expect(retry.needsPassphrase, true);
        expect(retry.error, kBackupNeedsPassphrase);
        expect(writes, 0);
      },
    );
  }

  test(
    'Backup sorting has a stable extension tie-breaker and retains every same-second format',
    () {
      const names = [
        'whoop-20210406-120000.db',
        'whoop-20210406-120000.db.gz',
        'whoop-20210406-120000.osbk',
        'whoop-20210406-120000-2.osbk',
        'whoop-20210405-120000.osbk',
      ];
      final expected = [names[3], names[2], names[1], names[0], names[4]];
      for (final input in [names, names.reversed]) {
        final sorted = sortBackupsNewestFirst([
          ...input.map(File.new),
          File('unrelated.db'),
          Directory('whoop-20210407-120000.osbk'),
        ]).map((f) => f.path).toList();
        expect(sorted, expected);
      }
      expect(BackupCadence.fromName('weekly').label, 'Weekly');
      expect(
        BackupCadence.fromName('weekly').interval,
        const Duration(days: 7),
      );
    },
  );
}

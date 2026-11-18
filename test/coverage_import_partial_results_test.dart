// Real picker-format routing and journal writes; expensive sensor importers are
// replaced at their existing AppState boundary with explicit partial outcomes.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/noop_import.dart';
import 'package:whoop_companion/import/whoop_import.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import 'support/coverage_store.dart';

class App extends AppState {
  App() : super.forTesting();
  final backups = <String>[], raw = <String>[], vendor = <String>[];
  bool refuseVendor = false;
  @override
  Future<int> importEdgeBackup(String path) async {
    final name = path.split(RegExp(r'[/\\]')).last;
    backups.add(name);
    lastImportRecords = 0;
    if (name == 'refused.db') {
      throw StateError('synthetic backup preflight refusal');
    }
    // An importer can commit one table before a later table fails. The router
    // must count and retain that work, not label the whole selection a failure.
    await LocalDb.putSession({
      'id': name,
      'type': 'swimming',
      'start_ts': 1617710400,
      'end_ts': 1617711000,
      'status': 'done',
      'created_at': 1,
    });
    lastImportRecords = 1;
    if (name == 'partial.db') throw StateError('synthetic later-table refusal');
    importRollupError = 'synthetic summary refusal';
    return 0;
  }

  @override
  Future<int> importNoopCsv(
    String path, {
    void Function(int)? onProgress,
  }) async {
    raw.add(path);
    if (path.endsWith('refused-raw.csv')) {
      throw StateError('synthetic raw refusal');
    }
    lastNoopImport = NoopImportResult(
      2,
      4,
      3,
      0,
      {'2021-04-02'},
      {'synthetic_table'},
    );
    return 2;
  }

  @override
  Future<int> importWhoopCsvs(
    List<String> paths, {
    void Function(int)? onProgress,
  }) async {
    vendor.addAll(paths);
    if (refuseVendor) throw StateError('synthetic vendor refusal');
    lastWhoopImport = WhoopImportResult(3, 2, 4);
    return 3;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late App app;
  late Directory dir;
  setUpAll(() async {
    await coverageStore('import-partial-results');
    dir = Directory(
      'build/coverage-remainder/cov44-import-partial-results',
    ).absolute;
  });
  setUp(() async {
    await resetCoverageStore();
    app = App();
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<String> file(String name, String data) async =>
      (await File('${dir.path}/$name').writeAsString(data)).path;
  Future<String> backup(String name) =>
      file(name, 'Authored routing-boundary bytes');
  Future<String> raw(String name) => file(
    name,
    'unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z\n'
    '1617710400,2021-04-06T12:00:00Z,hr,60,,,,\n',
  );

  test(
    'mixed backup failures name each refused file while retaining the one committed table',
    () async {
      final out = await runImport(app, [
        await backup('refused.db'),
        await backup('partial.db'),
        await backup('accepted.db'),
      ]);
      expect(app.backups, ['refused.db', 'partial.db', 'accepted.db']);
      expect(out.days, 0);
      expect(out.records, 2);
      expect(out.nothingLanded, false);
      expect(out.readError, contains('refused.db, partial.db'));
      expect(out.readError, contains('synthetic backup preflight refusal'));
      expect(out.rollupError, 'synthetic summary refusal');
      expect(await LocalDb.session('refused.db'), isNull);
      expect(await LocalDb.session('partial.db'), isNotNull);
      expect(await LocalDb.session('accepted.db'), isNotNull);
    },
  );

  test(
    'failed raw file does not discard the next raw result or a vendor result and their limitations',
    () async {
      final out = await runImport(app, [
        await raw('refused-raw.csv'),
        await raw('accepted-raw.csv'),
        await file('vendor.csv', 'Synthetic vendor header\nSynthetic value\n'),
      ]);
      expect(app.raw, hasLength(2));
      expect(app.vendor, hasLength(1));
      expect(out.days, 5);
      expect(out.workouts, 2);
      expect(out.skippedDays, 4);
      expect(out.lateRows, 3);
      expect(out.strandedDays, 1);
      expect(out.corruptTables, {'synthetic_table'});
      expect(out.readError, contains('refused-raw.csv'));
      expect(out.source, 'Raw sensor export + Vendor CSV export');
    },
  );

  test(
    'journal rows really land and raise revision even when a vendor file is refused',
    () async {
      app.refuseVendor = true;
      final before = app.insightsRevision.value;
      final out = await runImport(app, [
        await file(
          'journal.csv',
          'date,tags,note\n2021-04-06,Synthetic tag,Authored test note\n2021-19-80,,Invalid authored date\n',
        ),
        await file('vendor.csv', 'Synthetic vendor header\nSynthetic value\n'),
      ]);
      expect(out.journalRows, 1);
      expect(out.rejectedRows, hasLength(1));
      expect(out.rejectedRows.single, contains('line 3'));
      expect(out.readError, contains('synthetic vendor refusal'));
      expect(out.nothingLanded, false);
      expect(app.insightsRevision.value, greaterThan(before));
      final rows = await LocalDb.journalRows(date: '2021-04-06');
      expect(rows.single['note'], 'Authored test note');
      expect(jsonDecode(rows.single['tags_json'] as String), ['Synthetic tag']);
      expect(out.source, 'Journal CSV');
    },
  );

  test(
    'a wholly refused backup selection throws rather than claiming zero-row success',
    () async {
      await expectLater(
        runImport(app, [await backup('refused.db')]),
        throwsStateError,
      );
      expect((await LocalDb.instance).isOpen, true);
      expect(await LocalDb.session('refused.db'), isNull);
    },
  );
}

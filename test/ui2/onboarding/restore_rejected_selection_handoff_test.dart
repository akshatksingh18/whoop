// Real rejected restore inputs. The observer delegates every import to AppState;
// malformed sources fail before any derivation worker can be started.
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import '../../support/coverage_store.dart';

class _App extends AppState {
  _App() : super.forTesting();
  final attempts = <String>[];
  @override
  Future<int> importEdgeBackup(String path) {
    attempts.add(path);
    return super.importEdgeBackup(path);
  }
}

Future<String> _hash(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(
    () => coverageStore('restore-rejected-selection-handoff', fresh: true),
  );
  setUp(() async {
    await resetCoverageStore();
    await BodyLogDb.putWeight('2021-04-06', 70, 'kg');
    await LocalDb.putJournal(
      '2021-04-06',
      '["authored"]',
      'Preserve this unrelated authored note.',
    );
  });
  tearDownAll(LocalDb.close);
  for (final mode in ['corrupt', 'missing', 'truncated gzip', 'two rejected']) {
    test(
      'all-rejected $mode restore reports refusal and preserves inputs/history on retry',
      () async {
        final dir = await (await getTemporaryDirectory()).createTemp(
          'authored-rejection-',
        );
        final first = await File(
          '${dir.path}/authored.db',
        ).writeAsString('Authored non-SQLite content.');
        final second = await File(
          '${dir.path}/another.db',
        ).writeAsString('Different authored non-SQLite content.');
        final compressed = File('${dir.path}/authored.db.gz');
        final bytes = gzip.encode(List.generate(64, (i) => (i * 17 + 3) & 255));
        await compressed.writeAsBytes(bytes.sublist(0, bytes.length - 4));
        final missing = '${dir.path}/missing.db';
        final paths = switch (mode) {
          'corrupt' => [first.path],
          'missing' => [missing],
          'truncated gzip' => [compressed.path],
          _ => [first.path, second.path],
        };
        final inputs = {
          for (final f in [first, second, compressed]) f.path: await _hash(f),
        };
        final db = await LocalDb.instance;
        final before = {
          for (final table in [
            'body_weight',
            'body_weight_reading',
            'journal',
            'day_result',
            'metric_series',
            'samples',
          ])
            table: await db.query(table),
        };
        final app = _App();
        addTearDown(app.dispose);
        for (var attempt = 0; attempt < 2; attempt++) {
          await expectLater(runImport(app, paths), throwsA(isA<Exception>()));
          expect(app.lastImportRecords, 0);
          expect(app.importRollupError, isNull);
          expect(app.reanalyzing, false);
          expect(app.attempts, [for (var n = 0; n <= attempt; n++) ...paths]);
          for (final entry in before.entries) {
            expect(await db.query(entry.key), entry.value);
          }
          for (final entry in inputs.entries) {
            expect(await _hash(File(entry.key)), entry.value);
          }
          expect(await File(missing).exists(), false);
        }
        // A refused read must close its source so it remains movable/recoverable.
        expect(
          await _hash(await first.rename('${first.path}.retained')),
          inputs[first.path],
        );
        expect(
          await _hash(await second.rename('${second.path}.retained')),
          inputs[second.path],
        );
        expect(
          await _hash(await compressed.rename('${compressed.path}.retained')),
          inputs[compressed.path],
        );
      },
    );
  }
}

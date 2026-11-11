// The real backup merge admits retained naps without duration detail. Use its
// real repository/page projection, rather than a fabricated screen repository.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/naps.dart';
import 'coverage_restore_scalar_shape_recovery_test.dart' show sourceFile, date;
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('restored-nap-duration', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final explicitNull in [false, true]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets('restored ${explicitNull ? 'null' : 'missing'} nap duration '
          'at $scale keeps retained detection and source unchanged', (t) async {
        final backup = (await t.runAsync(() => sourceFile('map')))!;
        final source = (await t.runAsync(
          () => databaseFactory.openDatabase(backup.path),
        ))!;
        final payload = jsonEncode({
          'date': date,
          'naps': {
            'value': [
              {
                'start':
                    DateTime(2021, 4, 6, 14).millisecondsSinceEpoch ~/ 1000,
                'end':
                    DateTime(2021, 4, 6, 14, 30).millisecondsSinceEpoch ~/ 1000,
                if (explicitNull) 'duration_min': null,
                'source': 'detected',
              },
            ],
          },
        });
        await t.runAsync(
          () => source.update('day_result', {'payload_json': payload}),
        );
        await t.runAsync(source.close);
        final bytes = (await t.runAsync(backup.readAsBytes))!;
        final db = await LocalDb.instance;
        final other = (await t.runAsync(() => db.query('day_result')))!;
        final counts = (await t.runAsync(
          () => LocalDb.importFromDbFile(backup.path),
        ))!;
        expect(counts['day_result'], 1);
        final saved = (await t.runAsync(() => db.query('day_result')))!;
        expect(saved.where((r) => r['day_id'] != date).toList(), other);
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => null);
        addTearDown(app.dispose);
        final projected = (await t.runAsync(() => app.repo!.getDayNaps(date)))!;
        final nap = (projected['naps'] as List).single as Map;
        expect(nap['duration_min'], isNull);
        expect(nap.containsKey('duration_min'), explicitNull);
        await localizedPage(
          t,
          const NapsScreen(day: date),
          app: app,
          scale: scale,
        );
        await flush(t);
        expect(find.text('Detected'), findsOneWidget);
        expect(find.text('30m asleep · detected'), findsNothing);
        expect(find.text('No naps on this day'), findsNothing);
        expect(find.text('Not a nap'), findsOneWidget);
        expect(find.text('Log a nap'), findsOneWidget);
        expect(await t.runAsync(() => db.query('day_result')), saved);
        expect(await t.runAsync(() => LocalDb.napEdits(date)), isEmpty);
        expect(await t.runAsync(backup.readAsBytes), bytes);
      });
    }
  }
}

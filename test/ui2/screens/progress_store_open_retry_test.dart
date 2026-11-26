import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';

import 'nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('progress-store-open-retry', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final openedBeforeFailure in [false, true]) {
    testWidgets(
      'Progress keeps saved records across database open refusal after initial read: $openedBeforeFailure',
      (t) async {
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        addTearDown(app.dispose);
        final originalPath = LocalDb.dbName;
        final marker = File(
          '${File(originalPath).parent.path}/authored-storage-obstacle',
        );
        await t.runAsync(
          () => marker.writeAsString(
            'Personal data is never used by this fixture.',
          ),
        );
        addTearDown(() async {
          await LocalDb.close();
          LocalDb.dbName = originalPath;
        });
        await LocalDb.putSession({
          'id': 'authored-progress-history',
          'start_ts': 1617714000,
          'type': 'running',
          'status': 'finished',
          'source': 'manual',
          'created_at': 1,
        });
        final original = await LocalDb.session('authored-progress-history');
        expect(original, isNotNull);

        Future<void> refuseOpen() async {
          await t.runAsync(LocalDb.close);
          // A file cannot be the parent of a SQLite path. The saved database
          // itself stays exactly where it was and is reopened on retry.
          LocalDb.dbName = '${marker.path}/unavailable.sqlite';
        }

        if (!openedBeforeFailure) await refuseOpen();
        await localizedPage(t, const ProgressScreen(), app: app, settle: false);
        await io(t);
        if (openedBeforeFailure) {
          expect(find.text('Progress could not load'), findsNothing);
          await refuseOpen();
          app.bumpInsights();
          await io(t);
        }
        expect(find.text('Progress could not load'), findsOneWidget);
        expect(find.text('Your saved records are intact.'), findsOneWidget);

        LocalDb.dbName = originalPath;
        final retry = find.text('Retry');
        await reveal(t, retry);
        await t.tap(retry);
        await io(t);
        expect(find.text('Progress could not load'), findsNothing);
        expect(find.text('Progress'), findsOneWidget);
        expect(await LocalDb.session('authored-progress-history'), original);
        expect(
          await t.runAsync(marker.readAsString),
          'Personal data is never used by this fixture.',
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}

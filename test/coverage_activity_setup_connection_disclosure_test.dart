// Opening setup discloses the connection without starting a recording.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/setup.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_connection_lifecycle_test.dart' show LifecycleBand;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('activity-setup-connection-disclosure');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final connected in [false, true]) {
    testWidgets(
      'actual setup host shows the current band connection: $connected',
      (t) async {
        final band = LifecycleBand();
        if (connected) {
          band.connecting = (_) async => true;
          await band.connectToRemoteId('authored-setup-band');
          band.calls.clear();
        }
        final app = AppState.forTesting(engine: band);
        addTearDown(app.dispose);
        final running = activityByName('Running')!;
        await localizedPage(
          t,
          ActivitySetup(running, weightKg: 70, host: activityHost(app)),
          push: true,
        );
        expect(
          find.text(connected ? 'Band connected' : 'No band connected'),
          findsOneWidget,
        );
        expect(
          find.text(connected ? 'No band connected' : 'Band connected'),
          findsNothing,
        );
        final back = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Back',
        );
        await t.tap(back);
        await t.pumpAndSettle();
        expect(find.byType(ActivitySetup), findsNothing);
        expect(find.text('Closed test page'), findsOneWidget);
        expect(band.calls, isEmpty);
        expect(app.activeWorkout, isNull);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('sessions'),
          ),
          isEmpty,
        );
      },
    );
  }
}

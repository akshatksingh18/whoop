// Actual stored-session navigation, sources and Back; no native radio claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/profile/settings.dart' show EditProfile;
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_session_destination_boundaries_test.dart' show io;
import 'support/audit_visual.dart';
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class DisconnectedBand extends AppState {
  DisconnectedBand() : super.forTesting() {
    engine.state.generation = 'gen4';
    user = {
      'name': 'Authored profile',
      'age': 30,
      'sex': 'f',
      'height_cm': 170,
      'weight_kg': 70,
    };
    repo = LocalRepositoryImpl(getProfileMap: () => user);
  }
  @override
  bool get isPaired => true;
  @override
  bool get isConnected => false;
}

void main() {
  setUpAll(() async {
    WidgetsApp.debugAllowBannerOverride = false;
    await loadAuditFonts();
    await coverageStore('session-band-help');
  });
  setUp(resetCoverageStore);
  tearDownAll(() async {
    await LocalDb.close();
    WidgetsApp.debugAllowBannerOverride = true;
  });
  for (final scale in [1.0, 2.0, 3.1]) {
    for (final tab in ['Overview', 'Graphs']) {
      testWidgets(
        '$tab band help returns to the same dated session without writes scale=$scale',
        (t) async {
          final app = DisconnectedBand();
          final units = UnitsController.withUnits();
          addTearDown(app.dispose);
          addTearDown(units.dispose);
          await t.runAsync(() async {
            await LocalDb.putSession({
              'id': 'authored-no-pulse',
              'type': 'other',
              'status': 'done',
              'start_ts':
                  DateTime(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000,
              'end_ts':
                  DateTime(2021, 4, 6, 12, 30).millisecondsSinceEpoch ~/ 1000,
              'duration_min': 30,
              'rpe': 5,
              'source': 'manual',
              'created_at': 1,
            });
            await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
          });
          expect(t.takeException(), isNull);
          await localizedPage(
            t,
            const SessionDestination('authored-no-pulse'),
            app: app,
            units: units,
            scale: scale,
            capture: true,
          );
          t.view.physicalSize = const Size(430, 932);
          await io(t);
          expect(find.byType(ActivitySummary), findsOneWidget);
          if (tab == 'Graphs') {
            await reveal(t, find.text('Graphs').first);
            await t.tap(find.text('Graphs').first);
            await io(t);
          }
          final original = t.state(find.byType(ActivitySummary));
          final db = (await t.runAsync(() => LocalDb.instance))!;
          final sessionBefore = await t.runAsync(() => db.query('sessions'));
          final metricsBefore = await t.runAsync(
            () => db.query('metric_series'),
          );
          final vertical = find
              .byWidgetPredicate(
                (w) =>
                    w is Scrollable &&
                    (w.axisDirection == AxisDirection.down ||
                        w.axisDirection == AxisDirection.up),
              )
              .last;
          await captureAuditScroll(
            t,
            '${tab.toLowerCase()}_$scale',
            prefix: 'coverage102_session_band_help',
            scrollable: vertical,
          );
          await reveal(t, find.text('Check band connection'));
          await t.tap(find.text('Check band connection'));
          await io(t);
          expect(find.byType(MyDevices), findsOneWidget);
          expect(find.byType(EditProfile), findsNothing);
          expect(find.text('My sources'), findsOneWidget);
          expect(find.text('Your band'), findsOneWidget);
          if (tab == 'Overview') {
            await captureAuditScroll(
              t,
              'sources_$scale',
              prefix: 'coverage102_session_band_help',
            );
          }
          final back = find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == 'Back',
          );
          await t.tap(back);
          await io(t);
          expect(find.byType(MyDevices), findsNothing);
          expect(t.state(find.byType(ActivitySummary)), same(original));
          expect(find.textContaining('Apr 6, 2021'), findsWidgets);
          expect(
            find.text(
              tab == 'Graphs'
                  ? 'No series to plot'
                  : 'No heart rate for this session',
            ),
            findsOneWidget,
          );
          expect(await t.runAsync(() => db.query('sessions')), sessionBefore);
          expect(
            await t.runAsync(() => db.query('metric_series')),
            metricsBefore,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}

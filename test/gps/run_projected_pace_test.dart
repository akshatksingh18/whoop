// MapKit's thinned coordinates keep the corresponding saved pace colors.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/gps/map_snapshot.dart';
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/run_detail.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';

import 'map_snapshot_test.dart' show reply;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/localized_coverage.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/map_snapshot');
  setUpAll(loadAuditFonts);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final accepted in [false, true]) {
    testWidgets(
      'Run map keeps pace ownership with native projection accepted: $accepted',
      (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          final requested = <List<double>>[];
          binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
            call,
          ) async {
            final lat = (call.arguments['lat'] as List).cast<double>();
            requested.add(lat.toList());
            return accepted ? reply(lat.length) : null;
          });
          const count = 605;
          final start = DateTime(2021, 4, 6, 9);
          final track = [
            for (var i = 0; i < count; i++)
              RoutePoint(
                seq: i,
                tsMs: start.millisecondsSinceEpoch + i * 1000,
                lat: i * .00002,
                lng: 0,
              ),
          ];
          final savedPace = [for (var i = 0; i < count; i++) i / count];
          final result = ActivityResult(
            activityByName('Running')!,
            start: start,
            duration: const Duration(seconds: count),
            sessionId: 'authored-projection-pace-$accepted',
            track: track,
            route: [for (var i = 0; i < count; i++) Offset(.5, i / count)],
            routePace: savedPace,
          );
          await localizedPage(
            t,
            Scaffold(body: RunMapCard(RunView(result), cursor: count - 1)),
          );
          final paint = find.descendant(
            of: find.byType(RunMapCard),
            matching: find.byWidgetPredicate(
              (widget) => widget is CustomPaint && widget.painter != null,
            ),
          );
          final dynamic renderer = t.widget<CustomPaint>(paint).painter;
          final indices = thinnedIndex(count);
          expect(indices.length, lessThan(count));
          expect(requested.single, [for (final i in indices) track[i].lat]);
          expect(
            renderer.pace,
            accepted ? [for (final i in indices) savedPace[i]] : savedPace,
          );
          expect(find.byType(Image), accepted ? findsOneWidget : findsNothing);
          expect(result.routePace, savedPace);
          expect(result.track, track);
          expect(t.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}

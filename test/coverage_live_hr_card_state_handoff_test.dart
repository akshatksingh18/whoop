import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/paired_device.dart';
import 'package:whoop_companion/ui2/live_hr.dart';

import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  const id = 'authored-live-band';
  PairedDevice? paired;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('live-hr-card-state-handoff', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    await PairedDevice.save(id, null);
    paired = await PairedDevice.load();
  });
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets('live HR redraws when the capped trace changes at ${scale}x', (
      tester,
    ) async {
      final app = AppState.forTesting()..paired = paired;
      addTearDown(app.dispose);
      expect(app.paired?.remoteId, id);
      final state = app.device..connection = 'connected';
      app.engine.onState(state);
      await localizedPage(
        tester,
        const Scaffold(body: LiveHrCard()),
        app: app,
        scale: scale,
      );
      expect(
        find.text(
          'No beat in the last ${AppState.liveHrMaxAge.inSeconds} seconds.',
        ),
        findsOneWidget,
      );
      expect(find.text('LIVE'), findsNothing);

      final capacity = AppState.liveHrTraceMax;
      final start = DateTime.now().millisecondsSinceEpoch - capacity - 10;
      for (var i = 0; i < capacity; i++) {
        state.liveHr = i == 0 ? 40 : 60;
        state.liveHrAt = start + i;
        app.engine.onState(state);
      }
      await tester.pump();
      expect(find.text('60'), findsOneWidget);
      expect(
        find.textContaining('The last $capacity readings'),
        findsOneWidget,
      );
      expect(find.textContaining('40–60 bpm'), findsOneWidget);
      final revision = app.liveHrTraceRev;

      app.engine.onState(state);
      await tester.pump();
      expect(app.liveHrTraceRev, revision);
      state.liveHrAt = start + capacity;
      app.engine.onState(state);
      await tester.pump();
      expect(app.liveHr, 60);
      expect(app.liveHrTrace, hasLength(capacity));
      expect(app.liveHrTraceRev, revision + 1);
      expect(find.text('60'), findsOneWidget);
      expect(find.textContaining('60–60 bpm'), findsOneWidget);
      expect(find.textContaining('40–60 bpm'), findsNothing);

      state.connection = 'disconnected';
      app.engine.onState(state);
      await tester.pump();
      expect(
        find.textContaining('Your band is not connected.'),
        findsOneWidget,
      );
      expect(find.text('LIVE'), findsNothing);
      expect(app.liveHrTrace, isEmpty);
      final db = await LocalDb.instance;
      expect(await db.query('decoded_onehz'), isEmpty);
      expect(await db.query('sessions'), isEmpty);
      expect((await tester.runAsync(PairedDevice.load))?.remoteId, id);
      expect(tester.takeException(), isNull);
    });
  }
}

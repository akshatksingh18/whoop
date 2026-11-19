// Recover a retained one-hull checkpoint with incomplete phone-clock evidence.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('legacy-step-clock-fallback'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final missing in ['both', 'last']) {
    test(
      'legacy checkpoint recovers a band hull when phone time is missing $missing',
      () async {
        const key = 'live_session_checkpoint';
        final start = DateTime(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          key,
          jsonEncode({
            'steps': 100,
            'samples': 6000,
            'cover_start_ts': start,
            'cover_end_ts': start + 60,
            if (missing == 'last') 'first_ingest_ms': (start + 7) * 1000,
          }),
        );

        final app = AppState.forTesting();
        addTearDown(app.dispose);
        final db = await LocalDb.instance;
        expect(await db.query('live_coverage'), isEmpty);
        await app.debugFinalizeLivePedometer();
        final stored = await db.query('live_coverage');
        expect(stored, hasLength(1));
        expect(stored.single, containsPair('start_ts', start));
        expect(stored.single, containsPair('end_ts', start + 60));
        expect(stored.single, containsPair('steps', 100));
        expect(prefs.getString(key), isNull);

        await app.debugFinalizeLivePedometer();
        expect(await db.query('live_coverage'), stored);
      },
    );
  }
}

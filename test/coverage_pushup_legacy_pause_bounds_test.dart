// Cross-clock pause records from earlier imports remain available verbatim.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushups.dart';

import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('pushup-legacy-pause-bounds'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final lateResume in [false, true]) {
    test(
      'saved pause preserves clocks with a late Resume: $lateResume',
      () async {
        const day = '2021-04-06';
        final start = DateTime(2021, 4, 6, 9);
        final end = start.add(const Duration(hours: 1));
        final session = PushupSession(
          id: 'authored-cross-clock-day',
          day: day,
          started: start,
          ended: end,
          interval: 30,
          state: PushupState.ended,
          events: [
            PushupEvent(
              id: 'authored-late-pause',
              at: start.add(const Duration(minutes: 45)),
              kind: PushupEventKind.pause,
            ),
            if (lateResume)
              PushupEvent(
                id: 'authored-late-resume',
                at: end.add(const Duration(minutes: 10)),
                kind: PushupEventKind.resume,
              ),
          ],
        );
        await PushupDb.save(session);
        final db = await LocalDb.instance;
        final saved = await db.query('pushup_session');

        final summary = PushupDay.all(await PushupDb.all(), end).single;
        expect(summary.day, day);
        expect(summary.active, const Duration(minutes: 45));
        expect(summary.paused, const Duration(minutes: 15));
        expect(summary.pauses.single, (from: session.events.first.at, to: end));
        expect(await db.query('pushup_session'), saved);
      },
    );
  }
}

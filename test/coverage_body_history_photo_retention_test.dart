// Authored pixels and SQLite only. Removing one history photo cannot remove
// the same day's weight/tape; refused deletion keeps both its file and row.
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'coverage_body_history_actions_test.dart'
    show App, flush, matchingAction;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-history-photo-retention');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final mode in ['cancel', 'delete', 'refuse-retry']) {
    testWidgets(
      'history photo $mode preserves its day measurements and exposes the real store outcome',
      (t) async {
        final app = App()..user = {'weight_kg': 70};
        addTearDown(app.dispose);
        await BodyLogDb.putWeight('2021-04-06', 70, 'kg', historyOnly: true);
        await BodyLogDb.putMeasure(
          BodyMeasure(
            id: 'synthetic-history-tape',
            date: '2021-04-06',
            recordedAt: DateTime(2021, 4, 6, 12),
            inches: {'waistNavel': 32},
          ),
        );
        final photo = (await t.runAsync(
          () => BodyLogDb.addPhoto(
            img.encodeJpg(img.Image(width: 8, height: 12)),
            date: '2021-04-06',
            pose: 'front',
          ),
        ))!;
        final photoFile = (await t.runAsync(() => BodyLogDb.photoFile(photo)))!,
            db = await LocalDb.instance;
        final data = ProgressData(
          weights: await BodyLogDb.weights(),
          measures: await BodyLogDb.measures(),
          photos: [photo],
          lifts: [],
          food: [],
          steps: [],
          sleepMin: [],
          recovery: [],
          sessions: [],
          baseline: '2021-04-06',
          heightCm: 170,
        );
        await localizedPage(t, BodyHistoryScreen(data: data), app: app);
        await flush(t);
        Future<void> ask() async {
          final f = matchingAction('front photo, ');
          await reveal(t, f);
          await t.tap(f);
          await t.pumpAndSettle();
          expect(find.text('Delete this photo?'), findsOneWidget);
          expect(
            find.textContaining("That day's weight and measurements stay."),
            findsOneWidget,
          );
        }

        await ask();
        if (mode == 'cancel') {
          await t.tap(find.text('Keep it'));
          await flush(t);
          expect((await t.runAsync(BodyLogDb.photos))!.single.id, photo.id);
          expect(await t.runAsync(photoFile.exists), true);
        } else {
          if (mode == 'refuse-retry') {
            await db.execute(
              "CREATE TRIGGER synthetic_photo_history_refusal BEFORE DELETE ON body_photo BEGIN SELECT RAISE(ABORT,'synthetic history refusal'); END",
            );
          }
          try {
            await t.tap(find.text('Delete').last);
            await flush(t);
            if (mode == 'refuse-retry') {
              expect(
                find.text('Could not delete it. Try again.'),
                findsOneWidget,
              );
              expect((await t.runAsync(BodyLogDb.photos))!.single.id, photo.id);
              expect(await t.runAsync(photoFile.exists), true);
              await db.execute('DROP TRIGGER synthetic_photo_history_refusal');
              await ask();
              await t.tap(find.text('Delete').last);
              await flush(t);
            }
            expect(await t.runAsync(BodyLogDb.photos), isEmpty);
            expect(await t.runAsync(photoFile.exists), false);
            expect(matchingAction('front photo, '), findsNothing);
          } finally {
            await db.execute(
              'DROP TRIGGER IF EXISTS synthetic_photo_history_refusal',
            );
          }
        }
        expect((await t.runAsync(BodyLogDb.weights))!.single.kg, 70);
        expect(
          (await t.runAsync(BodyLogDb.measures))!.single.inches['waistNavel'],
          32,
        );
        expect(app.profileWrites, isEmpty);
      },
    );
  }
}

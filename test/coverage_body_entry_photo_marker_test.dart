import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart' show Pressable;

import 'coverage_nutrition_root_test.dart' show ago, io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-entry-photo-marker', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'only the weigh-in with an associated photo has a marker at ${scale}x',
      (tester) async {
        final day = ago(2), other = ago(1);
        final saved = (await tester.runAsync(() async {
          final photo = await BodyLogDb.addPhoto(
            img.encodeJpg(img.Image(width: 8, height: 12)),
            date: day,
            pose: 'front',
          );
          await BodyLogDb.putWeight(day, 71.2, 'kg');
          await BodyLogDb.putWeight(other, 72.4, 'kg');
          final media = await BodyLogDb.photoFile(photo);
          final db = await LocalDb.instance;
          return (
            db: db,
            media: media,
            bytes: await media.readAsBytes(),
            images: await db.query('body_photo'),
            weights: await db.query('body_weight_reading', orderBy: 'date'),
          );
        }))!;
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        addTearDown(app.dispose);
        final page = progressDetailPage(
          ProgressDest.weight,
          range: ProgressRange.all,
        );
        await localizedPage(
          tester,
          page,
          app: app,
          scale: scale,
          settle: false,
        );
        await io(tester);
        Finder entry(String value) => find.byWidgetPredicate(
          (widget) =>
              widget is Pressable &&
              widget.semanticLabel?.endsWith(', $value kg') == true,
        );
        Finder marker(Finder row) =>
            find.descendant(of: row, matching: find.byIcon(LucideIcons.image));
        final withPhoto = entry('71.2'), withoutPhoto = entry('72.4');
        await reveal(tester, withPhoto);
        expect(marker(withPhoto), findsOneWidget);
        await reveal(tester, withoutPhoto);
        expect(marker(withoutPhoto), findsNothing);
        await tester.runAsync(() async {
          expect(await saved.db.query('body_photo'), saved.images);
          expect(
            await saved.db.query('body_weight_reading', orderBy: 'date'),
            saved.weights,
          );
          expect(await saved.media.readAsBytes(), saved.bytes);
        });
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}

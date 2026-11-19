// The active Body detail photo door hands over the complete retained photo list.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_body_history_actions_test.dart' show flush;
import 'coverage_localized_progress_test.dart' show progress;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-detail-photo-navigation', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final dest in [ProgressDest.weight, ProgressDest.waist]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        '${dest.name} photo door at $scale returns to the same detail and retains original media',
        (t) async {
          final photos = (await t.runAsync(
            () async => [
              await BodyLogDb.addPhoto(
                img.encodeJpg(img.Image(width: 8, height: 12)),
                date: '2021-04-06',
                pose: 'front',
              ),
              await BodyLogDb.addPhoto(
                img.encodeJpg(img.Image(width: 9, height: 13)),
                date: '2021-04-20',
                pose: 'side',
              ),
            ],
          ))!;
          final bytes = (await t.runAsync(
            () async => [
              for (final p in photos)
                await (await BodyLogDb.photoFile(p)).readAsBytes(),
            ],
          ))!;
          final rows = (await t.runAsync(
            () async => (await LocalDb.instance).query('body_photo'),
          ))!;
          final data = progress(false)..photos.addAll(photos);
          final page = progressDetailPage(
            dest,
            initial: data,
            range: ProgressRange.all,
          );
          await localizedPage(t, page, scale: scale);
          final before = t.state(find.byWidget(page));
          final card = find.byWidgetPredicate(
            (w) => w is Surface && w.semanticLabel == 'Compare photos',
          );
          await reveal(t, card);
          final callback = t.widget<Surface>(card).onTap;
          expect(callback, isNotNull);
          callback!();
          await flush(t);
          expect(find.byType(PhotoCompareScreen), findsOneWidget);
          expect(
            t
                .widget<PhotoCompareScreen>(find.byType(PhotoCompareScreen))
                .photos
                .map((p) => p.id),
            photos.map((p) => p.id),
          );
          expect(find.text('File missing'), findsNothing);
          expect(find.byType(Image), findsWidgets);
          Navigator.of(t.element(find.byType(PhotoCompareScreen))).pop();
          await flush(t);
          expect(find.byType(PhotoCompareScreen), findsNothing);
          expect(t.state(find.byWidget(page)), same(before));
          expect(data.photos.map((p) => p.id), photos.map((p) => p.id));
          await t.runAsync(() async {
            expect(await (await LocalDb.instance).query('body_photo'), rows);
            for (var i = 0; i < photos.length; i++) {
              expect(
                await (await BodyLogDb.photoFile(photos[i])).readAsBytes(),
                bytes[i],
              );
            }
            expect(
              await (await LocalDb.instance).query('body_weight_reading'),
              isEmpty,
            );
            expect(
              await (await LocalDb.instance).query('body_measure'),
              isEmpty,
            );
          });
        },
      );
    }
  }
}

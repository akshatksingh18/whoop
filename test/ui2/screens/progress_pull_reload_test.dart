import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';

import '../activity/home_read_navigation_test.dart' show App;
import 'nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('progress-pull-reload', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets(
    'pulling Progress rereads a saved weigh-in without another write',
    (tester) async {
      final app = App()..repo = LocalRepositoryImpl(getProfileMap: () => {});
      addTearDown(app.dispose);
      await localizedPage(
        tester,
        const Scaffold(body: ProgressScreen()),
        app: app,
        settle: false,
      );
      await io(tester);
      expect(find.text('Progress could not load'), findsNothing);
      final before = (await readPage(tester)).join(' ');
      expect(before, contains('This week so far: 0 weigh-ins'));

      final today = todayLabel();
      await tester.runAsync(
        () => BodyLogDb.putWeight(today, 72.4, 'kg', notify: false),
      );
      final saved = (await BodyLogDb.weights()).single;
      expect(saved.date, today);
      expect(saved.kg, 72.4);
      expect(
        (await readPage(tester)).join(' '),
        contains('This week so far: 0 weigh-ins'),
      );

      final indicator = tester.state<RefreshIndicatorState>(
        find.byType(RefreshIndicator),
      );
      final refresh = indicator.show();
      await io(tester);
      await refresh;
      expect(app.pulls, 1);
      expect(find.text('Synthetic refresh completed'), findsOneWidget);
      expect(
        (await readPage(tester)).join(' '),
        contains('This week so far: 1 weigh-ins'),
      );
      final after = (await BodyLogDb.weights()).single;
      expect(after.date, saved.date);
      expect(after.kg, saved.kg);
      expect(await BodyLogDb.readingsOn(today), hasLength(1));
    },
  );
}

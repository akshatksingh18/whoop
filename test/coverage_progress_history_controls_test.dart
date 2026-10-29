// Dated authored records drive the real retained History controls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_localized_progress_test.dart' show progress;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder action(String s) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == s);
Future<void> tap(WidgetTester t, Finder f) async {
  await reveal(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('progress-history');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  testWidgets(
    'remembered Steps shows measured totals; switching charts persists the choice',
    (t) async {
      final p = (await t.runAsync(SharedPreferences.getInstance))!;
      await p.setString('progress.metric', 'steps');
      await localizedPage(
        t,
        progressDetailPage(
          ProgressDest.overview,
          initial: progress(true),
          range: ProgressRange.week,
        ),
      );
      var text = (await readPage(t)).join(' ');
      expect(text, contains('35,000'));
      expect(text, contains('7 days measured'));
      expect(action('Chart Steps, selected'), findsOneWidget);
      await tap(t, action('Chart Weight'));
      expect(p.getString('progress.metric'), 'weight');
      await tap(t, find.text('Readings').first);
      final scrub = find.byWidgetPredicate(
        (w) => w is Scrubber && w.label == 'Dated Weight chart',
      );
      await reveal(t, scrub);
      t.widget<Scrubber>(scrub).onChanged(1);
      await t.pumpAndSettle();
      expect(
        t
            .widget<ChartFrame>(
              find.ancestor(of: scrub, matching: find.byType(ChartFrame)),
            )
            .readout,
        contains('70 kg'),
      );
      await tap(t, find.text('7-day average').first);
      text = (await readPage(t)).join(' ');
      expect(text, contains('7-day average'));
      expect(p.getString('progress.metric'), 'weight');
    },
  );
  testWidgets(
    'explicit Waist destination overrides a remembered Steps choice and names tape changes',
    (t) async {
      final p = (await t.runAsync(SharedPreferences.getInstance))!;
      await p.setString('progress.metric', 'steps');
      await localizedPage(
        t,
        progressDetailPage(
          ProgressDest.waist,
          initial: progress(true),
          range: ProgressRange.month,
        ),
      );
      final text = (await readPage(t)).join(' ');
      expect(text, contains('TAPE'));
      expect(text, contains('in (−'));
      expect(action('Chart Steps, selected'), findsNothing);
      expect(
        p.getString('progress.metric'),
        'steps',
        reason:
            'An explicit route must not rewrite the remembered chart merely by opening',
      );
    },
  );
  for (final measurement in [false, true]) {
    testWidgets(
      'dated ${measurement ? 'tape' : 'weight'} entry opens the matching correction and cancels without a write',
      (t) async {
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        final d = progress(true);
        await localizedPage(
          t,
          progressDetailPage(
            measurement ? ProgressDest.waist : ProgressDest.weight,
            initial: d,
            range: ProgressRange.month,
          ),
          app: app,
        );
        final entry = find.byWidgetPredicate(
          (w) =>
              w is Pressable &&
              (w.semanticLabel?.endsWith(measurement ? ', 32 in' : ', 70 kg') ??
                  false),
        );
        await tap(t, entry.first);
        expect(find.byType(BodyEntryScreen), findsOneWidget);
        final editor = t.widget<BodyEntryScreen>(find.byType(BodyEntryScreen));
        expect(editor.date, d.weights.last.date);
        expect(editor.measure, measurement ? d.measures.first : isNull);
        Navigator.of(t.element(find.byType(BodyEntryScreen))).pop(false);
        await t.pumpAndSettle();
        expect(find.byType(BodyEntryScreen), findsNothing);
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('body_weight_reading'),
          ),
          isEmpty,
        );
      },
    );
  }
  testWidgets('All history returns to the same selected body page', (t) async {
    await localizedPage(
      t,
      progressDetailPage(
        ProgressDest.weight,
        initial: progress(true),
        range: ProgressRange.month,
      ),
    );
    final section = find.byWidgetPredicate(
      (w) => w is Section && w.title == 'Entries',
    );
    await reveal(t, section);
    t.widget<Section>(section).onAction!();
    await t.pumpAndSettle();
    expect(find.byType(BodyHistoryScreen), findsOneWidget);
    Navigator.of(t.element(find.byType(BodyHistoryScreen))).pop();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    expect(find.byType(BodyHistoryScreen), findsNothing);
    expect(find.text('Body'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}

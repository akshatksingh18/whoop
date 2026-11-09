// Real standalone/localized forms retain their copy,date and consent boundaries.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/off_lookup.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/ui2/localization.dart';
import 'package:whoop_companion/ui2/screens/barcode_food.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('shared-localization-fallback');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(430, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Widget host(Widget child, {String? language}) => MaterialApp(
    locale: language == null ? null : Locale(language),
    localizationsDelegates: language == null
        ? null
        : AppLocalizations.localizationsDelegates,
    supportedLocales: language == null
        ? const [Locale('en')]
        : AppLocalizations.supportedLocales,
    theme: buildTheme(Brightness.light),
    home: child,
  );
  test(
    'COV-66 fallback preserves English punctuation and every supplied locale object',
    () {
      final fallback = withEnglishFallback(null);
      expect(fallback.localeName, 'en');
      expect(fallback.logWorkoutDefaultTitle, 'Log a past workout');
      expect(fallback.logWorkoutSaving, 'Saving…');
      expect(fallback.logFoodConsentTitle, 'Look barcodes up online?');
      for (final locale in AppLocalizations.supportedLocales) {
        final supplied = lookupAppLocalizations(locale);
        expect(
          identical(withEnglishFallback(supplied), supplied),
          true,
          reason: 'Existing translations remain the exact authoritative object',
        );
      }
    },
  );

  testWidgets(
    'COV-66 standalone English workout keeps historical date and calendar Cancel',
    (t) async {
      phone(t);
      final start = DateTime(2021, 4, 6, 8);
      await t.pumpWidget(
        host(
          LogWorkout(
            start: start,
            end: start.add(const Duration(minutes: 30)),
            now: DateTime(2026, 8, 19, 21),
            spans: const [],
          ),
        ),
      );
      await flush(t);
      expect(AppLocalizations.of(t.element(find.byType(LogWorkout))), isNull);
      for (final label in [
        'Log a past workout',
        'When',
        'Started',
        'Ended',
        'Length',
        'Log it',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text('Date'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2021, 4, 6),
      );
      Navigator.of(t.element(find.byType(CalendarDatePicker))).pop();
      await flush(t);
      await t.tap(find.text('Date'));
      await t.pumpAndSettle();
      expect(
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2021, 4, 6),
      );
      Navigator.of(t.element(find.byType(CalendarDatePicker))).pop();
      await flush(t);
      expect(
        await t.runAsync(
          () async => (await LocalDb.instance).query('sessions'),
        ),
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'COV-66 changing locale retains the chosen historical workout window',
    (t) async {
      phone(t);
      var language = 'en';
      late StateSetter change;
      final start = DateTime(2021, 4, 6, 8);
      final page = LogWorkout(
        key: const ValueKey('retained historical editor'),
        start: start,
        end: start.add(const Duration(minutes: 30)),
        now: DateTime(2026, 8, 19, 21),
        spans: const [],
      );
      await t.pumpWidget(
        StatefulBuilder(
          builder: (_, setState) {
            change = setState;
            return host(page, language: language);
          },
        ),
      );
      await flush(t);
      await t.tap(find.text('Date'));
      await t.pumpAndSettle();
      Navigator.of(
        t.element(find.byType(CalendarDatePicker)),
      ).pop(DateTime(2021, 4, 7));
      await flush(t);
      change(() => language = 'fr');
      await flush(t);
      final strings = AppLocalizations.of(t.element(find.byType(LogWorkout)))!;
      expect(strings.localeName, 'fr');
      expect(find.text(strings.logWorkoutDefaultTitle), findsOneWidget);
      expect(find.text('Log a past workout'), findsNothing);
      expect(find.text(strings.logWorkoutStartedLabel), findsOneWidget);
      await t.tap(find.text(strings.logWorkoutDateLabel));
      await t.pumpAndSettle();
      expect(
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2021, 4, 7),
      );
      Navigator.of(t.element(find.byType(CalendarDatePicker))).pop();
      await flush(t);
      expect(
        await t.runAsync(
          () async => (await LocalDb.instance).query('sessions'),
        ),
        isEmpty,
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final language in <String?>[null, 'fr']) {
    testWidgets(
      'COV-66 ${language ?? 'standalone English'} consent decline stays authoritative',
      (t) async {
        phone(t);
        await setOffLookupAllowed(false);
        var finished = false;
        Object? result = 'not completed';
        await t.pumpWidget(
          host(
            Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () async {
                    result = await scanFoodProduct(c);
                    finished = true;
                  },
                  child: const Text('Authored scan entry'),
                ),
              ),
            ),
            language: language,
          ),
        );
        await flush(t);
        await t.tap(find.text('Authored scan entry'));
        await flush(t);
        final strings = withEnglishFallback(
          language == null ? null : lookupAppLocalizations(Locale(language)),
        );
        expect(find.text(strings.logFoodConsentTitle), findsOneWidget);
        expect(find.text(strings.logFoodConsentBody1), findsOneWidget);
        await t.ensureVisible(find.text(strings.logFoodNotNow));
        await t.tap(find.text(strings.logFoodNotNow));
        await flush(t);
        expect(finished, true);
        expect(result, isNull);
        expect(offLookupAllowed, false);
        final rows = await t.runAsync(
          () async => (await LocalDb.instance).query('food_def'),
        );
        expect(rows, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}

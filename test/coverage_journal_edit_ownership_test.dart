// Actual Journal editor, authored SQLite rows and delayed definition writes.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const day = '2021-04-06';

class _JournalRepo extends LocalRepositoryImpl {
  _JournalRepo() : super(getProfileMap: () => {});
  Completer<void>? definitionGate;
  int definitionWrites = 0;
  @override
  Future<List<JournalFieldSpec>> getJournalFields() async => [
    ...kJournalFields.where((s) => s.key == 'mood' || s.key == 'caffeine_mg'),
    ...await LocalDb.journalFieldDefs(),
  ];
  @override
  Future<void> postCustomJournalField(JournalFieldSpec spec) async {
    definitionWrites++;
    await definitionGate?.future;
    await super.postCustomJournalField(spec);
  }
}

Finder input(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
  matching: find.byType(TextField),
);
Future<void> flush(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<T> real<T>(WidgetTester t, Future<T> Function() action) async =>
    (await t.runAsync(action)) as T;
Future<void> tapText(WidgetTester t, String text) async {
  final f = find.text(text).first;
  await reveal(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Finder caffeine() => find.byWidgetPredicate(
  (w) => w is FieldStepper && w.spec.key == 'caffeine_mg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late _JournalRepo repo;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('journal-edit-ownership');
  });
  setUp(() async {
    await resetCoverageStore();
    repo = _JournalRepo();
    app = AppState.forTesting()..repo = repo;
    await LocalDb.putJournal(day, '["travel"]', 'Original authored note');
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const JournalCompose(date: day),
      app: app,
      push: true,
    );
    await flush(t);
  }

  for (final table in ['journal', 'journal_metric']) {
    testWidgets(
      'COV-63 real $table read failure retains historical rows and Retry restores the editor',
      (t) async {
        await real(
          t,
          () => LocalDb.putJournalMetrics(day, {
            'mood': const JournalMetricValue(2),
            'caffeine_mg': const JournalMetricValue(100, atMinuteOfDay: 0),
          }),
        );
        final db = await real(t, () => LocalDb.instance);
        final before = await real(t, () => db.query(table));
        await real(
          t,
          () => db.execute('ALTER TABLE $table RENAME TO authored_unavailable'),
        );
        try {
          await open(t);
          expect(find.text('This day could not load'), findsOneWidget);
          expect(find.text('Nothing was changed.'), findsOneWidget);
          expect(find.byType(MoodPicker), findsNothing);
        expect(find.widgetWithText(BigButton, 'Save'), findsNothing);
          expect(await real(t, () => db.query('authored_unavailable')), before);
        } finally {
          await real(
            t,
            () =>
                db.execute('ALTER TABLE authored_unavailable RENAME TO $table'),
          );
        }
        await tapText(t, 'Retry');
        await flush(t);
        expect(find.text('This day could not load'), findsNothing);
        expect(t.widget<MoodPicker>(find.byType(MoodPicker)).value, 2);
        expect(
          t.widget<TextField>(input('Anything else')).controller!.text,
          'Original authored note',
        );
        expect(t.widget<FieldStepper>(caffeine()).atMin, 0);
        expect(await real(t, () => db.query(table)), before);
      },
    );
  }

  for (final original in <int?>[null, 0, 1439]) {
    testWidgets(
      'COV-63 accepted last-dose edit from $original preserves the dose draft and historical date',
      (t) async {
        await real(
          t,
          () => LocalDb.putJournalMetrics(day, {
            'caffeine_mg': JournalMetricValue(100, atMinuteOfDay: original),
          }),
        );
        await open(t);
        await t.enterText(input('Anything else'), 'Unsaved time draft');
        final control = find.byWidgetPredicate(
          (w) =>
              w is Pressable && w.semanticLabel == 'When was the last Caffeine',
        );
        await reveal(t, control);
        await t.tap(control);
        await t.pumpAndSettle();
        final picker = t.widget<TimePickerDialog>(
          find.byType(TimePickerDialog),
        );
        if (original != null) {
          expect(
            picker.initialTime,
            TimeOfDay(hour: original ~/ 60, minute: original % 60),
          );
        }
        // Accept the actual picker. With a retained time this must preserve exact
        // midnight/last-minute values; a new time must stay a genuine local minute.
        await t.tap(find.text('OK'));
        await t.pumpAndSettle();
        final edited = t.widget<FieldStepper>(caffeine());
        expect(edited.value, 100);
        expect(edited.atMin, original ?? inInclusiveRange(0, 1439));
        expect(
          t.widget<TextField>(input('Anything else')).controller!.text,
          'Unsaved time draft',
        );
        final pending = await real(t, () => LocalDb.journalMetricsForDay(day));
        expect(pending['caffeine_mg']!.atMinuteOfDay, original);
        await invokeControl(
          t,
          t.widget<BigButton>(find.widgetWithText(BigButton, 'Save')).onTap,
        );
        expect(find.byType(JournalCompose), findsNothing);
        final saved = await real(t, () => LocalDb.journalMetricsForDay(day));
        expect(saved['caffeine_mg']!.value, 100);
        expect(saved['caffeine_mg']!.atMinuteOfDay, edited.atMin);
        expect(
          (await real(t, () => LocalDb.journalRows(date: day))).single['note'],
          'Unsaved time draft',
        );
        expect(
          (await real(
            t,
            () => LocalDb.journalRows(),
          )).every((r) => r['date'] == day),
          true,
        );
      },
    );
  }

  for (final rejected in [false, true]) {
    testWidgets(
      'COV-63 definition completion after editor closes refusal=$rejected never saves the abandoned day draft',
      (t) async {
        repo.definitionGate = Completer<void>();
        await open(t);
        await t.enterText(input('Anything else'), 'Abandoned authored draft');
        await tapText(t, 'Track something else');
        await t.enterText(
          input('What do you want to track?'),
          'Authored late definition',
        );
        await tapText(t, 'Start tracking it');
        expect(repo.definitionWrites, 1);
        expect(
          t
              .widget<Pressable>(
                find
                    .ancestor(
                      of: find.text('Track something else'),
                      matching: find.byType(Pressable),
                    )
                    .first,
              )
              .onTap,
          isNull,
        );
        // Closing the whole host is a real lifetime boundary; completion still
        // exercises the shared writer, not a direct widget callback after dispose.
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await t.runAsync(() async {
          if (rejected) {
            repo.definitionGate!.completeError(
              StateError('authored late refusal'),
            );
          } else {
            repo.definitionGate!.complete();
          }
          await Future<void>.delayed(const Duration(milliseconds: 80));
        });
        expect(t.takeException(), isNull);
        final defs = await real(t, LocalDb.journalFieldDefs);
        expect(
          defs.map((s) => s.key),
          rejected ? [] : ['custom_authored_late_definition'],
        );
        expect(
          (await real(t, () => LocalDb.journalRows(date: day))).single['note'],
          'Original authored note',
        );
        expect(await real(t, () => LocalDb.journalMetricsForDay(day)), isEmpty);
      },
    );
  }
}

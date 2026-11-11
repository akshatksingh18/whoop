// Real gestures -> editor -> shared conflict-safe writer -> SQLite -> reopening.
// Absence, entered zero and a positive dose remain three distinct states.
import 'package:flutter/widgets.dart' show SizedBox;
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

const day = '2021-04-06', other = '2021-04-01';
final spec = kJournalFields.singleWhere((v) => v.key == 'caffeine_mg');

class _Repo extends LocalRepositoryImpl {
  _Repo() : super(getProfileMap: () => {});
  @override
  Future<List<JournalFieldSpec>> getJournalFields() async => [spec];
}

Finder caffeine() =>
    find.byWidgetPredicate((w) => w is FieldStepper && w.spec.key == spec.key);
Finder step(String name) => find.descendant(
  of: caffeine(),
  matching: find.byWidgetPredicate(
    (w) => w is Pressable && w.semanticLabel == name,
  ),
);
Future<void> flush(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(t.takeException(), isNull);
}

Future<T> real<T>(WidgetTester t, Future<T> Function() f) async =>
    (await t.runAsync(f)) as T;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('journal-stepper-persistence');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final mode in ['missing', 'zero', 'positive', 'cap']) {
      testWidgets(
        'Journal $mode dose gestures save/reopen historical input at ${scale}x',
        (t) async {
          final initial = switch (mode) {
            'zero' => 0.0,
            'positive' => 2 * spec.step,
            'cap' => spec.max,
            _ => null,
          };
          final minute = mode == 'zero' ? 0 : 1439;
          await real(t, () async {
            await LocalDb.putJournal(
              day,
              '["travel"]',
              'Retained historical note',
            );
            if (initial != null) {
              await LocalDb.putJournalMetrics(day, {
                spec.key: JournalMetricValue(initial, atMinuteOfDay: minute),
              });
            }
            await LocalDb.putJournal(
              other,
              '["illness"]',
              'Unrelated banked note',
            );
            await LocalDb.putJournalMetrics(other, {
              'caffeine_mg': const JournalMetricValue(77, atMinuteOfDay: 600),
            });
          });
          final savedOther = await real(
            t,
            () => LocalDb.journalMetricsForDay(other),
          );
          final rowsOther = await real(
            t,
            () => LocalDb.journalRows(date: other),
          );
          final app = AppState.forTesting()..repo = _Repo();
          addTearDown(app.dispose);
          Future<void> open() async {
            // A popped Navigator retains its stack across pumpWidget updates.
            // Reopening means mounting a fresh editor,not reusing that stack.
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            await localizedPage(
              t,
              const JournalCompose(date: day),
              app: app,
              scale: scale,
              push: true,
            );
            await flush(t);
            expect(caffeine(), findsOneWidget);
          }

          double? value() => t.widget<FieldStepper>(caffeine()).value;
          Future<void> press(String name) async {
            final f = step(name);
            await reveal(t, f);
            await t.tap(f);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
          }

          await open();
          expect(value(), initial);
          if (mode == 'missing') {
            expect(t.widget<Pressable>(step('Decrease')).onTap, isNull);
            await press('Increase');
            expect(value(), spec.step);
            await press('Decrease');
            expect(value(), 0);
            await press('Decrease');
            expect(value(), isNull);
            await press('Increase');
            expect(value(), spec.step);
          } else if (mode == 'zero') {
            expect(t.widget<Pressable>(step('Decrease')).onTap, isNotNull);
            await press('Decrease');
            expect(value(), isNull);
          } else if (mode == 'positive') {
            await press('Decrease');
            expect(value(), spec.step);
            await press('Decrease');
            expect(value(), 0);
          } else {
            expect(t.widget<Pressable>(step('Increase')).onTap, isNull);
            await press('Decrease');
            expect(value(), spec.max - spec.step);
            await press('Increase');
            expect(value(), spec.max);
          }
          final wanted = value();
          // Gestures edit a draft;no metric or note is written until Save.
          final draft = await real(t, () => LocalDb.journalMetricsForDay(day));
          expect(draft[spec.key]?.value, initial);
          await invokeControl(
            t,
            t.widget<BigButton>(find.widgetWithText(BigButton, 'Save')).onTap,
          );
          expect(find.byType(JournalCompose), findsNothing);
          final stored = await real(t, () => LocalDb.journalMetricsForDay(day));
          expect(stored[spec.key]?.value, wanted);
          if (wanted != null) {
            expect(
              stored[spec.key]!.atMinuteOfDay,
              initial == null ? null : minute,
            );
          }
          expect(
            (await real(
              t,
              () => LocalDb.journalRows(date: day),
            )).single['note'],
            'Retained historical note',
          );
          expect(
            (await real(
              t,
              () => LocalDb.journalRows(date: day),
            )).single['tags_json'],
            '["travel"]',
          );
          expect(
            await real(t, () => LocalDb.journalMetricsForDay(other)),
            savedOther,
          );
          expect(
            await real(t, () => LocalDb.journalRows(date: other)),
            rowsOther,
          );
          await open();
          expect(value(), wanted);
          if (wanted != null) {
            expect(
              t.widget<FieldStepper>(caffeine()).atMin,
              initial == null ? null : minute,
            );
          }
        },
      );
    }
  }
}

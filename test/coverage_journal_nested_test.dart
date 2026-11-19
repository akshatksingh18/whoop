// Reachable Sleep -> rough-night -> Journal flows against synthetic storage.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/screens/custom_journal_field_sheet.dart';
import 'package:whoop_companion/ui2/screens/journal_compose.dart';
import 'package:whoop_companion/ui2/screens/rough_night.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

class _Repo extends LocalRepositoryImpl {
  _Repo() : super(getProfileMap: () => {});
  @override
  Future<List<JournalFieldSpec>> getJournalFields() async => [
    ...kJournalFields.where((s) => s.key == 'mood' || s.key == 'caffeine_mg'),
    ...await LocalDb.journalFieldDefs(),
  ];
}

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is WhoopTextField && w.label == label),
  matching: find.byType(TextField),
);
Future<void> until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 80 && !done(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
  expect(t.takeException(), isNull);
}

Future<void> press(WidgetTester t, String text) async {
  final f = find.text(text);
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late Database db;
  const oldDay = '2026-01-02';
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/journal',
    ).create(recursive: true)).absolute;
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    app = AppState.forTesting()..repo = _Repo();
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(900, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: child),
        ),
      ),
    );
    await until(
      t,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    );
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }

  testWidgets('opening an older night keeps its existing note and tags', (
    t,
  ) async {
    await t.runAsync(
      () => LocalDb.putJournal(oldDay, '["travel"]', 'Original old-night note'),
    );
    await open(t, const JournalCompose(date: oldDay));
    expect(
      t.widget<TextField>(field('Anything else')).controller!.text,
      'Original old-night note',
    );
    expect(
      t.widget<Pill>(find.widgetWithText(Pill, 'travel')).color,
      C.domMind,
    );
    await close(t);
  });

  testWidgets(
    'logging a tag for an older rough night preserves its earlier tags and note',
    (t) async {
      await t.runAsync(
        () =>
            LocalDb.putJournal(oldDay, '["travel"]', 'Original old-night note'),
      );
      var dismissed = false;
      await open(
        t,
        RoughNightCard(
          night: const RoughNight(
            day: oldDay,
            signs: 2,
            descriptor: 'A harder night',
            moved: ['resting heart rate', 'HRV'],
            knows: [],
          ),
          ask: 'on',
          onDismiss: () => dismissed = true,
        ),
      );
      await press(t, 'caffeine');
      await press(t, 'Log it for that night');
      await until(t, () => dismissed);
      final rows = await t.runAsync(() => LocalDb.journalRows());
      expect(rows!.single['note'], 'Original old-night note');
      expect(
        jsonDecode(rows.single['tags_json'] as String),
        unorderedEquals(['travel', 'caffeine']),
      );
      await close(t);
    },
  );

  testWidgets(
    'adding a custom field preserves the unsaved note, rating and tags',
    (t) async {
      bool? saved;
      await open(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              saved = await Navigator.of(c).push<bool>(
                MaterialPageRoute(
                  builder: (_) => JournalCompose(date: todayLabel()),
                ),
              );
            },
            child: const Text('Edit journal'),
          ),
        ),
      );
      await press(t, 'Edit journal');
      await until(t, () => field('Anything else').evaluate().isNotEmpty);
      await t.enterText(field('Anything else'), 'Keep this unsaved draft');
      t.widget<MoodPicker>(find.byType(MoodPicker)).onChanged(4);
      await press(t, 'travel');
      await press(t, 'Track something else');
      await t.enterText(
        field('What do you want to track?'),
        'Synthetic screen time',
      );
      await press(t, 'Minutes');
      await press(t, 'Start tracking it');
      await until(
        t,
        () => find
            .byWidgetPredicate((w) => w is FieldStepper && w.spec.custom)
            .evaluate()
            .isNotEmpty,
      );
      expect(
        t.widget<TextField>(field('Anything else')).controller!.text,
        'Keep this unsaved draft',
      );
      expect(t.widget<MoodPicker>(find.byType(MoodPicker)).value, 4);
      expect(
        t.widget<Pill>(find.widgetWithText(Pill, 'travel')).color,
        C.domMind,
      );
      final defs = await t.runAsync(LocalDb.journalFieldDefs);
      expect(defs!.single.kind, JournalFieldKind.duration);
      expect(defs.single.unit, 'min');
      final stepper = t.widget<FieldStepper>(
        find.byWidgetPredicate((w) => w is FieldStepper && w.spec.custom),
      );
      stepper.onChanged(30);
      await t.pump();
      await t.runAsync(() async {
        final dynamic action = t
            .widget<BigButton>(find.widgetWithText(BigButton, 'Save'))
            .onTap;
        await action();
      });
      await until(t, () => saved != null);
      expect(saved, isTrue);
      final stored = await t.runAsync(
        () => LocalDb.journalRows(date: todayLabel()),
      );
      expect(stored!.single['note'], 'Keep this unsaved draft');
      expect(jsonDecode(stored.single['tags_json'] as String), ['travel']);
      final values = await t.runAsync(
        () => LocalDb.journalMetricsForDay(todayLabel()),
      );
      expect(values!['mood']!.value, 4);
      expect(values[defs.single.key]!.value, 30);
      await close(t);
    },
  );

  test(
    'concurrent rough-night tag additions retain every answer and the current note',
    () async {
      await LocalDb.putJournal(oldDay, '["travel"]', 'Keep the current note');
      await Future.wait([
        for (var i = 0; i < 20; i++)
          app.repo!.mergeJournalTags(oldDay, ['synthetic_tag_$i']),
      ]);
      final row = (await LocalDb.journalRows(date: oldDay)).single;
      expect(row['note'], 'Keep the current note');
      expect(
        jsonDecode(row['tags_json'] as String),
        unorderedEquals([
          'travel',
          for (var i = 0; i < 20; i++) 'synthetic_tag_$i',
        ]),
      );
    },
  );

  test(
    'an exact selected-day read is independent of recent-list bounds',
    () async {
      await LocalDb.putJournal(oldDay, '["travel"]', 'Older note');
      await LocalDb.putJournal(todayLabel(), '["workout"]', 'Recent note');
      expect((await app.repo!.getJournal()).map((r) => r['date']), [
        todayLabel(),
      ]);
      expect((await app.repo!.getJournalDay(oldDay))!['note'], 'Older note');
      expect(await app.repo!.getJournalDay('2000-01-01'), isNull);
      expect((await LocalDb.journalRows(date: oldDay)).single['date'], oldDay);
    },
  );

  testWidgets(
    'an older-day conflict reloads its real note and tags and keeps the typed draft',
    (t) async {
      await t.runAsync(() async {
        await LocalDb.putJournal(oldDay, '["travel"]', 'Original old note');
        await LocalDb.putJournalMetrics(oldDay, {
          'mood': const JournalMetricValue(1),
        });
      });
      await open(t, const JournalCompose(date: oldDay));
      await t.enterText(field('Anything else'), 'My typed draft');
      t.widget<MoodPicker>(find.byType(MoodPicker)).onChanged(4);
      await t.pump();
      await t.runAsync(() async {
        await LocalDb.putJournal(oldDay, '["sick"]', 'Newer stored note');
        await LocalDb.putJournalMetrics(oldDay, {
          'mood': const JournalMetricValue(2),
        });
        final dynamic action = t
            .widget<BigButton>(find.widgetWithText(BigButton, 'Save'))
            .onTap;
        await action();
      });
      await until(
        t,
        () => find.textContaining('Changed elsewhere').evaluate().isNotEmpty,
      );
      expect(find.textContaining('Newer stored note'), findsOneWidget);
      expect(
        t.widget<TextField>(field('Anything else')).controller!.text,
        'My typed draft',
      );
      expect(t.widget<MoodPicker>(find.byType(MoodPicker)).value, 2);
      expect(
        t.widget<Pill>(find.widgetWithText(Pill, 'sick')).color,
        C.domMind,
      );
      await close(t);
    },
  );

  testWidgets(
    'a refused custom-field write keeps the day draft and allows a successful retry',
    (t) async {
      await t.runAsync(
        () => db.execute(
          "CREATE TEMP TRIGGER reject_journal_def BEFORE INSERT ON journal_field_def BEGIN SELECT RAISE(ABORT, 'synthetic refusal'); END",
        ),
      );
      try {
        await open(t, JournalCompose(date: todayLabel()));
        await t.enterText(field('Anything else'), 'Draft survives refusal');
        for (var attempt = 0; attempt < 2; attempt++) {
          await press(t, 'Track something else');
          await t.enterText(
            field('What do you want to track?'),
            'Synthetic retry field',
          );
          await press(t, 'Start tracking it');
          if (attempt == 0) {
            await until(
              t,
              () => find
                  .textContaining('Could not save it')
                  .evaluate()
                  .isNotEmpty,
            );
            expect(await t.runAsync(LocalDb.journalFieldDefs), isEmpty);
            await t.runAsync(
              () => db.execute('DROP TRIGGER reject_journal_def'),
            );
          } else {
            await until(
              t,
              () => find
                  .byWidgetPredicate((w) => w is FieldStepper && w.spec.custom)
                  .evaluate()
                  .isNotEmpty,
            );
          }
          expect(
            t.widget<TextField>(field('Anything else')).controller!.text,
            'Draft survives refusal',
          );
        }
        expect(
          (await t.runAsync(LocalDb.journalFieldDefs))!.single.key,
          'custom_synthetic_retry_field',
        );
        await close(t);
      } finally {
        await t.runAsync(
          () => db.execute('DROP TRIGGER IF EXISTS reject_journal_def'),
        );
      }
    },
  );

  testWidgets(
    'cancelling a last-dose time edit retains the original time and unsaved note',
    (t) async {
      await t.runAsync(
        () => LocalDb.putJournalMetrics(oldDay, {
          'caffeine_mg': const JournalMetricValue(100, atMinuteOfDay: 900),
        }),
      );
      await open(t, const JournalCompose(date: oldDay));
      await t.enterText(field('Anything else'), 'Keep note during time picker');
      await press(t, 'Last at 3:00 PM');
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await press(t, 'Cancel');
      expect(t.widget<FieldStepper>(find.byType(FieldStepper)).atMin, 900);
      expect(
        t.widget<TextField>(field('Anything else')).controller!.text,
        'Keep note during time picker',
      );
      expect(
        (await t.runAsync(
          () => LocalDb.journalMetricsForDay(oldDay),
        ))!['caffeine_mg']!.atMinuteOfDay,
        900,
      );
      await close(t);
    },
  );

  for (final shape in ['blank', 'punctuation', 'duplicate', 'unit']) {
    testWidgets('custom-field $shape validation keeps the sheet open', (
      t,
    ) async {
      JournalFieldSpec? result;
      await open(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              result = await showCustomJournalFieldSheet(
                c,
                existingKeys: {'custom_repeat'},
              );
            },
            child: const Text('Open field'),
          ),
        ),
      );
      await press(t, 'Open field');
      await t.enterText(field('What do you want to track?'), switch (shape) {
        'punctuation' => '???',
        'duplicate' => 'Repeat',
        'unit' => 'Synthetic dose',
        _ => '',
      });
      if (shape == 'unit') await press(t, 'An amount');
      await press(t, 'Start tracking it');
      expect(result, isNull);
      expect(
        find.text(switch (shape) {
          'punctuation' => 'Use at least one letter or number',
          'duplicate' => 'You already track something by that name',
          'unit' => 'Say what it is counted in (mg, ml, cups…)',
          _ => 'Give it a name',
        }),
        findsOneWidget,
      );
      expect(await t.runAsync(LocalDb.journalFieldDefs), isEmpty);
      await close(t);
    });
  }

  testWidgets(
    'changing custom field kind clears inappropriate unit and time choices',
    (t) async {
      JournalFieldSpec? result;
      await open(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              result = await showCustomJournalFieldSheet(c, existingKeys: {});
            },
            child: const Text('Open field'),
          ),
        ),
      );
      await press(t, 'Open field');
      await t.enterText(
        field('What do you want to track?'),
        'Synthetic rating',
      );
      await press(t, 'An amount');
      await t.enterText(field('Unit'), 'cups');
      await press(t, 'Ask when the last one was');
      await press(t, 'A 1–5 rating');
      await press(t, 'Start tracking it');
      expect(result!.kind, JournalFieldKind.rating);
      expect(result!.unit, '');
      expect(result!.hasTime, isFalse);
      expect(result!.max, 5);
      await close(t);
    },
  );
}

// Deep Lift navigation and durable edits over synthetic SQLite history.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/activity/lift_log_ui.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart'
    show OsTextField;
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is OsTextField && w.label == label),
  matching: find.byType(TextField),
);
Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);
Future<void> waitIo(WidgetTester t, bool Function() ready) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  expect(ready(), isTrue);
  expect(t.takeException(), isNull);
}

Future<void> ioFrame(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump(const Duration(milliseconds: 30));
  }
  await t.pumpAndSettle();
}

Widget frame(Widget child, {GlobalKey<NavigatorState>? nav}) => MaterialApp(
  navigatorKey: nav,
  theme: buildTheme(Brightness.light),
  home: child,
);
void phone(WidgetTester t) {
  t.view.physicalSize = const Size(390, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late LiftSplit split;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory(
      'build/coverage-expansion/lift',
    ).create(recursive: true);
    LocalDb.dbName = '${dir.absolute.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    db = await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    split = LiftSplit(
      id: 'synthetic-split',
      name: 'Synthetic A',
      exercises: [
        LiftSplitExercise(
          name: 'Synthetic press',
          loadMode: LiftLoadMode.total,
        ),
        LiftSplitExercise(name: 'Synthetic row', loadMode: LiftLoadMode.stack),
      ],
    );
    await LiftLogDb.saveSplits([split]);
  });
  tearDown(() async {
    await db.execute('DROP TRIGGER IF EXISTS synthetic_split_refusal');
    await db.execute('DROP TRIGGER IF EXISTS synthetic_set_refusal');
    await RestTimer.skip();
  });
  tearDownAll(LocalDb.close);

  for (final choice in [LiftChoice.empty, LiftChoice.trackOnly]) {
    testWidgets('setup restores ${choice.key} and changes to the saved split', (
      t,
    ) async {
      phone(t);
      await LiftChoice.remember(choice);
      LiftChoice? selected;
      await t.pumpWidget(
        frame(
          Scaffold(
            body: ListView(
              children: [LiftChoicePicker(onChanged: (x) => selected = x)],
            ),
          ),
        ),
      );
      await waitIo(t, () => selected != null);
      expect(selected!.key, choice.key);
      await t.tap(find.text('Synthetic A'));
      await t.pump();
      expect(selected, isA<LiftSplitChoice>());
      expect((selected as LiftSplitChoice).split.id, split.id);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'missing remembered split falls back to an unlogged empty workout',
    (t) async {
      phone(t);
      await LiftChoice.remember(
        LiftSplitChoice(LiftSplit(id: 'removed', name: 'Removed')),
      );
      LiftChoice? selected;
      await t.pumpWidget(
        frame(Scaffold(body: LiftChoicePicker(onChanged: (x) => selected = x))),
      );
      await waitIo(t, () => selected != null);
      expect(selected!.key, LiftChoice.empty.key);
      expect(await t.runAsync(() => LiftLogDb.forSession('no-start')), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final mode in LiftLoadMode.values) {
    testWidgets(
      'exercise editor preserves identity and ${mode.name} load meaning',
      (t) async {
        phone(t);
        LiftSplitExercise? result;
        final original = split.exercises.first;
        await t.pumpWidget(
          frame(
            Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () async =>
                      result = await editLiftExercise(c, existing: original),
                  child: const Text('Open exercise'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open exercise'));
        await t.pumpAndSettle();
        await t.tap(find.text(mode.title).last);
        await t.pump();
        expect(find.text(mode.guidance), findsOneWidget);
        await t.enterText(field('Name'), 'Edited synthetic');
        await t.enterText(
          field('Variation or setup (optional)'),
          '  neutral grip  ',
        );
        await t.ensureVisible(find.text('Save').last);
        await t.tap(find.text('Save').last);
        await t.pumpAndSettle();
        expect(result!.id, original.id);
        expect(result!.name, 'Edited synthetic');
        expect(result!.loadMode, mode);
        expect(result!.equipmentNote, 'neutral grip');
        expect(
          original.name,
          'Synthetic press',
          reason: 'editor returns a copy',
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'split exercises reorder, edit and remove durably without changing history',
    (t) async {
      phone(t);
      final previous = LiftWorkout(
        startedAt: DateTime(2026, 1, 1),
        sessionId: 'synthetic-finished',
      )..syncWith(split);
      previous.addSet(
        previous.exercises.first.id,
        reps: 8,
        load: 20,
        at: DateTime(2026, 1, 1, 10),
      );
      previous.finish(DateTime(2026, 1, 1, 11));
      await t.runAsync(() => LiftLogDb.save(previous));
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(frame(const LiftSplitsScreen(), nav: nav));
      await waitIo(t, () => find.text('Synthetic A').evaluate().isNotEmpty);
      await t.tap(find.text('Synthetic A'));
      await t.pumpAndSettle();
      await t.tap(action('Move Synthetic row up'));
      await ioFrame(t);
      expect(
        (await t.runAsync(LiftLogDb.splits))!.single.exercises.first.name,
        'Synthetic row',
      );
      await t.tap(find.text('Synthetic row'));
      await t.pumpAndSettle();
      await t.enterText(field('Name'), 'Edited row');
      await t.enterText(field('Variation or setup (optional)'), 'Machine A');
      await t.ensureVisible(find.text('Save').last);
      await t.tap(find.text('Save').last);
      await ioFrame(t);
      final saved = (await t.runAsync(LiftLogDb.splits))!.single;
      expect(saved.exercises.first.equipmentNote, 'Machine A');
      expect(saved.exercises.first.loadMode, LiftLoadMode.stack);
      await t.tap(action('Remove Synthetic press'));
      await ioFrame(t);
      expect(
        (await t.runAsync(LiftLogDb.splits))!.single.exercises.single.name,
        'Edited row',
      );
      nav.currentState!.pop();
      await ioFrame(t);
      expect(find.text('1 exercises'), findsOneWidget);
      final history = await t.runAsync(
        () => LiftLogDb.forSession('synthetic-finished'),
      );
      expect(history!.splitName, 'Synthetic A');
      expect(history.exercises.first.name, 'Synthetic press');
      expect(history.setCount, 1);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('new, reordered and deleted splits retain another saved split', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(frame(const LiftSplitsScreen()));
    await waitIo(t, () => find.text('Synthetic A').evaluate().isNotEmpty);
    await t.tap(find.text('New split'));
    await t.pumpAndSettle();
    await t.enterText(field('Name'), 'Synthetic B');
    await t.tap(find.text('Save').last);
    await ioFrame(t);
    expect((await t.runAsync(LiftLogDb.splits))!.map((s) => s.name), [
      'Synthetic A',
      'Synthetic B',
    ]);
    await t.tap(action('Move Synthetic B up'));
    await ioFrame(t);
    expect((await t.runAsync(LiftLogDb.splits))!.first.name, 'Synthetic B');
    await t.tap(action('Delete Synthetic B'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete').last);
    await ioFrame(t);
    expect((await t.runAsync(LiftLogDb.splits))!.single.id, split.id);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'refused split rename retains its draft then retries to durable storage',
    (t) async {
      phone(t);
      await t.pumpWidget(frame(const LiftSplitsScreen()));
      await waitIo(t, () => find.text('Synthetic A').evaluate().isNotEmpty);
      await t.tap(find.text('Synthetic A'));
      await t.pumpAndSettle();
      await t.runAsync(
        () => db.execute(
          "CREATE TRIGGER synthetic_split_refusal BEFORE INSERT ON baselines BEGIN SELECT RAISE(ABORT,'synthetic refusal'); END",
        ),
      );
      await t.tap(action('Rename split'));
      await t.pumpAndSettle();
      await t.enterText(field('Name'), 'Retained draft');
      await t.tap(find.text('Save').last);
      await ioFrame(t);
      expect(find.text('Changes not saved'), findsOneWidget);
      expect((await t.runAsync(LiftLogDb.splits))!.single.name, 'Synthetic A');
      await t.runAsync(
        () => db.execute('DROP TRIGGER synthetic_split_refusal'),
      );
      await t.tap(find.text('Retry'));
      await ioFrame(t);
      expect(find.text('Changes not saved'), findsNothing);
      expect(
        (await t.runAsync(LiftLogDb.splits))!.single.name,
        'Retained draft',
      );
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final kind in ['edit exercise', 'add exercise', 'rename']) {
    testWidgets('late $kind result cannot write into a disposed split page', (
      t,
    ) async {
      phone(t);
      final nav = GlobalKey<NavigatorState>();
      await t.pumpWidget(frame(const LiftSplitsScreen(), nav: nav));
      await waitIo(t, () => find.text('Synthetic A').evaluate().isNotEmpty);
      await t.tap(find.text('Synthetic A'));
      await t.pumpAndSettle();
      final owner = ModalRoute.of(t.element(find.text('Rename')))!;
      if (kind == 'edit exercise') {
        await t.tap(find.text('Synthetic press'));
      } else if (kind == 'add exercise') {
        await t.tap(find.text('Add exercise'));
      } else {
        await t.tap(action('Rename split'));
      }
      await t.pumpAndSettle();
      await t.enterText(field('Name'), 'Late result');
      nav.currentState!.removeRoute(owner);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save').last);
      await t.tap(find.text('Save').last);
      await ioFrame(t);
      expect(t.takeException(), isNull);
      expect(
        (await t.runAsync(LiftLogDb.splits))!.single.exercises.first.name,
        'Synthetic press',
      );
      final saved = (await t.runAsync(LiftLogDb.splits))!.single;
      expect(saved.name, 'Synthetic A');
      expect(saved.exercises, hasLength(2));
      await t.pumpWidget(const SizedBox());
    });
  }

  Future<LiftWorkout> live(
    WidgetTester t, {
    bool withHistory = false,
    bool finished = false,
  }) async {
    phone(t);
    final w = (await t.runAsync(() async {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      if (withHistory) {
        for (var i = 1; i <= 3; i++) {
          final past = LiftWorkout(
            startedAt: start.subtract(Duration(days: i)),
            sessionId: 'past-$i',
          );
          final e = past.addExercise(
            name: 'Synthetic press',
            loadMode: LiftLoadMode.total,
          );
          past.addSet(
            e,
            reps: 8,
            load: 25.0 - i,
            at: past.startedAt.add(const Duration(minutes: 1)),
          );
          past.finish(past.startedAt.add(const Duration(minutes: 2)));
          await LiftLogDb.save(past);
        }
      }
      await beginLiftLog(
        LiftSplitChoice(split),
        sessionId: 'live',
        startedAt: start,
      );
      final current = (await LiftLogDb.forSession('live'))!;
      current.addSet(
        current.exercises.first.id,
        reps: 8,
        load: 20,
        at: start.add(const Duration(minutes: 1)),
      );
      if (finished) {
        current.finish(start.add(const Duration(minutes: 4)));
        await LocalDb.putSession({
          'id': 'live',
          'start_ts': start.millisecondsSinceEpoch ~/ 1000,
          'end_ts': current.endedAt!.millisecondsSinceEpoch ~/ 1000,
          'status': 'done',
          'type': 'lift',
          'source': 'manual',
          'created_at': start.millisecondsSinceEpoch,
        });
      }
      await LiftLogDb.save(current);
      return current;
    }))!;
    await t.pumpWidget(
      frame(
        Scaffold(
          body: ListView(
            children: [
              finished
                  ? const LiftSummaryCard(sessionId: 'live')
                  : const LiftLivePanel(sessionId: 'live'),
            ],
          ),
        ),
      ),
    );
    await waitIo(
      t,
      () => find.text('S1 20 lb total × 8').evaluate().isNotEmpty,
    );
    return w;
  }

  Future<void> finishCase(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await ioFrame(t);
  }

  testWidgets(
    'live set editor rejects bad input, saves a correction and deletes only that set',
    (t) async {
      await live(t);
      await t.tap(action('Set 1: 20 lb total × 8. Edit'));
      await t.pumpAndSettle();
      await t.enterText(field('Reps').last, 'bad');
      await t.tap(find.text('Save').last);
      await ioFrame(t);
      expect(find.text('Enter the weight and the reps.'), findsOneWidget);
      expect(
        (await t.runAsync(() => LiftLogDb.forSession('live')))!.setCount,
        1,
      );
      await t.tap(action('Set 1: 20 lb total × 8. Edit'));
      await t.pumpAndSettle();
      await t.enterText(field('Reps').last, '10');
      await t.enterText(field('lb total').last, '22,5');
      await t.tap(find.text('Save').last);
      await ioFrame(t);
      final saved = (await t.runAsync(() => LiftLogDb.forSession('live')))!;
      expect(saved.exercises.first.sets.single.reps, 10);
      expect(saved.exercises.first.sets.single.load, 22.5);
      await t.tap(action('Set 1: 22.5 lb total × 10. Edit'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete set'));
      await ioFrame(t);
      expect(
        (await t.runAsync(() => LiftLogDb.forSession('live')))!.setCount,
        0,
      );
      await finishCase(t);
    },
  );
  testWidgets(
    'exercise progress compares real matching past sessions without writing a set',
    (t) async {
      await live(t, withHistory: true);
      await t.tap(action('Progress for Synthetic press'));
      await t.pumpAndSettle();
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Heaviest at each rep count'), findsOneWidget);
      expect(find.text('The last point is today so far.'), findsOneWidget);
      expect(find.textContaining('1 sets · best'), findsNWidgets(3));
      expect(
        (await t.runAsync(() => LiftLogDb.forSession('live')))!.setCount,
        1,
      );
      await finishCase(t);
    },
  );
  testWidgets(
    'a new variation after a set creates a separate exercise and preserves the original',
    (t) async {
      await live(t);
      await t.tap(action('New variation of Synthetic press'));
      await t.pumpAndSettle();
      await t.enterText(field('Variation'), 'Synthetic close grip');
      await t.tap(find.text('Use it'));
      await ioFrame(t);
      final saved = (await t.runAsync(() => LiftLogDb.forSession('live')))!;
      final entries = saved.exercises
          .where((e) => e.name == 'Synthetic press')
          .toList();
      expect(entries, hasLength(2));
      expect(entries.first.equipmentNote, '');
      expect(entries.first.sets, hasLength(1));
      expect(entries.last.equipmentNote, 'Synthetic close grip');
      expect(entries.last.sets, isEmpty);
      await finishCase(t);
    },
  );
  for (final both in [false, true]) {
    testWidgets(
      'remove exercise from ${both ? 'today and split' : 'today only'} honors the chosen scope',
      (t) async {
        await live(t);
        await t.tap(action('Remove Synthetic press'));
        await t.pumpAndSettle();
        await t.tap(
          find.text(
            both ? 'Remove from today and Synthetic A' : 'Remove from today',
          ),
        );
        await ioFrame(t);
        final saved = (await t.runAsync(() => LiftLogDb.forSession('live')))!;
        expect(saved.exercises.map((e) => e.name), ['Synthetic row']);
        final names = (await t.runAsync(
          LiftLogDb.splits,
        ))!.single.exercises.map((e) => e.name);
        expect(names.contains('Synthetic press'), !both);
        await finishCase(t);
      },
    );
  }
  for (final sec in RestTimer.choices) {
    testWidgets(
      'rest timer choice $sec is saved without changing workout timing or sets',
      (t) async {
        final before = await live(t);
        await t.tap(action('Rest timer'));
        await ioFrame(t);
        await t.tap(action(sec == 0 ? 'Off' : '$sec seconds'));
        await ioFrame(t);
        expect(await t.runAsync(RestTimer.defaultSec), sec);
        final saved = (await t.runAsync(() => LiftLogDb.forSession('live')))!;
        expect(saved.toJson(), before.toJson());
        await finishCase(t);
      },
    );
  }
  testWidgets(
    'finished set correction retains its draft on refusal and retries durably',
    (t) async {
      final before = await live(t, finished: true);
      await t.tap(action('Set 1: 20 lb total × 8. Fix'));
      await t.pumpAndSettle();
      await t.enterText(field('Reps'), '11');
      await t.runAsync(
        () => db.execute(
          "CREATE TEMP TRIGGER synthetic_set_refusal BEFORE INSERT ON lift_log BEGIN SELECT RAISE(ABORT,'synthetic set refusal'); END",
        ),
      );
      await t.tap(find.text('Save').last);
      await ioFrame(t);
      expect(find.textContaining('not saved'), findsWidgets);
      expect(
        (await t.runAsync(() => LiftLogDb.forSession('live')))!.setCount,
        1,
      );
      expect(
        (await t.runAsync(
          () => LiftLogDb.forSession('live'),
        ))!.exercises.first.sets.single.reps,
        8,
      );
      await t.runAsync(() => db.execute('DROP TRIGGER synthetic_set_refusal'));
      await t.tap(find.text('Save').last);
      await ioFrame(t);
      final saved = (await t.runAsync(() => LiftLogDb.forSession('live')))!;
      expect(saved.exercises.first.sets.single.reps, 11);
      expect(
        saved.startedAt.millisecondsSinceEpoch,
        before.startedAt.millisecondsSinceEpoch,
      );
      expect(
        saved.endedAt!.millisecondsSinceEpoch,
        before.endedAt!.millisecondsSinceEpoch,
      );
      await finishCase(t);
    },
  );
  testWidgets(
    'deleting the last finished set asks first and removes only its empty lift log',
    (t) async {
      await live(t, finished: true);
      await t.tap(action('Set 1: 20 lb total × 8. Fix'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete set'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      expect(
        (await t.runAsync(() => LiftLogDb.forSession('live')))!.setCount,
        1,
      );
      await t.tap(find.text('Delete set'));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete').last);
      await ioFrame(t);
      expect(await t.runAsync(() => LiftLogDb.forSession('live')), isNull);
      final session = (await t.runAsync(
        () => db.query('sessions', where: 'id = ?', whereArgs: ['live']),
      ))!.single;
      expect(session['status'], 'done');
      expect(session['end_ts'], isNotNull);
      expect(find.text('S1 20 lb total × 8'), findsNothing);
      await finishCase(t);
    },
  );
}

// Real retained Lift inputs and authored history. No OS timer/delivery claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/notify/notification_service.dart';
import 'package:whoop_companion/ui2/activity/lift_log_ui.dart';
import 'coverage_deep_lift_test.dart' show field, action, ioFrame;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('lift-retained-inputs');
  });
  setUp(() async {
    await resetCoverageStore();
    NotificationService.instance.debugRequestPermission = () async => false;
    NotificationService.instance.debugProbePermission = () async => false;
    NotificationService.instance.debugCancel = (_) async {};
    NotificationService.instance.invalidatePermissionCache();
    await RestTimer.setDefault(0);
  });
  tearDown(() async {
    await RestTimer.skip();
    NotificationService.instance.debugRequestPermission = null;
    NotificationService.instance.debugProbePermission = null;
    NotificationService.instance.debugCancel = null;
    NotificationService.instance.invalidatePermissionCache();
  });
  tearDownAll(LocalDb.close);
  Future<LiftWorkout> previous({
    LiftLoadMode mode = LiftLoadMode.total,
    double load = 20,
    int reps = 8,
    String variation = 'Authored bar',
  }) async {
    final w = LiftWorkout(
      startedAt: DateTime(2021, 4, 5, 10),
      sessionId: 'authored-past',
    );
    final e = w.addExercise(
      name: 'Synthetic press',
      loadMode: mode,
      equipmentNote: variation,
    );
    w.addSet(e, reps: reps, load: load, at: DateTime(2021, 4, 5, 10, 5));
    w.finish(DateTime(2021, 4, 5, 10, 30));
    await LiftLogDb.save(w);
    return w;
  }

  Future<void> start({List<LiftSplitExercise> exercises = const []}) =>
      beginLiftLog(
        LiftSplitChoice(
          LiftSplit(name: 'Authored current', exercises: exercises),
        ),
        sessionId: 'authored-current',
        startedAt: DateTime.now(),
      );
  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const Scaffold(
        body: SingleChildScrollView(
          child: LiftLivePanel(sessionId: 'authored-current'),
        ),
      ),
    );
    await ioFrame(t);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    await reveal(t, f);
    await t.tap(f);
    await ioFrame(t);
  }

  Future<LiftWorkout> saved(WidgetTester t) async =>
      (await t.runAsync(() => LiftLogDb.forSession('authored-current')))!;
  for (final live in [false, true]) {
    testWidgets(
      'COV-48 actual Lift ${live ? 'live' : 'setup'} split door saves and returns without inventing sets',
      (t) async {
        await LiftLogDb.saveSplits([
          LiftSplit(id: 'authored-kept', name: 'Authored retained'),
        ]);
        final choices = <LiftChoice>[];
        if (live) {
          await start(
            exercises: [
              LiftSplitExercise(
                name: 'Synthetic press',
                loadMode: LiftLoadMode.total,
              ),
            ],
          );
          final w = (await LiftLogDb.forSession('authored-current'))!;
          w.addSet(
            w.exercises.single.id,
            reps: 8,
            load: 20,
            at: DateTime.now(),
          );
          await LiftLogDb.save(w);
          await open(t);
        } else {
          await localizedPage(
            t,
            Scaffold(
              body: SingleChildScrollView(
                child: LiftChoicePicker(onChanged: choices.add),
              ),
            ),
          );
          await ioFrame(t);
        }
        await tap(t, action('Splits'));
        expect(find.byType(LiftSplitsScreen), findsOneWidget);
        expect(find.text('Authored retained'), findsOneWidget);
        await tap(t, find.text('New split'));
        await t.enterText(field('Name'), 'Authored added');
        await tap(t, find.text('Save').last);
        final splits = (await t.runAsync(LiftLogDb.splits))!;
        expect(splits.map((s) => s.name), [
          'Authored retained',
          'Authored added',
        ]);
        expect(splits.first.id, 'authored-kept');
        await tap(t, action('Back'));
        expect(find.byType(LiftSplitsScreen), findsNothing);
        if (live) {
          final w = await saved(t);
          expect(w.setCount, 1);
          expect(w.exercises.single.name, 'Synthetic press');
          expect(w.exercises.single.sets.single.load, 20);
          expect(w.exercises.single.sets.single.reps, 8);
        } else {
          expect(find.text('Authored added'), findsOneWidget);
          await tap(t, action('Authored added'));
          expect(
            choices.last,
            isA<LiftSplitChoice>().having(
              (c) => c.split.name,
              'explicit choice',
              'Authored added',
            ),
          );
          expect(
            await t.runAsync(() => LiftLogDb.forSession('authored-current')),
            isNull,
          );
        }
      },
    );
  }

  for (final comparable in [true, false]) {
    testWidgets(
      'COV-48 real Lift set retains ${comparable ? 'equal' : 'incomparable'} evidence after panel reopen',
      (t) async {
        await previous(reps: comparable ? 8 : 20);
        await start(
          exercises: [
            LiftSplitExercise(
              name: 'Synthetic press',
              loadMode: LiftLoadMode.total,
              equipmentNote: 'Authored bar',
            ),
          ],
        );
        await open(t);
        final text = comparable
            ? 'Matching last time so far'
            : 'Not comparable with last time: different weight and reps';
        expect(
          find.text(text),
          findsNothing,
          reason: 'A prefilled draft is not a performed set',
        );
        await tap(t, find.text('Synthetic press'));
        await t.enterText(field('lb total'), comparable ? '20' : '30');
        await t.enterText(field('Reps'), comparable ? '8' : '15');
        await tap(t, find.text('Log set'));
        expect(find.text(text), findsOneWidget);
        expect(
          find.byIcon(comparable ? LucideIcons.equal : LucideIcons.minus),
          findsOneWidget,
        );
        var w = await saved(t);
        expect(w.setCount, 1);
        expect(w.exercises.single.sets.single.load, comparable ? 20 : 30);
        expect(w.exercises.single.sets.single.reps, comparable ? 8 : 15);
        await t.pumpWidget(const SizedBox());
        await open(t);
        expect(find.text(text), findsOneWidget);
        w = await saved(t);
        expect(w.setCount, 1);
        final prior = (await t.runAsync(
          () => LiftLogDb.forSession('authored-past'),
        ))!;
        expect(prior.exercises.single.sets.single.load, 20);
        expect(prior.exercises.single.sets.single.reps, comparable ? 8 : 20);
        expect(prior.setCount, 1);
      },
    );
  }

  testWidgets(
    'search reuses a prior exercise then creates a new explicit exercise without logging sets',
    (t) async {
      await previous();
      await start();
      await open(t);
      await t.enterText(field('Find or add an exercise'), 'Synthetic press');
      await t.pumpAndSettle();
      expect(find.textContaining('logged before'), findsOneWidget);
      await tap(t, action('Synthetic press'));
      var w = await saved(t);
      expect(w.exercises.single.equipmentNote, 'Authored bar');
      expect(w.exercises.single.loadMode, LiftLoadMode.total);
      expect(w.setCount, 0);
      await t.enterText(field('Find or add an exercise'), 'Synthetic new');
      await t.pumpAndSettle();
      await tap(t, action('Add "Synthetic new"'));
      expect(
        t.widget<TextField>(field('Name')).controller!.text,
        'Synthetic new',
      );
      await tap(t, action(LiftLoadMode.total.title));
      await tap(t, find.text('Save').last);
      w = await saved(t);
      expect(w.exercises.map((e) => e.name), [
        'Synthetic press',
        'Synthetic new',
      ]);
      expect(w.setCount, 0);
      expect(
        t.widget<TextField>(field('Find or add an exercise')).controller!.text,
        '',
      );
    },
  );
  testWidgets(
    'Repeat uses the previous first bodyweight set as a draft and invalid reps never write',
    (t) async {
      await previous(mode: LiftLoadMode.addedWeight, load: 0, variation: '');
      await start(
        exercises: [
          LiftSplitExercise(
            name: 'Synthetic press',
            loadMode: LiftLoadMode.addedWeight,
          ),
        ],
      );
      await open(t);
      await tap(t, find.text('Synthetic press'));
      await tap(t, action('Repeat last set'));
      expect(
        t
            .widget<TextField>(field('lb added · blank for bodyweight'))
            .controller!
            .text,
        '',
      );
      expect(t.widget<TextField>(field('Reps')).controller!.text, '8');
      expect((await saved(t)).setCount, 0);
      await t.enterText(field('Reps'), 'bad');
      await tap(t, find.text('Log set'));
      expect(
        find.text('Enter the reps (leave the weight blank for bodyweight).'),
        findsOneWidget,
      );
      expect((await saved(t)).setCount, 0);
      await t.enterText(field('Reps'), '9');
      await tap(t, find.text('Log set'));
      expect((await saved(t)).exercises.single.sets.single.reps, 9);
      expect((await saved(t)).exercises.single.sets.single.load, 0);
    },
  );
  testWidgets(
    'unlogged variation chips change the existing entry and reordering persists',
    (t) async {
      await previous(variation: 'Alternate setup');
      await start(
        exercises: [
          LiftSplitExercise(
            name: 'Synthetic press',
            loadMode: LiftLoadMode.total,
            equipmentNote: 'Current setup',
          ),
          LiftSplitExercise(
            name: 'Synthetic row',
            loadMode: LiftLoadMode.stack,
          ),
        ],
      );
      final before = (await LiftLogDb.forSession(
        'authored-current',
      ))!.exercises.first.id;
      await open(t);
      await tap(t, find.text('Synthetic press'));
      await tap(t, action('Variation Alternate setup'));
      final w = await saved(t);
      expect(w.exercises.first.id, before);
      expect(w.exercises.first.equipmentNote, 'Alternate setup');
      expect(w.setCount, 0);
      await tap(t, action('Move Synthetic row up'));
      expect((await saved(t)).exercises.first.name, 'Synthetic row');
    },
  );
  testWidgets('finished summary retains its setup and actual new-best record', (
    t,
  ) async {
    await previous();
    final current = LiftWorkout(
      startedAt: DateTime(2021, 4, 6, 10),
      sessionId: 'authored-current',
    );
    final e = current.addExercise(
      name: 'Synthetic press',
      loadMode: LiftLoadMode.total,
      equipmentNote: 'Authored bar',
    );
    current.addSet(e, reps: 8, load: 30, at: DateTime(2021, 4, 6, 10, 5));
    current.finish(DateTime(2021, 4, 6, 10, 30));
    await LiftLogDb.save(current);
    await localizedPage(
      t,
      const Scaffold(
        body: SingleChildScrollView(
          child: LiftSummaryCard(sessionId: 'authored-current'),
        ),
      ),
    );
    await ioFrame(t);
    final text = (await readPage(t)).join(' ');
    expect(text, contains('Synthetic press · Authored bar'));
    expect(text, contains('NEW BESTS'));
    expect(text, contains('30'));
    expect((await saved(t)).setCount, 1);
  });
}

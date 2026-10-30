// Existing explicit file import: authored ended days, real SQLite and modal
// decisions. No system picker, notification schedule or external app is opened.
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'coverage_data_actions_test.dart' show Picker;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late FilePicker previous;
  late Picker picker;
  late File file;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('pushup-import-controls');
    FilePicker.platform = Picker();
    file = File(
      '${Directory('build/coverage-remainder/cov44-pushup-import-controls').absolute.path}/authored-pushups.json',
    );
  });
  PushupSession session(String day, int sets) {
    final start = DateTime.parse('${day}T08:00:00');
    return PushupSession(
      id: 'authored-$day',
      day: day,
      started: start,
      ended: start.add(const Duration(hours: 1)),
      interval: 15,
      goal: 12,
      state: PushupState.ended,
      events: [
        for (var i = 0; i < sets; i++)
          PushupEvent(
            id: '$day-set-$i',
            at: start.add(Duration(minutes: i + 1)),
            kind: PushupEventKind.done,
            source: 'authored fixture',
          ),
      ],
    );
  }

  setUp(() async {
    await resetCoverageStore();
    await PushupDb.setInterval(45);
    await PushupDb.setGoal(5);
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        'settings': {'interval': 20, 'goal': 8},
        'sessions': [
          session('2021-04-06', 2).toJson(),
          session('2021-04-07', 3).toJson(),
        ],
      }),
    );
    expect(
      (await planPushupImport(await file.readAsString())).add,
      hasLength(2),
    );
    app = AppState.forTesting();
    previous = FilePicker.platform;
    picker = Picker()..file = file;
    FilePicker.platform = picker;
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_pushup_import_refusal',
    );
    app.dispose();
    FilePicker.platform = previous;
  });
  tearDownAll(LocalDb.close);
  Future<void> tick(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
  }

  Future<void> choose(WidgetTester t, String text) async {
    await t.tap(find.text(text).last);
    await tick(t);
  }

  Future<void> visible(WidgetTester t, Finder f) async {
    for (var i = 0; i < 30 && f.evaluate().isEmpty; i++) {
      await tick(t);
    }
    expect(
      f,
      findsOneWidget,
      reason: t
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .join('\n'),
    );
    // A sheet can enter the tree during the last pump's microtasks. Complete
    // its entrance before sending a gesture; the busy underlay cannot settle.
    await t.pump(const Duration(milliseconds: 600));
  }

  Future<void> finished(WidgetTester t) async {
    for (
      var i = 0;
      i < 30 &&
          find.text('Working. Keep this screen open.').evaluate().isNotEmpty;
      i++
    ) {
      await tick(t);
    }
    expect(find.text('Working. Keep this screen open.'), findsNothing);
    await t.pumpAndSettle();
  }

  Future<void> begin(WidgetTester t) async {
    final row = find.byWidgetPredicate(
      (w) => w is SetRow && w.title == 'Import Pushups from AkshatOS',
    );
    await reveal(t, row);
    await t.tap(row);
    await visible(t, find.textContaining('Pushups days?'));
  }

  Future<List<Map<String, Object?>>> rows(WidgetTester t) async =>
      (await t.runAsync(
        () async =>
            (await LocalDb.instance).query('pushup_session', orderBy: 'id'),
      ))!;
  Future<void> settings(WidgetTester t, bool imported) async {
    expect(await t.runAsync(PushupDb.interval), imported ? 20 : 45);
    expect(await t.runAsync(PushupDb.goal), imported ? 8 : 5);
    expect(await t.runAsync(PushupDb.active), isNull);
  }

  testWidgets(
    'cancelled Pushups import writes neither ended days nor settings',
    (t) async {
      await localizedPage(t, const DataScreen(), app: app);
      await tick(t);
      await begin(t);
      expect(find.text('Import 2 Pushups days?'), findsOneWidget);
      await choose(t, 'Cancel');
      expect(await rows(t), isEmpty);
      await settings(t, false);
      expect(find.text('That did not work'), findsNothing);
    },
  );
  for (final conflict in [false, true]) {
    for (final useSettings in [false, true]) {
      for (final refusal in [false, true]) {
        testWidgets(
          'Pushups import conflict=$conflict settings=$useSettings refusal=$refusal preserves the reviewed history',
          (t) async {
            final db = await LocalDb.instance;
            if (conflict) await PushupDb.save(session('2021-04-06', 1));
            final original = await db.query('pushup_session', orderBy: 'id');
            if (refusal) {
              await db.execute(
                "CREATE TRIGGER authored_pushup_import_refusal BEFORE INSERT ON pushup_session WHEN NEW.day='${conflict ? '2021-04-07' : '2021-04-06'}' BEGIN SELECT RAISE(ABORT,'authored Pushups refusal'); END",
              );
            }
            await localizedPage(t, const DataScreen(), app: app);
            await tick(t);
            Future<void> confirm() async {
              await begin(t);
              expect(
                find.text('Import ${conflict ? 1 : 2} Pushups days?'),
                findsOneWidget,
              );
              if (conflict) {
                expect(
                  find.textContaining('1 differ and stay as they are'),
                  findsOneWidget,
                );
              }
              expect(await rows(t), original);
              await choose(t, 'Import');
              await visible(t, find.text('Use its settings too?'));
              expect(find.text('Use its settings too?'), findsOneWidget);
              expect(await rows(t), original);
              await choose(t, useSettings ? 'Use them' : 'Keep mine');
              await finished(t);
            }

            await confirm();
            if (refusal) {
              expect(find.text('That did not work'), findsOneWidget);
              expect(await rows(t), original);
              await settings(t, false);
              await t.runAsync(
                () => db.execute('DROP TRIGGER authored_pushup_import_refusal'),
              );
              await confirm();
            }
            final saved = (await t.runAsync(PushupDb.all))!;
            expect(saved, hasLength(2));
            expect(
              saved.singleWhere((s) => s.day == '2021-04-06').count,
              conflict ? 1 : 2,
            );
            expect(saved.singleWhere((s) => s.day == '2021-04-07').count, 3);
            expect(
              saved.every((s) => s.goal == 12 && s.state == PushupState.ended),
              true,
            );
            if (conflict) {
              expect(
                (await rows(t)).singleWhere((r) => r['day'] == '2021-04-06'),
                original.single,
              );
            }
            await settings(t, useSettings);
            expect(
              find.textContaining('${conflict ? 1 : 2} Pushups days imported.'),
              findsOneWidget,
            );
          },
        );
      }
    }
  }
}

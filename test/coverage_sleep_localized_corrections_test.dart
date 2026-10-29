// Correction ownership and shipped copy; restaging is substituted, recording guards use SQLite.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/screens/naps.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

const day = '2021-04-06';
final onset = DateTime(2021, 4, 5, 23).millisecondsSinceEpoch ~/ 1000;

class Reader extends LocalRepositoryImpl {
  Reader() : super(getProfileMap: () => {});
  Map<String, dynamic> night = {
    'duration_min': 420,
    'in_bed_min': 480,
    'onset_ts': onset,
    'wake_ts': onset + 28800,
    'sleep_source': 'auto_fallback',
  };
  @override
  Future<Map<String, dynamic>> getToday() async => {};
  @override
  Future<List<String>> availableDays() async => [day];
  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) async => {...night};
  @override
  Future<Map<String, dynamic>> getInsights() async => {
    'sleep_coach': {
      'need': {
        'value': {'need_sec': 28800},
      },
      'strain_bonus_min': 20,
    },
  };
  @override
  Future<List<Map<String, dynamic>>> sleepWindows({
    int days = 60,
    String? before,
  }) async => [
    {'date': '2021-04-04', 'onset_ts': onset - 86400, 'wake_ts': onset - 57600},
    {'date': '2021-04-05', 'onset_ts': onset - 3600, 'wake_ts': onset},
  ];
  @override
  Future<Map<String, dynamic>> getDayNaps(String date) async => {
    'naps': [
      {
        'start': onset + 15 * 3600,
        'end': onset + 16 * 3600,
        'duration_min': 60,
        'source': 'manual',
      },
    ],
    'nap_min': 60,
  };
}

class App extends AppState {
  App(this.reader) : super.forTesting() {
    repo = reader;
  }
  final Reader reader;
  final calls = <String>[];
  bool refuse = false, apply = true;
  @override
  Future<void> clearSleepOverride(String date) async {
    calls.add('clear:$date');
    if (refuse) throw StateError('authored refusal');
    if (apply) reader.night = {'sleep_source': 'auto'};
  }

  @override
  Future<void> confirmSleep(String date) async {
    calls.add('confirm:$date');
    reader.night['sleep_source'] = 'confirmed';
  }

  @override
  Future<void> setSleepOverride(
    String date,
    DateTime start,
    DateTime end, {
    String source = 'manual',
  }) async {
    calls.add('manual:$date');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Reader reader;
  late App app;
  late ThemeController theme;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('sleep-localized-corrections');
  });
  setUp(() async {
    await resetCoverageStore();
    reader = Reader();
    app = App(reader);
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
  });
  tearDown(() {
    app.dispose();
    theme.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> open(WidgetTester t) async {
    await localizedPage(
      t,
      const SleepDetail(day: day),
      app: app,
      themeController: theme,
    );
    await flush(t);
  }

  Future<void> tap(WidgetTester t, String label) async {
    await reveal(t, find.text(label));
    await t.tap(find.text(label));
    await flush(t);
  }

  test(
    'sleep read carries known coaching, dated onsets and manual naps without invented stages',
    () async {
      final d = await SleepData.load(reader, want: day);
      expect(d.day, day);
      expect(d.need.value, 480);
      expect(d.strainBonusMin, 20);
      expect(d.onsetHistory, [onset - 3600, onset - 86400]);
      expect(d.naps.single['source'], 'manual');
      expect(d.stages, isEmpty);
    },
  );
  testWidgets(
    'fallback confirmation uses the chosen night and retains absence disclosures',
    (t) async {
      await open(t);
      var text = (await readPage(t)).join(' ');
      expect(text, contains('No hypnogram for this night'));
      expect(text, contains('No stage split for this night'));
      expect(text, contains('No overnight signal lines'));
      await tap(t, 'Fix sleep times');
      expect(
        find.text('This window was inferred from heart rate'),
        findsOneWidget,
      );
      await tap(t, 'These times are right');
      expect(app.calls, ['confirm:$day']);
      expect(find.text('You set this window'), findsOneWidget);
      expect(find.text('Back to automatic'), findsOneWidget);
    },
  );
  for (final refusedWrite in [false, true]) {
    testWidgets(
      'rejected sleep ${refusedWrite ? 'reports a refused clear' : 'reports unfinished recalculation'} and can retry',
      (t) async {
        reader.night = {'sleep_source': 'rejected'};
        app.refuse = refusedWrite;
        app.apply = false;
        await open(t);
        expect(find.text('Marked as not sleep'), findsOneWidget);
        await tap(t, 'Undo — go back to automatic');
        expect(
          find.text('That correction has not been applied'),
          findsOneWidget,
        );
        expect(
          refusedWrite
              ? find.text('Nothing was saved. Try again.')
              : find.textContaining('not re-analysed'),
          findsOneWidget,
        );
        app.refuse = false;
        app.apply = true;
        await tap(t, 'Undo — go back to automatic');
        expect(find.text('No night to show'), findsOneWidget);
        expect(find.text('That correction has not been applied'), findsNothing);
        expect(app.calls, ['clear:$day', 'clear:$day']);
      },
    );
  }
  testWidgets(
    'manual time correction is refused when the retained recording covers too little',
    (t) async {
      final db = await LocalDb.instance;
      await db.insert('decoded_onehz', {
        'ts_ms': onset * 1000,
        'rec_ts': onset,
        'counter': 1,
        'hr': 50,
      });
      await open(t);
      await tap(t, 'Fix sleep times');
      await tap(t, 'Set the times myself');
      expect(find.text('WHEN YOU GOT INTO BED'), findsOneWidget);
      Navigator.of(
        t.element(find.byType(TimePickerDialog)),
      ).pop(const TimeOfDay(hour: 23, minute: 0));
      await flush(t);
      expect(find.text('WHEN YOU GOT UP'), findsOneWidget);
      Navigator.of(
        t.element(find.byType(TimePickerDialog)),
      ).pop(const TimeOfDay(hour: 7, minute: 0));
      await flush(t);
      expect(
        find.text('Too little of this window was recorded'),
        findsOneWidget,
      );
      expect(find.textContaining('about 0%'), findsOneWidget);
      expect(app.calls, isEmpty);
      await t.tap(find.text('OK'));
      await flush(t);
      expect(find.byType(SleepDetail), findsOneWidget);
    },
  );
  testWidgets('the no-night nap doorway keeps its viewed historical date', (
    t,
  ) async {
    reader.night = {'sleep_source': 'rejected'};
    await open(t);
    await tap(t, 'Naps');
    expect(t.widget<NapsScreen>(find.byType(NapsScreen)).day, day);
  });
}

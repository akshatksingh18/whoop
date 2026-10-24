// Original recovery evidence and the later day bundle are deliberately different.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/readiness_explain.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/screens/readiness_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String day;
  late LocalRepositoryImpl repo;
  late Map<String, dynamic> original, history, later;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/recovery',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    DayClock.install([], []);
    day = todayLabel();
    repo = LocalRepositoryImpl(getProfileMap: () => {});
    Map<String, dynamic> bundle(
      int score,
      List<double> contributions,
      double hrv,
      int rhr,
    ) => {
      'scalars': {
        'readiness': score,
        'ln_rmssd_v2': math.log(hrv),
        'rhr': rhr,
        'resp_rate': 14.3,
        'tst_min': 450,
      },
      'clinical': {
        'readiness_composite': {
          'value': {'score': score},
          'confidence': .8,
          'drivers': [
            for (var i = 0; i < 3; i++)
              {
                'label': ['HRV', 'RHR', 'RR'][i],
                'contribution': contributions[i],
              },
          ],
        },
      },
    };
    original = bundle(80, [1.1, .4, math.log(4) - 1.5], 56, 52);
    later = bundle(56, [.4, -.2, .05], 42, 60);
    history = {
      'ln_rmssd_history': [for (var i = 0; i < 28; i++) math.log(40 + i % 7)],
      'rhr_history': [for (var i = 0; i < 28; i++) 54.0 + i % 3],
      'resp_history': [for (var i = 0; i < 28; i++) 14.0 + (i % 3) * .1],
      'tst_history': [for (var i = 0; i < 28; i++) 400.0 + i % 7],
    };
    await LocalDb.putDayResult(
      dayId: day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode(later),
      windowJson: '{}',
      series: {'readiness': 56},
    );
    await LocalDb.putComputeFreshness(
      'today',
      jsonEncode({
        'today_day': day,
        'overnight_day': day,
        'overnight_state': 'ready',
        'activity_state': 'ready',
      }),
    );
  });
  tearDownAll(LocalDb.close);
  int sumPoints(ReadinessData d) =>
      50 +
      d.breakdown.fold<int>(0, (sum, r) => sum + ((r['points'] as int?) ?? 0));
  Finder pageScroll() => find
      .descendant(
        of: find.byType(ListView).first,
        matching: find.byType(Scrollable),
      )
      .first;
  Map<String, dynamic> snapshot() => recoveryExplanationSnapshot(
    original,
    history,
    day: day,
    hrvHistory: [
      for (var i = 0; i < 28; i++)
        (
          date: dayLabelOf(
            DateTime.parse(day).subtract(Duration(days: 28 - i)),
          ),
          value: math.log(40 + i % 7),
        ),
    ],
  )!;
  Future<void> pin() =>
      LocalDb.setFrozenHeadline(day, 80, explanation: snapshot());
  test(
    'a later calculation cannot change the original points, values or comparison behind the pinned score',
    () async {
      await pin();
      // The normal scalar history now disagrees too: it must not leak into the saved comparison.
      await LocalDb.putMetricSeriesValue(day, 'ln_rmssd_v2', math.log(42));
      await LocalDb.putMetricSeriesValue(day, 'rhr', 60);
      final d = await ReadinessData.load(repo);
      expect(d.readiness.value, 80);
      expect(sumPoints(d), 80);
      expect(d.originalExplanationMissing, isFalse);
      expect(d.savedMorningExplanation, isTrue);
      expect(d.hrv!.last, closeTo(56, .0001));
      expect(d.hrv!.nights.length, 14);
      expect(d.hrv!.usual, isNotNull);
      final hrv = d.breakdown.singleWhere((r) => r['label'] == 'hrv');
      expect(hrv['value_text'], '56 ms');
      expect(hrv['usual_text'], startsWith('usual '));
      expect(
        d.breakdown.singleWhere((r) => r['label'] == 'rhr')['value_text'],
        '52 bpm',
      );
      expect((await repo.getChart('recovery'))['points'].last['v'], 80);
      expect(
        jsonDecode(
          (await LocalDb.dayResult(day))!['payload_json'] as String,
        )['scalars']['readiness'],
        56,
        reason: 'the retained day and scientific score are not rewritten',
      );
    },
  );
  test(
    'an older pin has no invented reconstruction even when a complete later breakdown exists',
    () async {
      await LocalDb.setFrozenHeadline(day, 80);
      final d = await ReadinessData.load(repo);
      expect(d.readiness.value, 80);
      expect(d.breakdown, isEmpty);
      expect(d.originalExplanationMissing, isTrue);
    },
  );
  test('without a pin, the live calculation still explains itself', () async {
    final d = await ReadinessData.load(repo);
    expect(d.readiness.value, 56);
    expect(sumPoints(d), 56);
    expect(d.originalExplanationMissing, isFalse);
  });
  test(
    'a previous day uses its own saved explanation while that pin still supplies its chart point',
    () async {
      day = dayLabelOf(DateTime.parse(day).subtract(const Duration(days: 1)));
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode(later),
        windowJson: '{}',
        series: {'readiness': 56},
      );
      await pin();
      final d = await ReadinessData.load(repo, day: day);
      expect(d.readiness.value, 80);
      expect(sumPoints(d), 80);
      expect(d.originalExplanationMissing, isFalse);
    },
  );
  test(
    'unscored today never borrows the held-over night’s driver points',
    () async {
      final oldDay = dayLabelOf(
        DateTime.parse(day).subtract(const Duration(days: 1)),
      );
      await LocalDb.putDayResult(
        dayId: oldDay,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode(original),
        windowJson: '{}',
        series: {'readiness': 80},
      );
      await (await LocalDb.instance).delete(
        'day_result',
        where: 'day_id = ?',
        whereArgs: [day],
      );
      await LocalDb.putComputeFreshness(
        'today',
        jsonEncode({
          'today_day': day,
          'overnight_day': oldDay,
          'overnight_state': 'building',
          'showing_prior_overnight': true,
        }),
      );
      final d = await ReadinessData.load(repo);
      expect(d.readiness.value, isNull);
      expect(d.breakdown, isEmpty);
      expect(d.heldOverNight, oldDay);
    },
  );
  test(
    'restart preserves the paired snapshot; replacing the next day cannot reuse the earlier explanation',
    () async {
      await pin();
      await LocalDb.close();
      expect(sumPoints(await ReadinessData.load(repo)), 80);
      final next = dayLabelOf(DateTime.parse(day).add(const Duration(days: 1)));
      await LocalDb.setFrozenHeadline(next, 70);
      expect(await LocalDb.frozenHeadlineExplanation(day, 80), isNull);
      expect(await LocalDb.frozenHeadlineExplanation(next, 70), isNull);
    },
  );
  test(
    'database export, wipe and restore retain the score and original evidence together',
    () async {
      await pin();
      final before = await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor);
      final path = await LocalDb.exportCopy();
      try {
        await LocalDb.wipeAll();
        expect(await LocalDb.frozenHeadline(), isNull);
        await LocalDb.importFromDbFile(path);
        expect(await LocalDb.getCursor(LocalDb.kFrozenHeadlineCursor), before);
        expect((await LocalDb.frozenHeadline())!.value, 80);
        expect(
          (await LocalDb.frozenHeadlineExplanation(day, 80))!['hrv_series'],
          isNotEmpty,
        );
        expect(await LocalDb.frozenHeadlineExplanation(day, 56), isNull);
      } finally {
        await File(path).delete();
      }
    },
  );
  test(
    'a later missing-input note cannot replace an original measured input',
    () async {
      await pin();
      (later['scalars'] as Map).remove('resp_rate');
      (later['scalars'] as Map).remove('ln_rmssd_v2');
      later['respiration'] = {
        'rsa': {'note': 'need_sleep'},
      };
      (later['clinical'] as Map)['rmssd_sleep_session'] = {
        'note': 'need_sleep',
      };
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode(later),
        windowJson: '{}',
      );
      final d = await ReadinessData.load(repo);
      expect(d.breathingNote, isNull);
      expect(d.hrvNote, isNull);
      expect(d.hrv!.last, closeTo(56, .0001));
      expect(sumPoints(d), 80);
    },
  );
  test(
    'the saved recent series preserves calendar gaps and excludes future or stale nights',
    () {
      final e = recoveryExplanationSnapshot(
        original,
        history,
        day: day,
        hrvHistory: [
          (
            date: dayLabelOf(
              DateTime.parse(day).subtract(const Duration(days: 61)),
            ),
            value: math.log(30),
          ),
          (
            date: dayLabelOf(
              DateTime.parse(day).subtract(const Duration(days: 60)),
            ),
            value: math.log(40),
          ),
          (
            date: dayLabelOf(
              DateTime.parse(day).subtract(const Duration(days: 3)),
            ),
            value: math.log(44),
          ),
          (date: day, value: math.log(42)),
          (
            date: dayLabelOf(DateTime.parse(day).add(const Duration(days: 1))),
            value: math.log(60),
          ),
        ],
      )!;
      final dates = (e['hrv_series'] as List).map((s) => s['date']).toList();
      expect(dates, hasLength(3));
      expect(dates.last, day);
      expect(
        math.exp((e['hrv_series'] as List).last['value'] as double),
        closeTo(56, .0001),
      );
    },
  );
  for (final shape in ['wrong format', 'wrong total', 'missing values']) {
    test(
      'a $shape snapshot fails closed without discarding the score',
      () async {
        final e = snapshot();
        if (shape == 'wrong format') e['format'] = 99;
        if (shape == 'wrong total')
          e['composite'] = (later['clinical'] as Map)['readiness_composite'];
        if (shape == 'missing values') e.remove('values');
        await LocalDb.setFrozenHeadline(day, 80, explanation: e);
        final d = await ReadinessData.load(repo);
        expect(d.readiness.value, 80);
        expect(d.breakdown, isEmpty);
        expect(d.originalExplanationMissing, isTrue);
      },
    );
  }
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets(
      'the saved morning explanation and HRV comparison remain usable at ${scale}x',
      (t) async {
        final d = await t.runAsync(() async {
          await pin();
          return ReadinessData.load(repo);
        });
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: w!,
            ),
            home: RepaintBoundary(
              key: auditCaptureKey,
              child: ReadinessDetail(data: d),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('80'), findsOneWidget);
        final caption = find.text(
          'Same nightly HRV and 28-night window as the saved morning score.',
        );
        await t.scrollUntilVisible(
          caption,
          250,
          maxScrolls: 60,
          scrollable: pageScroll(),
        );
        await t.pumpAndSettle();
        expect(caption, findsOneWidget);
        expect(find.text('Morning breakdown unavailable'), findsNothing);
        final method = find.text("How it's worked out");
        await t.scrollUntilVisible(
          method,
          250,
          maxScrolls: 60,
          scrollable: pageScroll(),
        );
        await t.tap(method);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await captureAuditScroll(
          t,
          'recovery_saved_$scale',
          prefix: 'coverage102',
          scrollable: pageScroll(),
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
    testWidgets(
      'the older-pin state keeps score/history and honest copy readable at ${scale}x',
      (t) async {
        final d = await t.runAsync(() async {
          await LocalDb.setFrozenHeadline(day, 80);
          return ReadinessData.load(repo);
        });
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: w!,
            ),
            home: RepaintBoundary(
              key: auditCaptureKey,
              child: ReadinessDetail(data: d),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('80'), findsOneWidget);
        await t.ensureVisible(find.text('Morning breakdown unavailable'));
        await t.pumpAndSettle();
        expect(find.textContaining('cannot be reconstructed'), findsOneWidget);
        expect(t.takeException(), isNull);
        await captureAuditScroll(
          t,
          'recovery_legacy_$scale',
          prefix: 'coverage102',
          scrollable: pageScroll(),
        );
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      },
    );
  }
}

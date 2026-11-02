// Active recap and breathing readers filter dated inputs before presenting them.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/nightly_sweep.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/ui2/screens/sleep_breathing.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

class History extends LocalRepository {
  bool above = false;
  final readNights = <String>[];
  final now = DateTime.parse(todayLabel());
  String day(int ago) =>
      dayLabelOf(DateTime(now.year, now.month, now.day - ago));
  int ts(int ago) =>
      DateTime(now.year, now.month, now.day - ago, 12).millisecondsSinceEpoch ~/
      1000;
  @override
  Future<List<String>> availableDays() async => [
    for (var i = -1; i < 40; i++) day(i),
  ];
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async {
    if (metric == 'steps')
      throw StateError('synthetic unavailable step history');
    if (metric == 'strain') return {'points': null};
    if (metric == 'efficiency')
      return {
        'points': [
          {'t': ts(1), 'v': 90},
        ],
      };
    if (metric == 'irregular_rhythm_flag')
      return {
        'points': [
          {'t': ts(3), 'v': 1},
        ],
      };
    return {
      'algo_breaks': [
        null,
        {'t': ts(10)},
        {'t': ts(8)},
        {'t': 'bad'},
      ],
      'points': [
        null,
        {},
        {'t': ts(0), 'v': double.nan},
        for (var i = -1; i < 20; i++) {'t': ts(i), 'v': 50.0 + i},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getDayLungs(String date) async {
    readNights.add(date);
    return {
      'cvhr': {
        'value': date == day(2)
            ? {'cvhr_per_hour': null, 'analyzed_hours': 4}
            : {
                'cvhr_per_hour': date == day(0) && above
                    ? 30.0
                    : 4.0 + readNights.length % 4,
                'analyzed_hours': 5.0,
              },
      },
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  test(
    'COV-47 recap refuses cross-version, future, nonfinite and unreadable history',
    () async {
      final repo = History();
      final series = await collectSweepSeries(repo, repo.now);
      expect(series.map((s) => s.key), [
        'readiness',
        'rhr',
        'rmssd',
        'tst_min',
      ]);
      for (final s in series) {
        expect(s.today, 50);
        expect(s.history, [for (var i = 1; i <= 8; i++) 50.0 + i]);
      }
      expect(
        sweepFindings(series),
        isEmpty,
        reason:
            'an eight-day comparable window cannot become a fortnight of evidence',
      );
    },
  );
  for (final above in [false, true]) {
    testWidgets(
      'COV-47 across-night breathing excludes unknown nights and retains interpretation $above',
      (t) async {
        final repo = History()..above = above;
        final nights = await SleepBreathingScreen.nights(repo);
        expect(nights, hasLength(29));
        expect(nights.any((n) => n.dayKey == repo.day(2)), false);
        expect(
          nights.singleWhere((n) => n.dayKey == repo.day(3)).irregularRhythm,
          true,
        );
        expect(
          repo.readNights.every(
            (d) =>
                d.compareTo(repo.day(29)) >= 0 && d.compareTo(repo.day(0)) <= 0,
          ),
          true,
        );
        final metric = await SleepBreathingScreen.load(repo);
        expect(metric.value, isNotNull);
        await localizedPage(t, SleepBreathingScreen(data: metric));
        final text = (await readPage(t)).join(' ');
        expect(
          text,
          contains(
            above ? 'Higher than your usual' : 'Within your usual range',
          ),
        );
        expect(text, contains('not a breathing test'));
        final help = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'What this means',
        );
        await reveal(t, help);
        await t.tap(help);
        await t.pumpAndSettle();
        expect(
          (await readPage(t)).join(' '),
          contains('It cannot rule anything in or out'),
        );
      },
    );
  }
}

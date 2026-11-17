// Stored timeline rows can be incomplete; never invent a clock or measurement.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLocalizations l;
  final start = DateTime(2021, 4, 6).millisecondsSinceEpoch ~/ 1000;
  setUpAll(
    () async => l = await AppLocalizations.delegate.load(const Locale('en')),
  );

  test('incomplete stored rest/work rows do not acquire invented times', () {
    final moments = dayMoments(
      l: l,
      timeline: {
        'sleep': [
          null,
          {},
          {'onset_ts': start},
          {'wake_ts': start},
        ],
        'naps': [
          null,
          {},
          {'start': start + 60},
        ],
        'sessions': [
          null,
          {},
          {'end_ts': start + 120},
        ],
      },
    );
    expect(moments, hasLength(1));
    expect(moments.single.title, 'Nap');
    expect(moments.single.at, start + 60);
    expect(moments.single.until, isNull);
    expect(moments.single.detail, isNot(contains('0m')));
  });

  test('unknown session type retains supplied name and optional evidence', () {
    final moments = dayMoments(
      l: l,
      timeline: {
        'sessions': [
          {
            'start_ts': start,
            'end_ts': start + 3600,
            'type': 'authored_unknown_activity',
            'duration_min': 60,
            'avg_hr': 88,
          },
          {'start_ts': start + 4000},
        ],
      },
    );
    expect(moments.map((m) => m.title), [
      'authored unknown activity',
      'Workout',
    ]);
    expect(moments.first.until, start + 3600);
    expect(moments.first.detail, contains('1h 0m'));
    expect(moments.first.detail, contains('88 bpm avg'));
    expect(moments.last.until, isNull);
    expect(moments.last.detail, isNot(contains('bpm')));
  });

  test('wear states remain distinct and only long bounded gaps are shown', () {
    final moments = dayMoments(
      l: l,
      timeline: const {},
      wear: {
        'segments': [
          for (final (index, state) in [
            'off_wrist',
            'charging',
            'pending',
            'unknown',
          ].indexed)
            {
              'state': state,
              'start': start + index * 3600,
              'end': start + index * 3600 + 900,
            },
          {'state': 'off_wrist', 'end': start + 900},
          {'state': 'off_wrist', 'start': start + 20000},
          {'state': 'off_wrist', 'start': start + 21000, 'len_min': 14},
          {'state': 'worn', 'start': start, 'len_min': 90},
        ],
      },
    );
    expect(moments.map((m) => m.title), [
      'Band off your wrist',
      'On the charger',
      'Not yet synced',
      'Recording gap',
    ]);
    expect(moments.every((m) => m.color == null), isTrue);
    expect(moments.every((m) => m.until! - m.at == 900), isTrue);
  });

  test(
    'incomplete extremes stay absent while an observed extreme retains its clock',
    () {
      final moments = dayMoments(
        l: l,
        timeline: {
          'highs': {
            'peak_hr': {'v': 120},
            'low_hr': {'t': start + 30, 'v': 52.4},
          },
        },
      );
      expect(moments, hasLength(1));
      expect(moments.single.title, 'Lowest heart rate');
      expect(moments.single.at, start + 30);
      expect(moments.single.detail, contains('52 bpm'));
      expect(
        dayMoments(
          l: l,
          timeline: {
            'highs': {
              'peak_hr': {'t': start},
              'low_hr': null,
            },
          },
        ),
        isEmpty,
      );
    },
  );
}

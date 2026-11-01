// Current Today phase/absence disclosures, no sensor or native assertions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class PhaseApp extends AppState {
  PhaseApp() : super.forTesting();
  bool sync = false, calculate = false;
  int syncCalls = 0;
  @override
  bool get syncingNow => sync;
  @override
  bool get deriving => calculate;
  @override
  bool get derivePending => false;
  @override
  Future<void> syncNow() async {
    syncCalls++;
  }

  void publish() => notifyListeners();
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('home-phases');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final phase in ['sync', 'derive']) {
    testWidgets(
      'COV-44 Today $phase replaces connection latch and clears it on completion',
      (t) async {
        final app = PhaseApp();
        addTearDown(app.dispose);
        await localizedPage(
          t,
          const Scaffold(body: HomeScreen(data: HomeData())),
          app: app,
        );
        final card = t.widget<StatusCard>(find.byType(StatusCard).first);
        card.onFix!();
        await t.pump(const Duration(milliseconds: 100));
        expect(app.syncCalls, 1);
        expect(find.text('Connecting to your band'), findsOneWidget);
        app.sync = phase == 'sync';
        app.calculate = phase == 'derive';
        app.publish();
        await t.pump(const Duration(milliseconds: 100));
        expect(
          find.text(
            phase == 'sync'
                ? 'Syncing with your band'
                : "Crunching last night's numbers",
          ),
          findsOneWidget,
        );
        app.sync = false;
        app.calculate = false;
        app.publish();
        await t.pumpAndSettle();
        expect(find.text('Nothing derived yet'), findsOneWidget);
        expect(find.text('Connecting to your band'), findsNothing);
      },
    );
  }
  for (final kind in [
    'workout_hold',
    'algo_version',
    'stale',
    'needs_history',
    'failed',
    'missing',
    'unstamped',
  ]) {
    testWidgets(
      'COV-44 Today rollup $kind does not masquerade as current insight',
      (t) async {
        final data = HomeData(
          dayId: todayLabel(),
          readiness: const Metric(
            value: 70,
            confidence: .8,
            tier: MetricTier.estimate,
          ),
          insightsStale: {'kind': kind, 'built_for_day': '2021-04-06'},
        );
        await localizedPage(t, Scaffold(body: HomeScreen(data: data)));
        final content = (await readPage(t)).join(' ');
        expect(content, contains('Recovery'));
        expect(
          content,
          anyOf(contains('insights'), contains('workout'), contains('rollup')),
        );
        expect(content, isNot(contains('NaN')));
      },
    );
  }
  for (final state in ['amber', 'red'])
    for (final z in <double?>[null, 2.5, -1]) {
      testWidgets(
        'COV-44 Today illness $state $z retains night and uncertainty',
        (t) async {
          final d = HomeData(
            dayId: todayLabel(),
            readiness: const Metric(
              value: 70,
              confidence: .8,
              tier: MetricTier.estimate,
            ),
            illnessState: state,
            illnessDay: '2021-04-06',
            illnessZ: z,
          );
          await localizedPage(t, Scaffold(body: HomeScreen(data: d)));
          final content = (await readPage(t)).join(' ');
          if (state == 'amber')
            expect(content, contains('6 April'));
          else
            expect(content, contains('Several nights in a row'));
          expect(content, contains('not name a cause'));
          expect(
            content.toLowerCase(),
            anyOf(contains('watch'), contains('usual'), contains('rest')),
          );
          expect(content, isNot(contains('null')));
        },
      );
    }
  testWidgets(
    'COV-44 translated date chips, tiers and object envelopes preserve public read contracts',
    (t) async {
      late AppLocalizations l;
      await localizedPage(
        t,
        Scaffold(
          body: Builder(
            builder: (c) {
              l = AppLocalizations.of(c)!;
              return const Text('Synthetic readout contracts');
            },
          ),
        ),
      );
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      for (var i = 1; i <= 12; i++) expect(monthShortName(i, l), months[i - 1]);
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (var i = 1; i <= 7; i++)
        expect(weekdayShortName(i, l), weekdays[i - 1]);
      for (final (v, tier, label) in [
        (null, -1, 'Not scored'),
        (25, 0, 'Rest today'),
        (26, 1, 'Take it easy'),
        (36, 1, 'Take it easy'),
        (37, 2, 'Steady'),
        (60, 2, 'Steady'),
        (61, 3, 'Good to go'),
      ]) {
        final b = readinessBand(v, l);
        expect(b.tier, tier);
        expect(b.label, label);
      }
      for (final state in ['building', 'missing'])
        expect(
          staleOvernightNote({
            'status': {
              'showing_prior_overnight': true,
              'overnight_day': '2021-04-06',
              'overnight_state': state,
            },
          }, l),
          contains(state == 'building' ? 'worked out' : 'reached'),
        );
      final m = envMetric(
        {
          'confidence': .6,
          'tier': 'ESTIMATE',
          'inputs_used': ['synthetic'],
        },
        12,
        unit: 'ms',
      );
      expect(m.value, 12);
      expect(m.unit, 'ms');
      expect(m.confidence, .6);
      expect(
        envValue({
          'value': {'n': 0},
        }),
        {'n': 0},
      );
      expect(splitUnit('12 ms'), ('12', 'ms'));
      expect(splitUnit('absent'), ('absent', ''));
    },
  );
}

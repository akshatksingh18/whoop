// The embedded Sleep page names the dated night read from local storage.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart'
    show kAlgoVersion;
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart' show prettyDay;
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import '../ui2/screens/nutrition_root_test.dart' show io;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('stored-embedded-sleep-date');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final scale in [1.0, 3.1]) {
    testWidgets('embedded Sleep names the historical night at scale $scale', (
      t,
    ) async {
      const day = '2021-04-06';
      final midnight = localDayStartSec(day)!;
      final onset = midnight - 3600;
      final wake = midnight + 7 * 3600;
      await LocalDb.putDayResult(
        dayId: day,
        algoVersion: kAlgoVersion,
        payloadJson: jsonEncode({
          'date': day,
          'device_family': 'gen4',
          'sleep_source': 'auto',
          'scalars': {'tst_min': 420},
          'sleep': {
            'accounting': {
              'confidence': .8,
              'value': {
                'tst_sec': 25200,
                'waso_sec': 3600,
                'efficiency_pct': 87.5,
              },
            },
            'window': {
              'value': {
                'onset_ms': onset * 1000,
                'offset_ms': wake * 1000,
                'spt_sec': 28800,
              },
            },
          },
          'series': {
            'hypnogram': [
              {'start': onset, 'end': midnight, 'stage': 'light'},
              {'start': midnight, 'end': midnight + 3600, 'stage': 'deep'},
              {'start': midnight + 3600, 'end': wake, 'stage': 'light'},
            ],
          },
        }),
        windowJson: '{}',
        source: 'band',
        finalized: true,
        series: const {'tst_min': 420},
      );
      final app = AppState.forTesting()
        ..repo = LocalRepositoryImpl(getProfileMap: () => const {});
      addTearDown(app.dispose);
      final store = await LocalDb.instance;
      final before = await store.query('day_result');
      await localizedPage(
        t,
        const Scaffold(
          body: SingleChildScrollView(
            child: SleepDetail(embedded: true, day: day),
          ),
        ),
        app: app,
        scale: scale,
        settle: false,
      );
      await io(t);
      final l = AppLocalizations.of(t.element(find.byType(SleepDetail)));
      expect(find.text(prettyDay(day, l)), findsOneWidget);
      expect(find.text('Through the night'), findsOneWidget);
      final chart = find.byWidgetPredicate(
        (w) => w is Scrubber && w.label == 'Hypnogram',
      );
      await reveal(t, chart);
      final displayed = t.widget<Scrubber>(chart);
      expect(displayed.describe(.2), contains('Deep'));
      expect(await t.runAsync(() => store.query('day_result')), before);
      expect(t.takeException(), isNull);
    });
  }
}

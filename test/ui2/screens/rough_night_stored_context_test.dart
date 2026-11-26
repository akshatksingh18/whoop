// A dated Rough night reads saved context independently of its signs.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/ui2/screens/rough_night.dart';

import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('rough-night-stored-context');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final consent in [false, true]) {
    testWidgets(
      'Rough night preserves measured signs and the enabled context: $consent',
      (t) async {
        final today = DateTime.parse(todayLabel());
        String date(int earlier) =>
            dayLabelOf(DateTime(today.year, today.month, today.day - earlier));
        final day = date(1);
        final at = DateTime(today.year, today.month, today.day - 1, 20, 30);
        final end = at.millisecondsSinceEpoch ~/ 1000;
        final repo = LocalRepositoryImpl(
          getProfileMap: () => {
            'track_cycle': consent,
            'repro_state': 'cycling',
          },
        );
        final db = (await t.runAsync(() async {
          final db = await LocalDb.instance;
          for (var earlier = 21; earlier >= 1; earlier--) {
            final d = date(earlier);
            for (final entry in {
              'rhr': earlier == 1 ? 90.0 : 60.0 + earlier % 3,
              'rmssd': earlier == 1 ? 20.0 : 65.0 + earlier % 3,
              'dip_pct': earlier == 1 ? 5.0 : 30.0 + earlier % 3,
            }.entries) {
              await LocalDb.putMetricSeriesValue(d, entry.key, entry.value);
            }
          }
          await LocalDb.putDayResult(
            dayId: day,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode({'date': day, 'series': {}}),
            windowJson: '{}',
          );
          await LocalDb.putSession({
            'id': 'authored-evening-training',
            'type': 'yoga',
            'status': 'done',
            'source': 'manual',
            'start_ts': end - 1200,
            'end_ts': end,
            'created_at': 1,
          });
          await LocalDb.putCycleLog(date(19), 'start');
          await LocalDb.putCycleLog(date(47), 'start');
          await LocalDb.putBaseline(
            'crossday',
            jsonEncode({
              'algo_version': kAlgoVersion,
              'built_for_day': date(0),
              'recent': [
                {'date': day, 'illness': true},
              ],
            }),
          );
          return db;
        }))!;
        Future<List<Object>> snapshot() async => [
          await db.query('sessions'),
          await db.query('cycle_log'),
          await db.query('baselines'),
          await db.query('metric_series', orderBy: 'date,key'),
        ];
        final before = await t.runAsync(snapshot);
        const anchor = SizedBox();
        await localizedPage(t, const Scaffold(body: anchor));
        final context = t.element(find.byWidget(anchor));
        final l = AppLocalizations.of(context)!;
        final night = (await t.runAsync(
          () => loadRoughNight(repo, day, c: context),
        ))!;
        expect(night.day, day);
        expect(night.signs, 3);
        expect(night.illnessFlagged, isTrue);
        expect(night.knows, [
          l.roughNightLateTraining('8:30 PM'),
          l.roughNightIllness,
          if (consent) l.roughNightLuteal,
        ]);
        await localizedPage(
          t,
          Scaffold(
            body: RoughNightCard(night: night, ask: 'never'),
          ),
        );
        for (final fact in night.knows) {
          expect(find.text(fact), findsOneWidget);
        }
        expect(await t.runAsync(snapshot), before);
      },
    );
  }
}

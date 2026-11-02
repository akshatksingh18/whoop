// Deeper Train -> Strain -> Zones read/retry and enlarged-layout controls.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/activity/zones.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart';

Map<String, dynamic> measured() => {
  'ceiling': {'bpm': 182, 'date': '2026-01-14', 'session_type': 'run'},
  'source': 'karvonen',
  'max_hr': 182,
  'resting_hr': 50,
  'resting_days': 28,
  'age': 30,
  'zones': [
    for (var i = 1; i <= 5; i++)
      {'zone': i, 'name': 'Zone $i', 'lo': 90 + i * 15, 'hi': 105 + i * 15},
  ],
  'distribution': {
    'minutes': [40, 30, 20, 10, 5],
    'sessions': 12,
    'easy_min': 70,
    'moderate_min': 20,
    'hard_min': 15,
    'shape': 'pyramidal',
  },
};

class _Repo extends LocalRepository {
  bool fail = true;
  @override
  Future<Map<String, dynamic>> getZones() async {
    if (fail) throw StateError('synthetic failed read');
    return measured();
  }
}

void main() {
  setUpAll(loadAuditFonts);
  testWidgets(
    'failed zones read is retryable and never claims missing evidence',
    (t) async {
      t.view.physicalSize = const Size(1170, 2700);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      final repo = _Repo();
      final app = AppState.forTesting()..repo = repo;
      addTearDown(app.dispose);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const RepaintBoundary(
              key: auditCaptureKey,
              child: ZonesDetail(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Could not read heart-rate zones'), findsOneWidget);
      expect(find.text('No measured ceiling yet'), findsNothing);
      await captureAuditScroll(t, 'zones_read_failure', prefix: 'build100');
      repo.fail = false;
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('182'), findsOneWidget);
      expect(find.text('Could not read heart-rate zones'), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  for (final scale in [1.0, 3.1]) {
    testWidgets(
      'measured zones and their full distribution stay readable at $scale',
      (t) async {
        t.view.physicalSize = const Size(1170, 2700);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(
                key: auditCaptureKey,
                child: ZonesDetail(data: ZonesData.parse(measured())),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await captureAuditScroll(
          t,
          'zones_measured_$scale',
          prefix: 'build100',
        );
        for (var i = 0; i < 12; i++) {
          await t.drag(find.byType(Scrollable).last, const Offset(0, -600));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
        expect(
          find.textContaining('description, not a target'),
          findsOneWidget,
        );
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}

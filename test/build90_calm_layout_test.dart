import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  testWidgets('large text comparison values and detail title remain whole', (
    t,
  ) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(3.1)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  NavBar(
                    'Food, training and recovery',
                    sub: 'Earlier and current periods',
                  ),
                  InlineMetrics([
                    ('Start', '81.1 kg', C.body),
                    ('Latest', '80.2 kg', C.body),
                    ('Change', '−0.9 kg', C.body),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final title = t.widget<Text>(find.text('Food, training and recovery'));
    expect(title.maxLines, isNull);
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    for (final value in ['81.1 kg', '80.2 kg', '−0.9 kg']) {
      expect(t.widget<Text>(find.text(value)).softWrap, isFalse);
    }
    expect(
      t.getTopLeft(find.text('81.1 kg')).dy,
      lessThan(t.getTopLeft(find.text('80.2 kg')).dy),
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(3.1)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Section(
              'Recent workouts',
              SizedBox(),
              action: 'Add a past workout',
              onAction: () {},
            ),
          ),
        ),
      ),
    );
    expect(t.widget<Text>(find.text('Add a past workout')).maxLines, isNull);
    expect(t.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets(
      'metric digits share an edge with optional charts, units and actions at ${scale}x',
      (t) async {
        t.view.physicalSize = const Size(1170, 2532);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        var opened = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Surface(
                    child: Column(
                      children: [
                        MetricLine(
                          label: 'HRV',
                          value: '67',
                          unit: 'ms',
                          color: C.recovery,
                          values: const [60, 61, null, 67],
                          onTap: () => opened++,
                        ),
                        const MetricLine(
                          label: 'Resting HR asleep',
                          value: '53',
                          unit: 'bpm',
                          color: C.recovery,
                        ),
                        MetricLine(
                          label: 'Breathing rate',
                          value: '15.8',
                          unit: 'breaths/min',
                          color: C.sleep,
                          onTap: () => opened++,
                        ),
                        const MetricLine(
                          label: 'Wear time',
                          color: C.body,
                          absentWhy: 'Not yet synced; no off-wrist event',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final edges = [
          '67',
          '53',
          '15.8',
        ].map((v) => t.getBottomRight(find.text(v)).dx).toList();
        expect(edges[0], closeTo(edges[1], .1));
        expect(edges[1], closeTo(edges[2], .1));
        expect(find.text('Resting HR asleep'), findsOneWidget);
        expect(find.text('Not yet synced; no off-wrist event'), findsOneWidget);
        expect(t.widget<Text>(find.text('15.8')).softWrap, isFalse);
        await t.ensureVisible(find.text('15.8'));
        await t.tap(find.text('15.8'));
        expect(opened, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
}

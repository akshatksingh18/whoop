// The shipped dated-detail control and Material picker, not a copied date rule.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  setUp(() => DayClock.install([], []));
  tearDown(() => DayClock.install([], []));
  const days = ['2021-04-07', '2021-04-06', '2021-04-05'];
  late ValueNotifier<String?> current;
  late ValueNotifier<bool> visible;
  late List<String> picked;

  Future<void> mount(WidgetTester t) async {
    current = ValueNotifier('2021-04-06');
    visible = ValueNotifier(true);
    picked = [];
    addTearDown(current.dispose);
    addTearDown(visible.dispose);
    await localizedPage(
      t,
      ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, show, _) => Scaffold(
          body: show
              ? ValueListenableBuilder<String?>(
                  valueListenable: current,
                  builder: (_, day, _) => DayNav(
                    day: day,
                    days: days,
                    onDay: (day) {
                      picked.add(day);
                      current.value = day;
                    },
                  ),
                )
              : const Text('Originating control closed'),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester t) async {
    await t.tap(
      find.descendant(
        of: find.byType(DayNav),
        matching: find.text(dayNavLabel(current.value)),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(t.takeException(), isNull);
  }

  Future<void> select(WidgetTester t, int day) async {
    await t.tap(
      find.descendant(
        of: find.byType(CalendarDatePicker),
        matching: find.text('$day'),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> finish(WidgetTester t, {required bool save}) async {
    final labels = MaterialLocalizations.of(
      t.element(find.byType(DatePickerDialog)),
    );
    await t.tap(
      find.text(save ? labels.okButtonLabel : labels.cancelButtonLabel),
    );
    await t.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(t.takeException(), isNull);
  }

  testWidgets(
    'COV-48 dated picker cancellation and unchanged selection preserve the current day',
    (t) async {
      await mount(t);
      await open(t);
      await select(t, 5);
      await finish(t, save: false);
      expect(current.value, '2021-04-06');
      expect(picked, isEmpty);
      await open(t);
      expect(
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2021, 4, 6),
      );
      await finish(t, save: true);
      expect(current.value, '2021-04-06');
      expect(picked, isEmpty);
    },
  );

  testWidgets(
    'COV-48 explicit historical selection and Latest reopen with the authoritative date',
    (t) async {
      await mount(t);
      await open(t);
      await select(t, 5);
      await finish(t, save: true);
      expect(current.value, '2021-04-05');
      expect(picked, ['2021-04-05']);
      await open(t);
      expect(
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2021, 4, 5),
      );
      await finish(t, save: false);
      await t.tap(find.text('Latest'));
      await t.pumpAndSettle();
      expect(current.value, '2021-04-07');
      expect(picked, ['2021-04-05', '2021-04-07']);
      await open(t);
      expect(
        t
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        DateTime(2021, 4, 7),
      );
      await select(t, 6);
      await finish(t, save: true);
      expect(current.value, '2021-04-06');
      expect(picked, ['2021-04-05', '2021-04-07', '2021-04-06']);
    },
  );

  testWidgets(
    'COV-48 dated detail retains its recorded-zone caption after travel',
    (t) async {
      final start = dayZoneCalendarStart('2021-04-05', 'Asia/Kolkata')!;
      final changed =
          DateTime.utc(2021, 4, 7, 18).millisecondsSinceEpoch ~/ 1000;
      final changes = [
        ZoneChange(start, 'Asia/Kolkata'),
        ZoneChange(changed, 'America/Chicago'),
      ];
      DayClock.install(
        buildDayZones(
          fromSec: start,
          throughSec: changed + 3 * 86400,
          changes: changes,
        ),
        changes,
      );
      final selected = <String>[];
      expect(DayClock.forDate('2021-04-06')!.zoneId, 'Asia/Kolkata');
      expect(
        DayClock.abbreviation(
          '2021-04-06',
          nowSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
        'IST',
      );
      await localizedPage(
        t,
        Scaffold(
          body: Column(children: dayNavRow('2021-04-06', days, selected.add)),
        ),
      );
      expect(find.text('IST'), findsOneWidget);
      expect(find.text(dayNavLabel('2021-04-06')), findsOneWidget);
      await t.tap(find.byIcon(LucideIcons.chevronRight));
      await t.pumpAndSettle();
      expect(selected, ['2021-04-07']);
    },
  );

  testWidgets(
    'COV-48 a dated picker result cannot update its disposed originating control',
    (t) async {
      await mount(t);
      await open(t);
      await select(t, 5);
      visible.value = false;
      await t.pumpAndSettle();
      expect(find.byType(DayNav), findsNothing);
      await finish(t, save: true);
      expect(current.value, '2021-04-06');
      expect(picked, isEmpty);
      expect(find.text('Originating control closed'), findsOneWidget);
    },
  );
}

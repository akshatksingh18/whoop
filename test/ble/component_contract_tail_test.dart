// Component contracts the public constructors and seams permit. Authored
// synthetic inputs only; no physical radio, OS delivery or native claim.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/ui2/profile/alarm.dart';
import 'package:whoop_companion/ui2/screens/food_calendar.dart';
import 'package:whoop_companion/ui2/screens/food_diary.dart' show shiftDay;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);

  testWidgets('a public view given a time without an arm state shows Not set', (
    t,
  ) async {
    final now = DateTime(2024, 5, 1, 21);
    await localizedPage(
      t,
      AlarmScreenView(
        armedAt: now.add(const Duration(hours: 9)),
        state: AlarmArmState.none,
        now: now,
      ),
    );
    expect(find.text('Not set'), findsWidgets);
  });

  // A week two weeks ahead is entirely after today on any run date, so the
  // dimmed, unopenable future-day cell no longer depends on the weekday CI runs.
  testWidgets('a future week shows every day dimmed and unopenable', (t) async {
    final day = shiftDay(todayLabel(), 14);
    final monday = mondayOf(day);
    String? chosen;
    await localizedPage(
      t,
      FoodWeekStrip(date: day, onDay: (d) => chosen = d, marks: const {}),
    );
    for (var i = 0; i < 7; i++) {
      expect(shiftDay(monday, i).compareTo(todayLabel()), greaterThan(0));
    }
    await t.tap(
      find.text('${DateTime.parse(monday).day}').first,
      warnIfMissed: false,
    );
    await t.pump();
    expect(chosen, isNull);
  });
}

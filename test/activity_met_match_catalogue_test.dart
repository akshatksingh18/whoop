import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/activity_met.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';

/// The data layer prices a saved workout from [kActivityMetByKey]; the screens
/// price it from the catalogue. If the two drift, the stored calories stop
/// matching the shown ones, which is the Build 90 bug this table exists to end.
void main() {
  test('every catalogue activity has the same MET here', () {
    final catalogue = {for (final a in allActivities) a.typeKey: a.met};
    expect(kActivityMetByKey, catalogue);
  });

  test('lookup ignores case and spaces like activityByName', () {
    expect(catalogueMetFor('Weight training'), 6.0);
    expect(catalogueMetFor('weight_training'), 6.0);
    expect(catalogueMetFor('General workout'), isNull);
    expect(catalogueMetFor('not an activity'), isNull);
    expect(catalogueMetFor(null), isNull);
  });
}

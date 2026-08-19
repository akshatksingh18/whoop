import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gps/route_types.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';

/// The bug this pins: `kRouteTypeKeys` used to live in app_state as
/// {'run', 'cycle', 'walk', 'hike'} while the catalogue stores 'running',
/// 'cycling', 'walking', 'hiking'. Zero overlap, so the route gate returned
/// before it ever asked for location permission — no map on any activity, and
/// on iOS no Location row in Settings at all, because the OS only creates one
/// after the first request.
void main() {
  final catalogue = {
    for (final a in allActivities)
      if (a.gps) a.typeKey,
  };

  test('every gps activity in the catalogue records a route', () {
    final missing = catalogue.difference(kRouteTypeKeys);
    expect(missing, isEmpty,
        reason: 'catalogue marks these gps: true but they would record no '
            'route: $missing');
  });

  test('no route type is a key the catalogue cannot produce', () {
    final orphans = kRouteTypeKeys.difference(catalogue);
    expect(orphans, isEmpty,
        reason: 'these keys match no activity, so they can never fire: '
            '$orphans — the exact shape of the original bug');
  });

  test('the gate accepts a real typeKey and is case-insensitive', () {
    expect(typeRecordsRoute('running'), isTrue);
    expect(typeRecordsRoute('Running'), isTrue);
    expect(typeRecordsRoute('trail_running'), isTrue);
    // The old set's contents, none of which any activity produces.
    expect(typeRecordsRoute('run'), isFalse);
    expect(typeRecordsRoute('walk'), isFalse);
    expect(typeRecordsRoute(null), isFalse);
  });

  test('an indoor activity does not arm gps', () {
    expect(typeRecordsRoute('treadmill'), isFalse);
    expect(typeRecordsRoute('indoor_bike'), isFalse);
  });
}

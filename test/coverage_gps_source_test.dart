// Plugin-boundary controls. They prove Dart reactions, not real GPS delivery.
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:whoop_companion/gps/gps_source.dart';

class _Geo extends GeolocatorPlatform {
  bool service = true, fail = false;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requested = LocationPermission.whileInUse;
  var prompts = 0, appSettings = 0, locationSettings = 0;
  List<Position> positions = [];
  @override
  Future<bool> isLocationServiceEnabled() async {
    if (fail) throw StateError('synthetic service failure');
    return service;
  }

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return requested;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return !fail;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return !fail;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      Stream.fromIterable(positions);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  late _Geo geo;
  setUp(() {
    original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = geo = _Geo();
  });
  tearDown(() => GeolocatorPlatform.instance = original);
  test(
    'disabled service and platform failure are distinct from denial',
    () async {
      geo.service = false;
      expect(
        await GpsSource.ensurePermission(),
        GpsPermissionStatus.serviceOff,
      );
      geo.fail = true;
      expect(await GpsSource.ensurePermission(), GpsPermissionStatus.error);
      expect(geo.prompts, 0);
    },
  );
  for (final permission in LocationPermission.values) {
    test(
      'existing ${permission.name} permission follows its actual state',
      () async {
        geo.permission = permission;
        geo.requested = LocationPermission.denied;
        final expected = switch (permission) {
          LocationPermission.always ||
          LocationPermission.whileInUse => GpsPermissionStatus.granted,
          LocationPermission.deniedForever => GpsPermissionStatus.deniedForever,
          _ => GpsPermissionStatus.denied,
        };
        expect(await GpsSource.ensurePermission(), expected);
        expect(geo.prompts, permission == LocationPermission.denied ? 1 : 0);
      },
    );
  }
  test(
    'a user grant is honored; a permanent denial routes to app settings',
    () async {
      geo.permission = LocationPermission.denied;
      expect(await GpsSource.ensurePermission(), GpsPermissionStatus.granted);
      expect(geo.prompts, 1);
      await GpsSource.openSettingsFor(GpsPermissionStatus.deniedForever);
      await GpsSource.openSettingsFor(GpsPermissionStatus.serviceOff);
      expect(geo.appSettings, 1);
      expect(geo.locationSettings, 1);
    },
  );
  test(
    'valid zero speed remains measured; invalid speed and uncertainty are absent',
    () async {
      geo.positions = [
        for (final speed in [0.0, -1.0, double.nan, double.infinity])
          Position(
            longitude: 0,
            latitude: 0,
            timestamp: DateTime.utc(2026, 1, 1),
            accuracy: 5,
            altitude: 0,
            altitudeAccuracy: 1,
            heading: 0,
            headingAccuracy: 1,
            speed: speed,
            speedAccuracy: speed.isFinite ? 0.5 : double.nan,
          ),
      ];
      final fixes = await GpsSource.stream().toList();
      expect(fixes, hasLength(4));
      expect(fixes.first.speed, 0);
      expect(fixes.first.speedAccuracy, 0.5);
      expect(fixes.skip(1).every((s) => s.speed == null), isTrue);
      expect(fixes.last.speedAccuracy, isNull);
      expect(fixes.first.tsMs, DateTime.utc(2026, 1, 1).millisecondsSinceEpoch);
    },
  );
}

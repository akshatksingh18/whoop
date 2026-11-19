// Dart's iPhone permission/settings contract; no physical location acceptance.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:whoop_companion/gps/gps_source.dart';
import 'package:whoop_companion/gps/route_models.dart';

class _Geo extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requested = LocationPermission.whileInUse;
  LocationAccuracyStatus accuracy = LocationAccuracyStatus.precise;
  bool service = true, failAccuracy = false;
  int prompts = 0, accuracyReads = 0, cancellations = 0;
  LocationSettings? settings;
  late final positions = StreamController<Position>.broadcast(
    onCancel: () => cancellations++,
  );
  @override
  Future<bool> isLocationServiceEnabled() async => service;
  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    prompts++;
    return requested;
  }

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async {
    accuracyReads++;
    if (failAccuracy) throw StateError('authored accuracy reply refusal');
    return accuracy;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    settings = locationSettings;
    return positions.stream;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  late _Geo geo;
  setUp(() {
    original = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = geo = _Geo();
  });
  tearDown(() async {
    await geo.positions.close();
    GeolocatorPlatform.instance = original;
  });
  for (final permission in [
    LocationPermission.whileInUse,
    LocationPermission.always,
  ]) {
    for (final prompt in [false, true]) {
      for (final reduced in [false, true]) {
        test(
          'COV-60 iPhone ${permission.name} prompt=$prompt reduced=$reduced remains explicit',
          () async {
            geo.permission = prompt ? LocationPermission.denied : permission;
            geo.requested = permission;
            geo.accuracy = reduced
                ? LocationAccuracyStatus.reduced
                : LocationAccuracyStatus.precise;
            expect(
              await GpsSource.ensurePermission(isIOS: true),
              reduced
                  ? GpsPermissionStatus.reducedAccuracy
                  : GpsPermissionStatus.granted,
            );
            expect(geo.prompts, prompt ? 1 : 0);
            expect(geo.accuracyReads, 1);
            expect(geo.settings, isNull, reason: 'Permission is not a stream');
          },
        );
      }
    }
  }
  test(
    'COV-60 refused accuracy read stays unknown and permits a fresh reply',
    () async {
      geo.failAccuracy = true;
      expect(
        await GpsSource.ensurePermission(isIOS: true),
        GpsPermissionStatus.error,
      );
      expect(geo.accuracyReads, 1);
      geo.failAccuracy = false;
      geo.accuracy = LocationAccuracyStatus.reduced;
      expect(
        await GpsSource.ensurePermission(isIOS: true),
        GpsPermissionStatus.reducedAccuracy,
      );
      expect(geo.accuracyReads, 2);
      expect(geo.prompts, 0);
    },
  );
  test(
    'COV-60 disabled iPhone location never prompts or probes precision',
    () async {
      geo.service = false;
      geo.permission = LocationPermission.denied;
      expect(
        await GpsSource.ensurePermission(isIOS: true),
        GpsPermissionStatus.serviceOff,
      );
      expect(geo.prompts, 0);
      expect(geo.accuracyReads, 0);
      expect(geo.settings, isNull);
    },
  );
  test(
    'COV-60 iPhone stream keeps fitness background flags and releases its subscription',
    () async {
      final fixes = <GpsSample>[];
      final subscription = GpsSource.stream(isIOS: true).listen(fixes.add);
      try {
        final settings = geo.settings! as AppleSettings;
        expect(settings.accuracy, LocationAccuracy.bestForNavigation);
        expect(settings.distanceFilter, 5);
        expect(settings.activityType, ActivityType.fitness);
        expect(settings.pauseLocationUpdatesAutomatically, false);
        expect(settings.allowBackgroundLocationUpdates, true);
        expect(settings.showBackgroundLocationIndicator, true);
        final at = DateTime.utc(2021, 4, 6, 12);
        geo.positions.add(
          Position(
            longitude: 0,
            latitude: 0,
            timestamp: at,
            accuracy: 5,
            altitude: 2,
            altitudeAccuracy: 1,
            heading: 0,
            headingAccuracy: 1,
            speed: 0,
            speedAccuracy: .5,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(fixes, hasLength(1));
        expect(fixes.single.tsMs, at.millisecondsSinceEpoch);
        expect(fixes.single.speed, 0);
        expect(fixes.single.speedAccuracy, .5);
        expect(fixes.single.alt, 2);
        expect(geo.prompts, 0);
      } finally {
        await subscription.cancel();
      }
      expect(geo.cancellations, 1);
    },
  );
}

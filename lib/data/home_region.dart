// Home auto-pause for Pushups (build 86, Akshat's approval of Always
// location). One system-monitored circular region around Home, set from a
// one-shot location fix: leaving pauses a running Pushups day, arriving
// resumes only a day that leaving paused. iOS region monitoring, never
// continuous GPS; no trail of places is kept.
//
// The coordinate and radius live in this phone's preferences only. They are
// not in the database, so no backup, export or salvage ever carries them,
// and turning the feature off deletes them and stops the monitoring.
//
// Native side: `HomeRegionBridge` in ios/Runner/AppDelegate.swift. It is
// created at launch so a region event that relaunches the app is delivered,
// and it keeps events in a small durable inbox until Dart drains them.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pushups.dart' show HomeAutomation, HomePresence;

/// What the phone allows, as the bridge reports it.
class HomeRegionStatus {
  const HomeRegionStatus({
    this.authorization = 'unavailable',
    this.monitoring = false,
    this.backgroundRefresh = 'available',
    this.monitored = false,
  });

  /// notDetermined, whenInUse, always, denied, restricted or unavailable.
  final String authorization;

  /// Whether this phone can monitor regions at all.
  final bool monitoring;

  /// available, denied or restricted (Background App Refresh).
  final String backgroundRefresh;

  /// Whether the Home region is registered with the system right now.
  final bool monitored;

  /// Healthy only when every piece that delivers an event in the background
  /// is in place — a registered region alone is not enough.
  bool get healthy =>
      authorization == 'always' &&
      monitoring &&
      monitored &&
      backgroundRefresh == 'available';

  /// Why Home auto-pause would not work now, in one line; null when healthy.
  String? get problem {
    if (!monitoring) return 'This phone cannot watch a Home area.';
    if (authorization == 'denied' || authorization == 'restricted') {
      return 'Location is off for WHOOP. Turn on Always in Settings.';
    }
    if (authorization != 'always') {
      return 'Needs Always location to work while WHOOP is closed.';
    }
    if (backgroundRefresh != 'available') {
      return 'Background App Refresh is off for WHOOP.';
    }
    if (!monitored) return 'Home is not being watched. Set it again.';
    return null;
  }
}

typedef HomeBoundary = ({double lat, double lon, double radius});

class HomeRegion {
  HomeRegion._();

  static const _channel = MethodChannel('openstrap/home_region');
  static const _boundaryKey = 'pushups.home.boundary';
  static const _stateKey = 'pushups.home.state';

  /// The 150 m starting radius absorbs ordinary location jitter without
  /// covering a neighbourhood; 50 m to 1 km is allowed.
  static const defaultRadius = 150.0;
  static const minRadius = 50.0, maxRadius = 1000.0;

  /// Called with each event the bridge delivers while Dart is running.
  static void Function()? onEvent;

  static bool _listening = false;
  static void listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'event') onEvent?.call();
      return null;
    });
  }

  static Future<HomeRegionStatus> status() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('status');
      if (m == null) return const HomeRegionStatus();
      return HomeRegionStatus(
        authorization: m['authorization'] as String? ?? 'unavailable',
        monitoring: m['monitoring'] == true,
        backgroundRefresh: m['backgroundRefresh'] as String? ?? 'available',
        monitored: m['monitored'] == true,
      );
    } catch (_) {
      return const HomeRegionStatus();
    }
  }

  /// One fix of where the phone is now, asking for While-In-Use first if it
  /// has not been decided. Throws with a plain reason when there is none.
  static Future<({double lat, double lon, double accuracy})> here() async {
    final m = await _channel.invokeMapMethod<String, Object?>(
      'currentLocation',
    );
    final lat = (m?['lat'] as num?)?.toDouble();
    final lon = (m?['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      throw StateError(
        'Your location is unavailable. Check Location Services and try again.',
      );
    }
    return (
      lat: lat,
      lon: lon,
      accuracy: (m?['accuracy'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Ask iOS for Always; returns the authorization afterwards.
  static Future<String> requestAlways() async {
    try {
      return await _channel.invokeMethod<String>('requestAlways') ?? 'denied';
    } catch (_) {
      return 'denied';
    }
  }

  static Future<HomeBoundary?> boundary() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_boundaryKey);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map;
      return (
        lat: (m['lat'] as num).toDouble(),
        lon: (m['lon'] as num).toDouble(),
        radius: (m['radius'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Save Home and start watching it. Presence starts unknown; the system's
  /// first state report fills it in.
  static Future<void> setHome(HomeBoundary b) async {
    if (b.lat < -90 || b.lat > 90 || b.lon < -180 || b.lon > 180) {
      throw ArgumentError('Choose a valid Home location.');
    }
    if (b.radius < minRadius || b.radius > maxRadius) {
      throw ArgumentError('The radius is 50 m to 1 km.');
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _boundaryKey,
      jsonEncode({'lat': b.lat, 'lon': b.lon, 'radius': b.radius}),
    );
    await p.setString(_stateKey, jsonEncode(HomeAutomation().toJson()));
    await _channel.invokeMethod('monitor', {
      'lat': b.lat,
      'lon': b.lon,
      'radius': b.radius,
    });
  }

  /// Turn Home auto-pause off: stop watching and delete the place.
  static Future<void> clear() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.remove(_boundaryKey);
    await p.remove(_stateKey);
  }

  static Future<HomeAutomation> automation() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_stateKey);
      return raw == null
          ? HomeAutomation()
          : HomeAutomation.fromJson(jsonDecode(raw) as Map);
    } catch (_) {
      return HomeAutomation();
    }
  }

  static Future<void> saveAutomation(HomeAutomation a) async {
    await (await SharedPreferences.getInstance()).setString(
      _stateKey,
      jsonEncode(a.toJson()),
    );
  }

  /// Boundary events the bridge has kept since the last drain, oldest first.
  static Future<List<({HomePresence presence, DateTime at})>> drain() async {
    try {
      final list =
          await _channel.invokeListMethod<Object?>('drain') ?? const [];
      return [
        for (final e in list)
          if (e is Map && e['at'] is num)
            (
              presence: switch (e['kind']) {
                'enter' || 'inside' => HomePresence.inside,
                'exit' || 'outside' => HomePresence.outside,
                _ => HomePresence.unknown,
              },
              at: DateTime.fromMillisecondsSinceEpoch(
                ((e['at'] as num) * 1000).round(),
              ),
            ),
      ];
    } catch (_) {
      return const [];
    }
  }
}

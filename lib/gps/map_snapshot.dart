// A dark Apple Maps picture under a recorded route (iOS only).
//
// The native side (MapSnapshotBridge in AppDelegate.swift) renders a static
// MapKit snapshot around the route and reports where each route point lands
// on it as a 0…1 fraction of the image, so the route can be drawn on top in
// Flutter with the app's own colours. MapKit downloads the map tiles for that
// area from Apple; that is the only thing that leaves the phone.
//
// Anything that fails — no network, not iOS, a test — returns null and the
// screen falls back to the plain route shape.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MapSnapshot {
  final Uint8List png;

  /// Where each requested point lands on the image, 0…1 from top-left.
  final List<double> x, y;
  const MapSnapshot(this.png, this.x, this.y);
}

const _channel = MethodChannel('openstrap/map_snapshot');

/// Reuse an unchanged route/size. Corrections can change a session's track.
final _cache =
    <
      String,
      ({List<double> lat, List<double> lng, Future<MapSnapshot?> result})
    >{};

/// The most points sent to the native side. The line is drawn from these, so
/// a few hundred is plenty for a phone-width card.
const _maxPoints = 600;

/// The snapshot for [key] (a session id), or null when there is none.
/// [lat]/[lng] are thinned to [_maxPoints]; the returned x/y match the thinned
/// list, and [thinnedIndex] maps them back.
Future<MapSnapshot?> mapSnapshot(
  String key,
  List<double> lat,
  List<double> lng,
  double width,
  double height,
) {
  if (defaultTargetPlatform != TargetPlatform.iOS ||
      lat.length < 2 ||
      lat.length != lng.length ||
      !width.isFinite ||
      !height.isFinite ||
      width <= 0 ||
      height <= 0)
    return Future.value(null);
  final id = '$key@${width.round()}x${height.round()}';
  final previous = _cache[id];
  if (previous != null &&
      listEquals(previous.lat, lat) &&
      listEquals(previous.lng, lng)) {
    return previous.result;
  }
  // A caller may reuse/mutate its lists while a snapshot is being rendered.
  final latCopy = List<double>.unmodifiable(lat),
      lngCopy = List<double>.unmodifiable(lng);
  late final Future<MapSnapshot?> result;
  result = _fetch(latCopy, lngCopy, width, height).then((s) {
    if (s == null && identical(_cache[id]?.result, result)) _cache.remove(id);
    return s;
  });
  _cache[id] = (lat: latCopy, lng: lngCopy, result: result);
  return result;
}

/// Indices of the points [mapSnapshot] actually sends, for a track of [n].
List<int> thinnedIndex(int n) {
  if (n <= 0) return const [];
  final step = (n / _maxPoints).ceil().clamp(1, n);
  return [for (var i = 0; i < n; i += step) i, if ((n - 1) % step != 0) n - 1];
}

Future<MapSnapshot?> _fetch(
  List<double> lat,
  List<double> lng,
  double width,
  double height,
) async {
  final idx = thinnedIndex(lat.length);
  try {
    final r = await _channel.invokeMethod<Map>('snapshot', {
      'lat': [for (final i in idx) lat[i]],
      'lng': [for (final i in idx) lng[i]],
      'width': width,
      'height': height,
    });
    final png = r?['png'];
    final x = r?['x'], y = r?['y'];
    if (png is! Uint8List || x is! List || y is! List) return null;
    if (x.length != idx.length ||
        y.length != idx.length ||
        [...x, ...y].any((v) => v is! num || !v.isFinite))
      return null;
    return MapSnapshot(
      png,
      [for (final v in x) (v as num).toDouble()],
      [for (final v in y) (v as num).toDouble()],
    );
  } catch (_) {
    return null;
  }
}

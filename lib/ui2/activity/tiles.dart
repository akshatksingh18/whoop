// A real map under a route, as a still picture.
//
// The share card is EXPORTED — `RenderRepaintBoundary.toImage` runs once and
// whatever is on screen at that instant is what leaves the phone. An
// interactive map widget loads its tiles asynchronously and would export blank
// about as often as not, which is why this is a fetch-then-paint mosaic rather
// than `flutter_map`: every tile is awaited before anything is drawn, so the
// export is deterministic.
//
// OpenStreetMap's tile usage policy is not decoration. This file honours it:
//   · a real User-Agent naming the app and its repo (the policy's first rule);
//   · a disk cache, so a card re-rendered ten times fetches once;
//   · a hard ceiling of [_maxTiles] per card and one zoom level per card, so
//     there is no bulk download here under any input;
//   · [kOsmAttribution], which the caller MUST render on the card. Tiles
//     without the credit are a licence breach, not a design choice.
//
// The tiles are the standard raster style, which is a light map. Painting it
// under a dark card would be a white slab, so the mosaic is tinted to the
// surface it lands on — see [_themeFilter]. Tinting is a display transform of
// our own copy; it does not touch the source data or the credit.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../theme.dart';

/// Required on any card that draws [buildRouteMosaic]'s output.
const kOsmAttribution = '© OpenStreetMap contributors';

const _tileSize = 256;

/// Per card. A 1080-wide card at zoom-to-fit needs 6-12; the cap exists so a
/// pathological bounding box (a flight, a GPS glitch across a hemisphere)
/// cannot turn one share into a scrape.
const _maxTiles = 24;

const _minZoom = 2;
const _maxZoom = 17;

/// The policy's first requirement. A generic Dart user-agent is the one thing
/// guaranteed to get an app blocked.
const _userAgent =
    'OpenStrap/1.0 (+https://github.com/abdulsahil/openstrap; local-first '
    'health app; one map per shared activity card)';

/// A stitched basemap, and the route already projected onto it.
class RouteMosaic {
  /// The tiles, stitched and themed. Size is exactly [width] × [height].
  final ui.Image image;

  /// The route in [image]'s pixel space, ready for a `Path`.
  final List<Offset> path;

  final double width, height;

  const RouteMosaic(this.image, this.path, this.width, this.height);

  void dispose() => image.dispose();
}

/// Web Mercator, in tile units at [z] — the slippy-map convention, origin at
/// the top-left of the world, `2^z` tiles across.
///
/// Public because it is the one piece of arithmetic here that can be silently,
/// plausibly wrong: an error in it puts a correct-looking route in the wrong
/// country, and the only way to catch that is to pin it against known
/// coordinates. See `test/poster_map_test.dart`.
///
/// Latitude is clamped to the projection's own limit. Mercator has no poles,
/// `tan(90°)` is infinite, and the NaN that follows propagates into a Path and
/// takes the whole card down with it.
({double x, double y}) tileXY(double lat, double lng, int z) {
  final n = math.pow(2, z).toDouble();
  final clamped = lat.clamp(-85.05112878, 85.05112878);
  final rad = clamped * math.pi / 180;
  // Clamped into the grid at the end too: at exactly the latitude limit the
  // arithmetic lands 2.5e-8 the wrong side of zero, which is right to eight
  // decimal places and still a negative tile row.
  return (
    x: (lng.clamp(-180.0, 180.0) + 180) / 360 * n,
    y: ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n)
        .clamp(0.0, n),
  );
}

/// Desaturate the raster and pull it toward the card's own surface.
///
/// Two transforms, in order: drop to luminance, then map that grey onto the
/// line between [bg] and [ink]. The result reads as a map — roads, water and
/// parks keep their relative brightness — without fighting the card it sits
/// on, and it works for a light card and a dark one from the same source
/// tiles.
ColorFilter _themeFilter(Color bg, Color ink) {
  // Rec. 709 luma.
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  // out = from + luma × (to − from), per channel. `ColorFilter.matrix` rows
  // are [r, g, b, a, offset] against 0…255 inputs with a 0…255 offset, while
  // `Color.r/g/b` are 0…1 — hence the ×255 on the offset only.
  //
  // Sanity, both ends: a white source pixel has luma 1 (the three weights sum
  // to 1) and lands exactly on `to`; a black one lands exactly on `from`.
  List<double> row(double from, double to) =>
      [lr * (to - from), lg * (to - from), lb * (to - from), 0, from * 255];
  return ColorFilter.matrix(<double>[
    ...row(bg.r, ink.r),
    ...row(bg.g, ink.g),
    ...row(bg.b, ink.b),
    0, 0, 0, 1, 0,
  ]);
}

Directory? _cacheDir;

Future<File?> _cacheFile(int z, int x, int y) async {
  try {
    _cacheDir ??= Directory('${(await getTemporaryDirectory()).path}/osm_tiles')
      ..createSync(recursive: true);
    return File('${_cacheDir!.path}/${z}_${x}_$y.png');
  } catch (_) {
    // No cache directory is survivable — it means every card refetches, which
    // is slower and ruder but still correct. It is not a reason to draw no map.
    return null;
  }
}

Future<ui.Image?> _tile(int z, int x, int y, http.Client client) async {
  final f = await _cacheFile(z, x, y);
  try {
    if (f != null && f.existsSync() && f.lengthSync() > 0) {
      return await decodeImageFromList(f.readAsBytesSync());
    }
  } catch (_) {
    // A truncated cache entry (killed mid-write) is not fatal — refetch it.
  }
  try {
    final res = await client
        .get(Uri.parse('https://tile.openstreetmap.org/$z/$x/$y.png'),
            headers: const {'User-Agent': _userAgent})
        .timeout(Motion.tick * 8);
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    try {
      f?.writeAsBytesSync(res.bodyBytes);
    } catch (_) {/* cache is best-effort */}
    return await decodeImageFromList(res.bodyBytes);
  } catch (_) {
    return null;
  }
}

/// Fetch a basemap that frames [geo], and project the route onto it.
///
/// Returns null when there is no route, no network, or every tile failed —
/// and the caller must then fall back to drawing the route on its own. A
/// missing map is a plainer card; a half-loaded one is a broken picture that
/// somebody else receives.
///
/// [pad] is the fraction of the frame left around the route, so the line never
/// runs into the card's edge.
Future<RouteMosaic?> buildRouteMosaic(
  List<(double lat, double lng)> geo, {
  required int width,
  required int height,
  required Color bg,
  required Color ink,
  double pad = .12,
}) async {
  if (geo.length < 2 || width <= 0 || height <= 0) return null;

  var loLat = geo.first.$1, hiLat = loLat;
  var loLng = geo.first.$2, hiLng = loLng;
  for (final (lat, lng) in geo) {
    if (lat.isNaN || lng.isNaN) return null;
    loLat = math.min(loLat, lat);
    hiLat = math.max(hiLat, lat);
    loLng = math.min(loLng, lng);
    hiLng = math.max(hiLng, lng);
  }

  final usableW = width * (1 - pad * 2), usableH = height * (1 - pad * 2);

  // Largest zoom whose projected bounds still fit the frame, then stepped back
  // until the tile count is under the ceiling. Zoom-to-fit and a tile budget
  // are the same knob.
  var z = _maxZoom;
  for (; z > _minZoom; z--) {
    final a = tileXY(hiLat, loLng, z), b = tileXY(loLat, hiLng, z);
    final w = (b.x - a.x).abs() * _tileSize, h = (b.y - a.y).abs() * _tileSize;
    if (w <= usableW && h <= usableH) break;
  }

  // The frame, in tile units, centred on the route.
  var centre = tileXY((loLat + hiLat) / 2, (loLng + hiLng) / 2, z);
  var halfW = width / 2 / _tileSize, halfH = height / 2 / _tileSize;
  var x0 = (centre.x - halfW).floor(), x1 = (centre.x + halfW).ceil();
  var y0 = (centre.y - halfH).floor(), y1 = (centre.y + halfH).ceil();
  while ((x1 - x0) * (y1 - y0) > _maxTiles && z > _minZoom) {
    z--;
    centre = tileXY((loLat + hiLat) / 2, (loLng + hiLng) / 2, z);
    x0 = (centre.x - halfW).floor();
    x1 = (centre.x + halfW).ceil();
    y0 = (centre.y - halfH).floor();
    y1 = (centre.y + halfH).ceil();
  }

  final n = math.pow(2, z).toInt();
  final client = http.Client();
  final fetched = <(int, int), ui.Image>{};
  try {
    final jobs = <Future<void>>[];
    for (var x = x0; x < x1; x++) {
      for (var y = y0; y < y1; y++) {
        // Longitude wraps; latitude does not. An out-of-range row is empty
        // ocean off the top or bottom of the world, not a tile to ask for.
        if (y < 0 || y >= n) continue;
        final wx = x % n, wy = y;
        jobs.add(_tile(z, wx < 0 ? wx + n : wx, wy, client).then((img) {
          if (img != null) fetched[(x, y)] = img;
        }));
      }
    }
    await Future.wait(jobs);
  } finally {
    client.close();
  }
  if (fetched.isEmpty) return null;

  // Top-left of the frame in tile units, so a tile at (x, y) lands at
  // ((x - originX) * 256, (y - originY) * 256).
  final originX = centre.x - halfW, originY = centre.y - halfH;

  final rec = ui.PictureRecorder();
  final canvas = Canvas(
      rec, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));
  canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = bg);
  final paint = Paint()
    ..colorFilter = _themeFilter(bg, ink)
    ..filterQuality = FilterQuality.medium
    ..isAntiAlias = true;
  fetched.forEach((k, img) {
    final (tx, ty) = k;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH((tx - originX) * _tileSize, (ty - originY) * _tileSize,
          _tileSize.toDouble(), _tileSize.toDouble()),
      paint,
    );
  });
  final picture = rec.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  for (final img in fetched.values) {
    img.dispose();
  }

  return RouteMosaic(
    image,
    [
      for (final (lat, lng) in geo)
        () {
          final p = tileXY(lat, lng, z);
          return Offset(
              (p.x - originX) * _tileSize, (p.y - originY) * _tileSize);
        }(),
    ],
    width.toDouble(),
    height.toDouble(),
  );
}

// The basemap's failure paths, which are the ones that matter.
//
// A share card is the one screen whose output leaves the phone, so the map
// either loads completely or is not drawn at all. Every input below is one
// this has to survive without throwing, because each of them ends with the
// user tapping Share regardless.
//
// `TestWidgetsFlutterBinding` answers every HTTP request with a 400 and there
// is no `path_provider` plugin under a test binding, so this file exercises
// the no-network, no-cache path for real rather than by mocking it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/catalogue.dart';
import 'package:openstrap_edge/ui2/activity/poster.dart';
import 'package:openstrap_edge/ui2/activity/summary.dart';
import 'package:openstrap_edge/ui2/activity/tiles.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the projection', () {
    // Pinned against independently-computed slippy-map coordinates. This is
    // the one calculation here that fails PLAUSIBLY — a wrong constant still
    // draws a neat route, just somewhere the user has never been.
    test('lands on the right tile at zoom 12', () {
      for (final (name, lat, lng, x, y) in const [
        ('London', 51.5074, -0.1278, 2046.5459, 1362.0245),
        ('Sydney', -33.8688, 151.2093, 3768.4258, 2457.9779),
        ('Null Island', 0.0, 0.0, 2048.0, 2048.0),
      ]) {
        final p = tileXY(lat, lng, 12);
        expect(p.x, closeTo(x, .001), reason: name);
        expect(p.y, closeTo(y, .001), reason: name);
      }
    });

    test('the poles are clamped, not infinite', () {
      // `tan(90°)` is where a slippy map turns into a NaN.
      for (final lat in const [90.0, -90.0, 89.999]) {
        final p = tileXY(lat, 0, 12);
        expect(p.y.isFinite, isTrue, reason: 'lat \$lat');
        expect(p.y, inInclusiveRange(0, 4096));
      }
    });

    test('zoom doubles the grid', () {
      final a = tileXY(51.5074, -0.1278, 12);
      final b = tileXY(51.5074, -0.1278, 13);
      expect(b.x, closeTo(a.x * 2, .001));
      expect(b.y, closeTo(a.y * 2, .001));
    });
  });

  group('buildRouteMosaic refuses rather than throws', () {
    Future<RouteMosaic?> run(List<(double, double)> geo) => buildRouteMosaic(
          geo,
          width: 128,
          height: 64,
          bg: C.n900,
          ink: C.white,
        );

    test('fewer than two points is not a route', () async {
      expect(await run(const []), isNull);
      expect(await run(const [(51.5, -0.12)]), isNull);
    });

    test('a NaN coordinate is refused, not projected', () async {
      // Mercator has no poles and `log(tan(NaN))` is NaN — which reaches a
      // Path and takes the card down with it. Caught at the door instead.
      expect(await run(const [(double.nan, -0.12), (51.5, -0.12)]), isNull);
      expect(await run(const [(51.5, double.nan), (51.6, -0.12)]), isNull);
    });

    test('a zero-area route is still a route', () async {
      // Someone who stood still with GPS running. Bounds collapse to a point,
      // which must pick a zoom rather than divide by a zero span.
      expect(() => run(const [(51.5, -0.12), (51.5, -0.12)]),
          returnsNormally);
    });

    test('an absurd bounding box does not become a scrape', () async {
      // A GPS glitch across a hemisphere. The zoom-out loop and the tile cap
      // are the same knob, so this must terminate and stay under the ceiling
      // rather than enumerate the world.
      expect(await run(const [(-33.9, 151.2), (51.5, -0.12)]), isNull,
          reason: 'no network under a test binding — but it must ASK for few '
              'enough tiles to get there without hanging');
    });

    test('no network means no map, not a broken one', () async {
      expect(await run(const [(51.500, -0.120), (51.505, -0.118)]), isNull);
    });

    test('a zero-sized box is refused', () async {
      expect(
          await buildRouteMosaic(const [(51.5, -0.12), (51.6, -0.11)],
              width: 0, height: 64, bg: C.n900, ink: C.white),
          isNull);
    });
  });

  testWidgets('the poster draws without a basemap', (t) async {
    // The no-signal card. It must render the route on its own surface and
    // keep every number, rather than showing a hole where the map was.
    t.view.physicalSize = const Size(390 * 3, 900 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: PosterCard(_run, const {'Time', 'Pace'}),
        ),
      ),
    ));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.textContaining('12.42'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    // The credit is drawn only when tiles are — crediting OpenStreetMap for a
    // map that is not on the card would be its own small lie.
    expect(find.text(kOsmAttribution), findsNothing);
  });
}

final _run = ActivityResult(
  activityByName('Trail running')!,
  start: DateTime(2026, 8, 13, 18, 20),
  duration: Motion.tick * 3734,
  avgHr: 148,
  distanceKm: 12.42,
  route: const [Offset(.2, .8), Offset(.5, .3), Offset(.8, .7)],
  geo: const [(51.500, -0.120), (51.505, -0.118), (51.508, -0.121)],
);

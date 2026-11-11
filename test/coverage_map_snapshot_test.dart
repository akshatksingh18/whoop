// Synthetic channel responses only: no map service or actual location is used.
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/gps/map_snapshot.dart';
import 'package:image/image.dart' as img;
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/run_detail.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';

Map<String, Object> reply(int count) => {
  'png': Uint8List.fromList(img.encodePng(img.Image(width: 1, height: 1))),
  'x': List.filled(count, .5),
  'y': List.filled(count, .5),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/map_snapshot');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'a changed route under the same session cannot reuse its old map',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        return reply(((call.arguments as Map)['lat'] as List).length);
      });
      final lat = [0.0, .001], lng = [0.0, .001];
      expect(
        (await mapSnapshot('synthetic-edit', lat, lng, 300, 200))!.x,
        hasLength(2),
      );
      lat.add(.002);
      lng.add(.002);
      expect(
        (await mapSnapshot('synthetic-edit', lat, lng, 300, 200))!.x,
        hasLength(3),
      );
      lat[1] = .0005;
      await mapSnapshot('synthetic-edit', lat, lng, 300, 200);
      expect(calls, 3);
      await mapSnapshot('synthetic-edit', [...lat], [...lng], 300, 200);
      expect(
        calls,
        3,
        reason: 'unchanged coordinates still reuse the snapshot',
      );
    },
  );
  test('an older failed request cannot remove a newer cached route', () async {
    var calls = 0;
    final entered = Completer<void>(), release = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      if (calls == 1) {
        entered.complete();
        await release.future;
        throw PlatformException(code: 'synthetic_old_failure');
      }
      return reply(2);
    });
    final first = mapSnapshot(
      'synthetic-overlap',
      [0, .001],
      [0, .001],
      300,
      200,
    );
    await entered.future;
    final second = mapSnapshot(
      'synthetic-overlap',
      [0, .002],
      [0, .002],
      300,
      200,
    );
    // Releasing the first also lets the pre-fix implementation finish rather than hang.
    release.complete();
    expect(await first, isNull);
    expect(await second, isNotNull);
    await mapSnapshot('synthetic-overlap', [0, .002], [0, .002], 300, 200);
    expect(calls, 2);
  });
  test(
    'malformed projected points use the existing plain-route fallback',
    () async {
      for (final bad in [
        reply(1),
        {
          ...reply(2),
          'y': [double.nan, .5],
        },
        {
          ...reply(2),
          'x': [null, .5],
        },
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => bad);
        expect(
          await mapSnapshot(
            'synthetic-invalid-${bad.hashCode}',
            [0, .001],
            [0, .001],
            300,
            200,
          ),
          isNull,
        );
      }
    },
  );
  test('empty and single-point thinning are safe', () {
    expect(thinnedIndex(0), isEmpty);
    expect(thinnedIndex(1), [0]);
    expect(thinnedIndex(1000).last, 999);
  });
  testWidgets('a changed route hides the earlier projection while loading', (
    t,
  ) async {
    final pending = Completer<Map<String, Object>>();
    var calls = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => ++calls == 1 ? reply(2) : pending.future,
    );
    final start = DateTime(2026, 1, 1);
    ActivityResult route(int count) => ActivityResult(
      activityByName('Running')!,
      start: start,
      duration: const Duration(minutes: 1),
      sessionId: 'synthetic-widget',
      track: [
        for (var i = 0; i < count; i++)
          RoutePoint(
            seq: i,
            tsMs: start.millisecondsSinceEpoch + i * 10000,
            lat: 0,
            lng: i * .001,
          ),
      ],
    );
    Widget frame(int count) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: RunMapCard(RunView(route(count)), cursor: 1)),
    );
    await t.pumpWidget(frame(2));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await t.pumpWidget(frame(3));
    await t.pump();
    expect(find.byType(Image), findsNothing);
    expect(t.takeException(), isNull);
    pending.complete(reply(3));
    await t.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}

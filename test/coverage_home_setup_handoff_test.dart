// Authored coordinates and a fake native bridge; no real location or OS claim.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/home_region.dart';
import 'package:whoop_companion/ui2/screens/pushups_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Finder action(String s) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == s);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const bridge = MethodChannel('whoop/home_region');
  final calls = <MethodCall>[];
  var auth = 'always', failure = '', monitoring = false;
  Object? location;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('home-handoff');
  });
  setUp(() async {
    await resetCoverageStore();
    calls.clear();
    auth = 'always';
    failure = '';
    monitoring = false;
    location = <String, Object>{'lat': 0.0, 'lon': 0.0, 'accuracy': 12.0};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, (call) async {
          calls.add(call);
          if (call.method == failure) {
            throw PlatformException(
              code: 'synthetic',
              message: 'Bridge refused',
            );
          }
          return switch (call.method) {
            'status' => {
              'authorization': auth,
              'monitoring': true,
              'monitored': monitoring,
              'backgroundRefresh': 'available',
            },
            'currentLocation' => location,
            'requestAlways' => auth,
            'monitor' => monitoring = true,
            'stop' => monitoring = false,
            _ => null,
          };
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bridge, null);
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) =>
      localizedPage(t, const HomeSetupScreen(), push: true);
  Future<void> run(WidgetTester t, String s) async {
    await reveal(t, action(s));
    await invokeControl(t, t.widget<Pressable>(action(s)).onTap);
  }

  for (final permission in ['always', 'whenInUse']) {
    testWidgets('Home save retains radius and explains $permission delivery', (
      t,
    ) async {
      auth = permission;
      await open(t);
      await run(t, 'Use my current location as Home');
      expect(find.text('Located to within 12 m.'), findsOneWidget);
      await run(t, '250 metres');
      await run(t, 'Save Home');
      final saved = await t.runAsync(HomeRegion.boundary);
      expect(saved, (lat: 0.0, lon: 0.0, radius: 250.0));
      expect(calls.where((c) => c.method == 'monitor').single.arguments, {
        'lat': 0.0,
        'lon': 0.0,
        'radius': 250.0,
      });
      expect(
        find.text(permission == 'always' ? 'Working' : 'Not working'),
        findsOneWidget,
      );
      if (permission != 'always') {
        expect(
          find.textContaining('Saved, but WHOOP has location only while open.'),
          findsOneWidget,
        );
      }
      expect(action('Use my current location as Home'), findsOneWidget);
    });
  }
  testWidgets('unavailable location keeps Save absent and can retry', (
    t,
  ) async {
    location = <String, Object>{'accuracy': 12.0};
    await open(t);
    await run(t, 'Use my current location as Home');
    expect(
      find.textContaining('Your location is unavailable.'),
      findsOneWidget,
    );
    expect(action('Save Home'), findsNothing);
    location = <String, Object>{'lat': 0.0, 'lon': 0.0, 'accuracy': 8.0};
    await run(t, 'Use my current location as Home');
    expect(action('Save Home'), findsOneWidget);
    expect(await t.runAsync(HomeRegion.boundary), isNull);
  });
  testWidgets('invalid location refuses the save without an invented Home', (
    t,
  ) async {
    location = <String, Object>{'lat': 91.0, 'lon': 0.0, 'accuracy': 8.0};
    await open(t);
    await run(t, 'Use my current location as Home');
    await run(t, 'Save Home');
    expect(find.text('Choose a valid Home location.'), findsOneWidget);
    expect(await t.runAsync(HomeRegion.boundary), isNull);
    expect(calls.where((c) => c.method == 'monitor'), isEmpty);
  });
  testWidgets(
    'native monitor refusal keeps the saved boundary visibly unmonitored',
    (t) async {
      failure = 'monitor';
      await open(t);
      await run(t, 'Use my current location as Home');
      await run(t, 'Save Home');
      expect(await t.runAsync(HomeRegion.boundary), isNotNull);
      expect(find.text('Not working'), findsOneWidget);
      expect(
        find.text('Home is not being watched. Set it again.'),
        findsOneWidget,
      );
      expect(find.textContaining('Bridge refused'), findsOneWidget);
      failure = '';
      await run(t, 'Use my current location as Home');
      await run(t, 'Save Home');
      expect(find.text('Working'), findsOneWidget);
    },
  );
  for (final refuse in [false, true]) {
    testWidgets(
      'turning Home off ${refuse ? 'preserves retry state on refusal' : 'cancels then deletes'}',
      (t) async {
        await HomeRegion.setHome((lat: 0.0, lon: 0.0, radius: 150.0));
        await open(t);
        await reveal(t, action('Turn off Home auto-pause'));
        await t.tap(action('Turn off Home auto-pause'));
        await t.pumpAndSettle();
        await t.tap(find.text('Keep it'));
        await t.pumpAndSettle();
        expect(await t.runAsync(HomeRegion.boundary), isNotNull);
        if (refuse) failure = 'stop';
        await t.tap(action('Turn off Home auto-pause'));
        await t.pumpAndSettle();
        await t.tap(find.text('Turn off').last);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await t.pumpAndSettle();
        if (refuse) {
          expect(await t.runAsync(HomeRegion.boundary), isNotNull);
          expect(
            find.textContaining('Its settings are kept so you can retry.'),
            findsOneWidget,
          );
          failure = '';
          await t.tap(action('Turn off Home auto-pause'));
          await t.pumpAndSettle();
          await t.tap(find.text('Turn off').last);
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          await t.pumpAndSettle();
        }
        expect(await t.runAsync(HomeRegion.boundary), isNull);
        expect(action('Turn off Home auto-pause'), findsNothing);
        expect(monitoring, isFalse);
      },
    );
  }
}

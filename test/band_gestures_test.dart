// THE DOUBLE-TAP PICKER — and the one action that made it worth building.
//
// The whole gesture engine shipped without this screen, so the mapping could
// never leave `none`. Two things it may not get wrong:
//   * it offers ONLY what this phone reported it can do. An action drawn and
//     then silently doing nothing is worse than one never offered;
//   * when native answers with nothing, the phone actions are absent AND the
//     screen says why, rather than leaving a gap to guess at.
//
// Rendered, not read: this project has paid three times for layout faults that
// inspecting a widget tree does not find.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/gestures/gesture_dispatcher.dart';
import 'package:openstrap_edge/gestures/gesture_settings.dart';
import 'package:openstrap_edge/ui2/profile/gestures.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// What `GestureSettings.bootstrap` builds on a phone whose native side
/// answered: `none`, every in-app action, and the reported native ones.
Set<DeviceAction> _supported(Set<DeviceAction> native) => {
      DeviceAction.none,
      ...DeviceAction.values.where((a) => a.isInApp),
      ...native,
    };

Future<void> _pump(
  WidgetTester t, {
  required Set<DeviceAction> supported,
  DeviceAction chosen = DeviceAction.none,
  ValueChanged<DeviceAction>? onPick,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  t.view.physicalSize = Size(390 * 3, 2400 * 3 * scale);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        theme: buildTheme(brightness),
        home: BandGesturesView(
          chosen: chosen,
          supported: supported,
          onPick: onPick,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  group('the picker renders', () {
    testWidgets('an iPhone is offered ring and torch, never volume or Tasker',
        (t) async {
      await _pump(t,
          supported:
              _supported({DeviceAction.ringPhone, DeviceAction.torch}));

      expect(layoutFaults, isEmpty);
      expect(find.text('Ring my phone'), findsOneWidget);
      expect(find.text('Flashlight'), findsOneWidget);
      expect(find.text('Log water'), findsOneWidget);
      expect(find.text('Do nothing'), findsOneWidget);
      // Not offerable on iOS, so not drawn.
      expect(find.text('Volume up'), findsNothing);
      expect(find.text('Broadcast to Tasker'), findsNothing);
      expect(find.text('Play / pause music'), findsNothing);
    });

    testWidgets('an Android phone gets the full native list', (t) async {
      await _pump(t,
          supported: _supported({
            DeviceAction.mediaPlayPause,
            DeviceAction.mediaNext,
            DeviceAction.mediaPrev,
            DeviceAction.volumeUp,
            DeviceAction.volumeDown,
            DeviceAction.ringPhone,
            DeviceAction.torch,
            DeviceAction.broadcastToTasker,
          }));

      expect(layoutFaults, isEmpty);
      for (final label in const [
        'Play / pause music',
        'Volume up',
        'Ring my phone',
        'Broadcast to Tasker',
        'Log water',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // No "why is this missing" note when nothing is missing.
      expect(find.textContaining('could not reach the system'), findsNothing);
    });

    testWidgets('native unreachable: the in-app actions stand, and the '
        'missing ones state their reason', (t) async {
      // capabilities() returned {} — the honest answer is not a bare gap.
      await _pump(t, supported: _supported({}));

      expect(layoutFaults, isEmpty);
      expect(find.text('Ring my phone'), findsNothing);
      expect(find.text('Flashlight'), findsNothing);
      // In-app actions act on our own data, so they are unaffected.
      expect(find.text('Log water'), findsOneWidget);
      expect(find.text('Mark a moment'), findsOneWidget);
      expect(find.textContaining('could not reach the system'), findsOneWidget);
      // Absence explains itself; it is never a bare dash.
      expect(find.text('—'), findsNothing);
    });

    testWidgets('a tap reports the action it is drawn next to', (t) async {
      DeviceAction? picked;
      await _pump(t,
          supported: _supported({DeviceAction.ringPhone}),
          onPick: (a) => picked = a);

      await t.tap(find.text('Log water'));
      await t.pumpAndSettle();
      expect(picked, DeviceAction.logWater);

      await t.tap(find.text('Ring my phone'));
      await t.pumpAndSettle();
      expect(picked, DeviceAction.ringPhone);
    });

    testWidgets('nothing overflows at 3.1x, in either theme', (t) async {
      for (final b in Brightness.values) {
        await _pump(t,
            supported: _supported({DeviceAction.ringPhone, DeviceAction.torch}),
            chosen: DeviceAction.logWater,
            scale: 3.1,
            brightness: b);
        expect(layoutFaults, isEmpty, reason: '$b');
      }
    });
  });

  group('log water dispatches', () {
    GestureDispatcher build(DeviceAction mapped, {required void Function() water,
        void Function()? moment}) {
      final s = GestureSettings()..doubleTap = mapped;
      return GestureDispatcher(
        settings: s,
        onLogWater: () async => water(),
        onMarkMoment: () async => moment?.call(),
      );
    }

    int now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

    test('a live double-tap mapped to water calls the water handler', () {
      var n = 0;
      build(DeviceAction.logWater, water: () => n++).onEvent(14, now(), '');
      expect(n, 1);
    });

    test('the 2 s debounce still owns the second tap', () {
      var n = 0;
      final d = build(DeviceAction.logWater, water: () => n++);
      d.onEvent(14, now(), '');
      d.onEvent(14, now(), '');
      expect(n, 1, reason: 'one physical tap can arrive twice from the band');
    });

    test('a tap drained from flash is too old to pour a glass', () {
      var n = 0;
      build(DeviceAction.logWater, water: () => n++)
          .onEvent(14, now() - 3600, '');
      expect(n, 0);
    });

    test('water is in-app, so it is offerable with no native at all', () {
      expect(DeviceAction.logWater.isInApp, isTrue);
      expect(DeviceAction.logWater.isNative, isFalse);
      // Persisted. Changing it orphans everyone who already picked it.
      expect(DeviceAction.logWater.id, 'log_water');
      expect(DeviceActionX.fromId('log_water'), DeviceAction.logWater);
    });
  });
}

/// Layout faults are reported as caught exceptions, not failed matchers — a
/// negative margin asserting on every build still leaves a findable tree.
List<Object> get layoutFaults {
  final out = <Object>[];
  while (true) {
    final e = TestWidgetsFlutterBinding.instance.takeException();
    if (e == null) break;
    out.add(e as Object);
  }
  return out;
}

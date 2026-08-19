// THE STRAP-BUZZ RELAY, RENDERED — and the label it has to derive.
//
// The point of this screen is that the app ships a notification-listener
// permission (AndroidManifest.xml declares BIND_NOTIFICATION_LISTENER_SERVICE)
// with no way to reach the feature it exists for. So the assertions are about
// reachability and honesty rather than pixels: every state has a control or a
// reason, the permission is explained where it is asked for, and the empty app
// list says why it is empty instead of looking broken.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/notify/notification_relay.dart';
import 'package:openstrap_edge/ui2/profile/band_notifications.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Future<void> _pump(WidgetTester t, Widget w, {double scale = 1}) async {
  t.view.physicalSize = Size(390 * 3, 2400 * 3 * scale);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: MaterialApp(theme: buildTheme(Brightness.light), home: w),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('the relay screen', () {
    testWidgets('off is one tap from on, and says what it will do', (t) async {
      var toggled;
      await _pump(
        t,
        BandNotificationsView(onEnabled: (v) => toggled = v),
      );
      expect(find.text('Buzz on app notifications'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      await t.tap(find.text('Buzz on app notifications'));
      expect(toggled, isTrue);
    });

    testWidgets('on-but-ungranted asks for the permission and says why', (
      t,
    ) async {
      var asked = false;
      await _pump(
        t,
        BandNotificationsView(enabled: true, onGrant: () => asked = true),
      );
      expect(find.text('Grant notification access'), findsOneWidget);
      // The claim that has to be on the same card as the request — and it has
      // to be the TRUE one. The relay keeps the package names locally, so
      // "nothing is stored" was a promise the code did not keep.
      expect(find.textContaining('stay on this phone'), findsOneWidget);
      expect(find.textContaining('nothing leaves it'), findsOneWidget);
      await t.tap(find.text('Grant notification access'));
      expect(asked, isTrue);
    });

    testWidgets('an empty app list states its reason, not a bare emptiness', (
      t,
    ) async {
      await _pump(t, const BandNotificationsView(enabled: true, granted: true));
      expect(find.text('No app has notified you yet'), findsOneWidget);
      expect(find.textContaining('the first time each one notifies'),
          findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('each seen app is a row you can arm, with its package under it',
        (t) async {
      final calls = <(String, bool)>[];
      await _pump(
        t,
        BandNotificationsView(
          enabled: true,
          granted: true,
          apps: const [
            RelayApp('com.whatsapp', on: true),
            RelayApp('org.telegram.messenger'),
          ],
          onApp: (p, v) => calls.add((p, v)),
        ),
      );
      expect(find.text('Whatsapp'), findsOneWidget);
      expect(find.text('com.whatsapp'), findsOneWidget);
      expect(find.text('Buzzes'), findsOneWidget);
      // The count is the one number that says whether this does anything.
      expect(find.text('Apps armed'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await t.tap(find.text('Messenger'));
      expect(calls, [('org.telegram.messenger', true)]);
    });

    testWidgets('iOS gets a reason, not a dead switch', (t) async {
      await _pump(t, const BandNotificationsView(supported: false));
      expect(find.text('This phone cannot do it'), findsOneWidget);
      expect(find.text('Buzz on app notifications'), findsNothing);
    });

    testWidgets('nothing overflows at 2x text', (t) async {
      await _pump(
        t,
        const BandNotificationsView(
          enabled: true,
          granted: true,
          apps: [
            RelayApp('com.google.android.apps.messaging', on: true),
            RelayApp('com.whatsapp'),
          ],
        ),
        scale: 2,
      );
      expect(t.takeException(), isNull);
    });
  });

  group('appLabel', () {
    test('takes the last meaningful segment, capitalised', () {
      expect(appLabel('com.whatsapp'), 'Whatsapp');
      expect(appLabel('org.telegram.messenger'), 'Messenger');
      expect(appLabel('com.slack'), 'Slack');
    });

    test('steps over a platform or build segment', () {
      // "Android" under every second icon is not a name.
      expect(appLabel('com.foo.android'), 'Foo');
      expect(appLabel('com.foo.mobile.lite'), 'Foo');
    });

    test('never returns empty, whatever the package looks like', () {
      expect(appLabel('android'), 'Android');
      expect(appLabel('a'), 'A');
      expect(appLabel('com..bar.'), 'Bar');
      expect(appLabel(''), '');
    });
  });
}

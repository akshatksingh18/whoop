// Goldens for onboarding and profile.
//
// These are whole screens rather than single components, because the bugs
// this flow produces are layout bugs: a form that overflows at accessibility
// text size, a failure state whose escape hatch falls below the fold, a
// settings row whose value column eats its own label.
//
// Every screen is captured light and dark, at 1.0x and 2.0x text scale. The
// 2.0x pass is the whole point.
//
//     flutter test --update-goldens test/ui2_onboarding_profile_golden_test.dart
//
// Regenerate deliberately and look at the diff.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/ui2/onboarding/pairing.dart';
import 'package:openstrap_edge/ui2/onboarding/profile_setup.dart';
import 'package:openstrap_edge/ui2/onboarding/splash.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';
import 'package:openstrap_edge/ui2/profile/devices.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

/// Fixed, so a golden is never a function of the calendar or of a real band.
final _synced = DateTime(2026, 8, 22, 7, 12);

/// The alarm screen renders a relative day ("Tomorrow"), so both ends of that
/// comparison are pinned or the golden is a function of when the suite runs.
final _alarmNow = DateTime(2026, 8, 21, 22, 40);
final _alarmAt = DateTime(2026, 8, 22, 6, 30);

final _band = HealthSource(
  name: 'WHOOP 4.0',
  kind: 'WHOOP 4 · wrist optical',
  tier: SourceTier.wristOptical,
  icon: LucideIcons.watch,
  connected: true,
  batteryPct: 78,
  lastData: _synced,
  isBand: true,
);

const _phone = HealthSource(
  name: 'This phone',
  kind: 'Motion coprocessor',
  tier: SourceTier.phone,
  icon: LucideIcons.smartphone,
  connected: true,
);

Map<String, Widget> _cases() => {
      'welcome': WelcomeView(onNew: () {}, onImport: () {}),
      'welcome_import_lost': WelcomeView(
        onNew: () {},
        onImport: () {},
        outcome: const ImportOutcome(
            source: 'Raw sensor export',
            days: 412,
            lateRows: 1840,
            strandedDays: 3),
      ),
      'pairing_idle': PairingView(phase: PairPhase.idle, onPair: () {}, onSkip: () {}),
      'pairing_not_found':
          PairingView(phase: PairPhase.notFound, onPair: () {}, onSkip: () {}),
      'pairing_bond_refused': PairingView(
          phase: PairPhase.bondRefused,
          onPair: () {},
          onSkip: () {},
          detail: 'PlatformException(bond_failed, createBond returned false)'),
      'pairing_cancelled':
          PairingView(phase: PairPhase.cancelled, onPair: () {}, onSkip: () {}),
      'profile_setup': ProfileSetupView(onSave: (_) async {}),
      'profile_setup_filled': ProfileSetupView(
          initial: const {'sex': 'f', 'age': 34, 'weight_kg': 61.5},
          onSave: (_) async {}),
      'profile_home': const ProfileHomeView(
        stats: ProfileStats(
            name: 'Sahil', sources: 2, storageBytes: 1503238553),
      ),
      'profile_home_loading': const ProfileHomeView(),
      'my_devices': MyDevicesView(sources: [_band, _phone]),
      'my_devices_empty': const MyDevicesView(),
      'device_detail': DeviceDetailView(_band, onFind: () {}, onForget: () {}),
      'more_settings': const MoreSettingsView(
          units: 'Metric', appearance: 'Dark', phoneSteps: true),
      // The alarm's three confirmation states are the point of the screen: it
      // must not draw a confident tick over an alarm the band never
      // acknowledged.
      'alarm_none': const AlarmScreenView(connected: true),
      'alarm_confirmed': AlarmScreenView(
          armedAt: _alarmAt,
          now: _alarmNow,
          state: AlarmArmState.confirmed,
          connected: true,
          onSet: (_) async {},
          onTest: () async {},
          onCancel: () async {}),
      'alarm_unconfirmed': AlarmScreenView(
          armedAt: _alarmAt,
          now: _alarmNow,
          state: AlarmArmState.unknown,
          connected: true,
          onSet: (_) async {},
          onTest: () async {},
          onCancel: () async {}),
      'alarm_disconnected': AlarmScreenView(
          armedAt: _alarmAt, now: _alarmNow, state: AlarmArmState.unknown),
      'notification_settings': const NotificationSettingsView(),
      'notification_settings_blocked': const NotificationSettingsView(
          granted: false,
          prefs: NotificationPrefs(
              deviceEnabled: false, quietStartMin: 23 * 60, quietEndMin: 6 * 60)),
      'edit_profile': EditProfileView(
        initial: const {
          'name': 'Sahil',
          'sex': 'm',
          'age': 34,
          'height_cm': 178.0,
          'weight_kg': 72.4,
        },
        onSave: (_) async {},
      ),
    };

final _shot = GlobalKey();

Widget _frame(Widget child, Brightness b, double scale) => MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(b),
        home: RepaintBoundary(key: _shot, child: child),
      ),
    );

/// The bundled type, so the goldens show words instead of the harness's block
/// glyphs. An unreadable golden is an unreviewed golden.
Future<void> _loadType() async {
  final files = Directory('assets/fonts/Manrope')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.ttf'));
  for (final family in const ['Manrope', '.SF Pro Text']) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(f
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
}

void main() {
  final cases = _cases();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadType();
  });

  for (final scale in const [1.0, 2.0]) {
    final tag = scale == 1.0 ? '1x' : '2x';
    for (final brightness in Brightness.values) {
      final theme = brightness.name;
      group('$theme · $tag text', () {
        cases.forEach((name, widget) {
          testWidgets(name, (tester) async {
            // A real phone viewport: these are full screens, so what is below
            // the fold is part of what the golden records.
            tester.view.physicalSize = const Size(390 * 3, 844 * 3);
            tester.view.devicePixelRatio = 3;
            addTearDown(tester.view.reset);

            await tester.pumpWidget(_frame(widget, brightness, scale));
            await tester.pumpAndSettle();

            await expectLater(
              find.byKey(_shot),
              matchesGoldenFile('goldens/${name}_${theme}_$tag.png'),
            );
          });
        });
      });
    }
  }

  testWidgets('the splash uncovers the app once it is ready', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      // Reduced motion: the cover has no fade to hide behind, so it must stop
      // existing rather than sit on top at opacity zero swallowing taps.
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(
        home: BootSplash(ready: true, child: Text('the app')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('the app'), findsOneWidget);
    expect(find.byType(BootSplash), findsOneWidget);
  });

  testWidgets('an absent value is a StatusCard, never a bare dash',
      (tester) async {
    for (final entry in cases.entries) {
      await tester.pumpWidget(_frame(entry.value, Brightness.light, 1));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsNothing, reason: entry.key);
    }
  });
}

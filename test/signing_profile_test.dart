// The personal sideload's signing-expiry read and its 48 h / 24 h warnings.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_service.dart';
import 'package:openstrap_edge/platform/signing_profile.dart';

/// A provisioning profile as Sideloadly embeds it: binary CMS bytes around a
/// plain XML plist, with CreationDate BEFORE ExpirationDate.
List<int> _profile(String expiry) => [
      0x30, 0x82, 0xff, 0x00, 0x06, 0x09, // DER noise, not valid UTF-8
      ...latin1.encode('<?xml version="1.0" encoding="UTF-8"?><plist><dict>'
          '<key>CreationDate</key><date>2026-09-18T10:00:00Z</date>'
          '<key>ExpirationDate</key>\n\t<date>$expiry</date>'
          '<key>Name</key><string>WHOOP</string></dict></plist>'),
      0x00, 0xa0, 0xff,
    ];

void main() {
  group('parseProvisionExpiry', () {
    test('reads ExpirationDate, not the first date in the file', () {
      expect(parseProvisionExpiry(_profile('2026-09-25T10:00:00Z')),
          DateTime.utc(2026, 9, 25, 10));
    });

    test('anything that is not a profile is null, never a guess', () {
      expect(parseProvisionExpiry(const []), isNull);
      expect(parseProvisionExpiry(latin1.encode('<plist></plist>')), isNull);
      expect(parseProvisionExpiry(_profile('not a date')), isNull);
    });
  });

  group('signingAlertPlan', () {
    final expiry = DateTime.utc(2026, 9, 25, 10);

    test('a fresh profile arms both warnings, 48 h and 24 h before', () {
      final plan = signingAlertPlan(expiry, DateTime.utc(2026, 9, 18, 10));
      expect(plan.map((a) => a.hoursBefore), [48, 24]);
      expect(plan.first.at, DateTime.utc(2026, 9, 23, 10));
      expect(plan.last.at, DateTime.utc(2026, 9, 24, 10));
    });

    test('inside the last 48 h only the 24 h warning is still ahead', () {
      final plan = signingAlertPlan(expiry, DateTime.utc(2026, 9, 23, 12));
      expect(plan.map((a) => a.hoursBefore), [24]);
    });

    test('inside the last 24 h, or with no profile, nothing is armed', () {
      expect(signingAlertPlan(expiry, DateTime.utc(2026, 9, 24, 12)), isEmpty);
      expect(signingAlertPlan(null, DateTime.utc(2026, 9, 18)), isEmpty);
    });

    test('the OS scheduler gate lets both warnings through', () {
      expect(NotificationService.maySchedule(NotificationService.idSigningExpiry48),
          isTrue);
      expect(NotificationService.maySchedule(NotificationService.idSigningExpiry24),
          isTrue);
    });
  });
}

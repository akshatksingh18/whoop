// B88-12 (C8): each health-alert kind can be switched off on its own.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/findings.dart' show FindingKind;
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('muted health-alert kinds round-trip and default to none', () async {
    SharedPreferences.setMockInitialValues({});
    expect((await NotificationPrefs.load()).mutedFindings, isEmpty);
    await const NotificationPrefs()
        .copyWith(mutedFindings: {FindingKind.lowReadiness.name})
        .save();
    final back = await NotificationPrefs.load();
    expect(back.mutedFindings, {'lowReadiness'});
    // Other settings are untouched by a mute.
    expect(back.healthEnabled, isTrue);
  });
}

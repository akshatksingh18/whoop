import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

void main() {
  group('imuModePayload', () {
    test('gen4 stays bare on/off; gen5 prepends revision1', () {
      expect(imuModePayload(true, isGen5: false), [0x01]);
      expect(imuModePayload(false, isGen5: false), [0x00]);
      expect(imuModePayload(true, isGen5: true), [revision1, 0x01]);
      expect(imuModePayload(false, isGen5: true), [revision1, 0x00]);
    });
  });
}

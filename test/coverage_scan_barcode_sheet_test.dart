// Drive the shipped scanner sheet through the plugin's platform channels.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:whoop_companion/ui2/screens/scan_barcode.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

const camera = MethodChannel('dev.steenbakker.mobile_scanner/scanner/method');
const events = MethodChannel('dev.steenbakker.mobile_scanner/scanner/event');
const orientations = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
);

void main() {
  setUpAll(loadAuditFonts);
  final ios = TargetPlatformVariant({TargetPlatform.iOS});

  for (final mode in ['permission', 'start refusal', 'close', 'scan']) {
    testWidgets(
      'scanner $mode preserves the one-result contract',
      variant: ios,
      (t) async {
        final messenger = t.binding.defaultBinaryMessenger;
        final commands = <String>[];
        final configurations = <Map<Object?, Object?>>[];
        messenger.setMockMethodCallHandler(camera, (call) async {
          commands.add(call.method);
          switch (call.method) {
            case 'state':
              return mode == 'permission' ? 2 : 1;
            case 'request':
              return false;
            case 'start':
              configurations.add(call.arguments as Map<Object?, Object?>);
              if (mode == 'start refusal') {
                throw PlatformException(code: 'synthetic-camera-start-refused');
              }
              return {
                'cameraDirection': CameraFacing.back.rawValue,
                'textureId': 1,
                'size': {'width': 430.0, 'height': 430.0},
              };
            case 'stop':
            case 'updateScanWindow':
              return null;
            default:
              fail('Unexpected camera method ${call.method}');
          }
        });
        for (final channel in [events, orientations]) {
          messenger.setMockMethodCallHandler(channel, (call) async {
            expect(call.method, anyOf('listen', 'cancel'));
            return null;
          });
        }

        const opener = 'Open scanner test sheet';
        final results = <String?>[];
        var manual = 0;
        await localizedPage(
          t,
          Scaffold(
            body: Builder(
              builder: (c) => TextButton(
                onPressed: () async {
                  results.add(await scanBarcode(c, onManual: () => manual++));
                },
                child: const Text(opener),
              ),
            ),
          ),
        );
        await t.tap(find.text(opener));
        await t.pumpAndSettle();

        if (mode == 'permission' || mode == 'start refusal') {
          expect(
            find.text(
              mode == 'permission'
                  ? 'No camera access'
                  : 'The camera did not start',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              mode == 'permission'
                  ? 'Allow it in iPhone Settings'
                  : 'This device would not open its camera',
            ),
            findsOneWidget,
          );
          expect(
            commands,
            mode == 'permission'
                ? ['stop', 'state', 'request']
                : ['stop', 'state', 'start'],
          );
          await t.tap(find.text('Type the numbers instead'));
        } else if (mode == 'close') {
          await t.tap(
            find.byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == 'Close',
            ),
          );
        } else {
          Future<void> emit(List<String?> values) async {
            await messenger.handlePlatformMessage(
              events.name,
              const StandardMethodCodec().encodeSuccessEnvelope({
                'name': 'barcode',
                'data': [
                  for (final value in values)
                    {'format': BarcodeFormat.ean13.rawValue, 'rawValue': value},
                ],
              }),
              (_) {},
            );
          }

          await emit([null, '   ']);
          await t.pumpAndSettle();
          expect(find.byType(MobileScanner), findsOneWidget);
          expect(results, isEmpty);
          // These are authored digits. The test never performs a product lookup.
          await emit([' ', ' 2000000000015 ']);
          await emit(['2000000000022']);
        }

        await t.pumpAndSettle();
        expect(find.byType(MobileScanner), findsNothing);
        expect(find.text(opener), findsOneWidget);
        expect(results, [mode == 'scan' ? '2000000000015' : null]);
        expect(manual, mode == 'permission' || mode == 'start refusal' ? 1 : 0);
        if (configurations.isNotEmpty) {
          expect(configurations.single['returnImage'], isFalse);
          expect(configurations.single['formats'], [
            for (final format in [
              BarcodeFormat.ean13,
              BarcodeFormat.ean8,
              BarcodeFormat.upcA,
              BarcodeFormat.upcE,
              BarcodeFormat.dataBar,
              BarcodeFormat.dataBarExpanded,
            ])
              format.rawValue,
          ]);
        }
        if (mode == 'close' || mode == 'scan') {
          expect(commands.where((command) => command != 'updateScanWindow'), [
            'stop',
            'state',
            'start',
            'stop',
          ]);
        }
        expect(t.takeException(), isNull);
      },
    );
  }
}

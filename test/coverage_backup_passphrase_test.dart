// Synthetic passphrases only. No backup data, key derivation or encryption runs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/onboarding/welcome.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart';

void main() {
  setUpAll(loadAuditFonts);
  String? result;
  bool closed = false;
  Future<void> open(
    WidgetTester t, {
    bool creating = true,
    double scale = 1,
    double keyboard = 0,
  }) async {
    result = null;
    closed = false;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      RepaintBoundary(
        key: auditCaptureKey,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: w!,
          ),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await askBackupPassphrase(c, creating: creating);
                  closed = true;
                },
                child: const Text('Open backup prompt'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open backup prompt'));
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  for (final shape in ['short', 'different']) {
    testWidgets(
      'creating a backup rejects a $shape synthetic passphrase without closing',
      (t) async {
        await open(t);
        await t.enterText(
          find.byType(TextField).at(0),
          shape == 'short' ? 'short' : 'synthetic fixture',
        );
        await t.enterText(find.byType(TextField).at(1), 'different fixture');
        await t.tap(find.text('Encrypt'));
        await t.pumpAndSettle();
        expect(closed, isFalse);
        expect(
          find.text(
            shape == 'short'
                ? 'At least 8 characters.'
                : 'The two do not match.',
          ),
          findsOneWidget,
        );
        expect(
          t
              .widgetList<TextField>(find.byType(TextField))
              .every((w) => w.obscureText),
          isTrue,
        );
        await close(t);
      },
    );
  }
  testWidgets(
    'matching synthetic passphrases return exact bytes including spaces',
    (t) async {
      await open(t);
      const value = ' synthetic fixture ';
      await t.enterText(find.byType(TextField).at(0), value);
      await t.enterText(find.byType(TextField).at(1), value);
      await t.tap(find.text('Encrypt'));
      await t.pumpAndSettle();
      expect(closed, isTrue);
      expect(result, value);
      await close(t);
    },
  );
  for (final creating in [false, true]) {
    testWidgets(
      'cancelling ${creating ? 'backup creation' : 'restore'} returns no passphrase',
      (t) async {
        await open(t, creating: creating);
        await t.enterText(find.byType(TextField).first, 'synthetic fixture');
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(closed, isTrue);
        expect(result, isNull);
        await close(t);
      },
    );
  }
  testWidgets(
    'restore rejects an empty passphrase and permits an older shorter one',
    (t) async {
      await open(t, creating: false);
      await t.tap(find.text('Unlock'));
      await t.pumpAndSettle();
      expect(find.text('Enter the passphrase.'), findsOneWidget);
      expect(closed, isFalse);
      await t.enterText(find.byType(TextField), 'old');
      t.widget<TextField>(find.byType(TextField)).onSubmitted!('old');
      await t.pumpAndSettle();
      expect(result, 'old');
      await close(t);
    },
  );
  for (final creating in [false, true]) {
    for (final shape in ['keyboard', 'large text']) {
      testWidgets(
        '${creating ? 'backup' : 'restore'} prompt stays usable with $shape',
        (t) async {
          await open(
            t,
            creating: creating,
            scale: shape == 'large text' ? 3.1 : 1,
            keyboard: shape == 'keyboard' ? 320 : 0,
          );
          expect(t.takeException(), isNull);
          await captureAuditScroll(
            t,
            'passphrase_${creating ? 'create' : 'restore'}_${shape.replaceAll(' ', '_')}',
            prefix: 'coverage102',
            scrollable: find
                .descendant(
                  of: find.byWidgetPredicate(
                    (w) =>
                        w is SingleChildScrollView &&
                        w.scrollDirection == Axis.vertical,
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          final fields = find.byType(TextField);
          await t.ensureVisible(fields.first);
          await t.pumpAndSettle();
          await t.enterText(fields.first, 'synthetic fixture');
          if (creating) {
            await t.ensureVisible(fields.at(1));
            await t.pumpAndSettle();
            await t.enterText(fields.at(1), 'synthetic fixture');
          }
          final submit = find.text(creating ? 'Encrypt' : 'Unlock');
          await t.ensureVisible(submit);
          await t.pumpAndSettle();
          await t.tap(submit);
          await t.pumpAndSettle();
          expect(closed, isTrue);
          expect(result, 'synthetic fixture');
          expect(t.takeException(), isNull);
          await close(t);
        },
      );
    }
  }
}

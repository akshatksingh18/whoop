// Enter and cancel the real Settings reset confirmation; never execute a wipe.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/profile/settings.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart';

class _App extends AppState {
  _App() : super.forTesting();
  int wipes = 0;
  @override
  Future<void> resetAllData() async {
    wipes++;
  }
}

void main() {
  setUpAll(loadAuditFonts);
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets('Settings reset disclosure and Keep my data work at ${scale}x', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      final app = _App(),
          units = UnitsController.seed(UnitSystem.metric),
          theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
      addTearDown(app.dispose);
      addTearDown(units.dispose);
      addTearDown(theme.dispose);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: app),
            ChangeNotifierProvider.value(value: units),
            ChangeNotifierProvider.value(value: theme),
          ],
          child: RepaintBoundary(
            key: auditCaptureKey,
            child: MaterialApp(
              theme: buildTheme(Brightness.light),
              builder: (c, w) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: w!,
              ),
              home: const MoreSettings(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Reset all data'),
        300,
        maxScrolls: 80,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Reset all data'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('The band is unpaired'), findsOneWidget);
      final paragraph = t.renderObject<RenderParagraph>(
        find.textContaining('This deletes, permanently'),
      );
      final text = paragraph.text.toPlainText();
      final tail = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: text.length - 3,
              extentOffset: text.length,
            ),
          )
          .last;
      expect(
        tail.bottom,
        lessThanOrEqualTo(paragraph.size.height + .5),
        reason:
            'the end of the deletion disclosure must not be silently clipped inside its text box',
      );
      paragraph.showOnScreen(rect: tail.toRect());
      await t.pumpAndSettle();
      expect(
        paragraph.localToGlobal(Offset(tail.right, tail.bottom)).dy,
        lessThanOrEqualTo(844.5),
      );
      await captureAuditScroll(
        t,
        'reset_disclosure_$scale',
        prefix: 'coverage102',
        scrollable: find
            .descendant(
              of: find.byType(SingleChildScrollView),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      final keep = find.text('Keep my data');
      await t.ensureVisible(keep);
      await t.pumpAndSettle();
      await t.tap(keep);
      await t.pumpAndSettle();
      expect(find.text('Delete everything?'), findsNothing);
      expect(app.wipes, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    });
  }
}

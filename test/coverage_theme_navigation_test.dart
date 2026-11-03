// Retained ThemeController/route compatibility contracts, not a UI redesign.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/ui2/theme.dart' show buildTheme;
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/theme/theme_switcher.dart';
import 'package:whoop_companion/theme/tokens.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

class Draft extends StatefulWidget {
  const Draft({super.key});
  @override
  State<Draft> createState() => DraftState();
}

class DraftState extends State<Draft> {
  int value = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: Column(
      children: [
        Text('draft=$value'),
        TextButton(
          onPressed: () => setState(() => value++),
          child: const Text('Increment'),
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(loadAuditFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => AppColors.active = kLightPalette);
  testWidgets(
    'COV-47 retained themed navigation keeps route identity and typed draft across a real switch',
    (t) async {
      final controller = ThemeController.seed(
        AppThemeChoice.light,
        Brightness.light,
      );
      final overlay = GlobalKey<ThemeSwitchOverlayState>();
      final nav = GlobalKey<NavigatorState>();
      addTearDown(controller.dispose);
      t.view.physicalSize = const Size(430, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: Builder(
            builder: (c) {
              final theme = c.watch<ThemeController>();
              return MaterialApp(
                navigatorKey: nav,
                theme: buildTheme(Brightness.light),
                darkTheme: buildTheme(Brightness.dark),
                themeMode: theme.isDark ? ThemeMode.dark : ThemeMode.light,
                builder: (_, child) =>
                    ThemeSwitchOverlay(key: overlay, child: child!),
                home: const Scaffold(body: Text('Home')),
              );
            },
          ),
        ),
      );
      final route = themedRoute<void>(
        (_) => const Draft(),
        name: 'synthetic-draft',
      );
      expect(route, isA<MaterialPageRoute<void>>());
      expect(route.settings.name, 'synthetic-draft');
      unawaited(nav.currentState!.push(route));
      await t.pumpAndSettle();
      final state = t.state<DraftState>(find.byType(Draft));
      await t.tap(find.text('Increment'));
      await t.pumpAndSettle();
      expect(find.text('draft=1'), findsOneWidget);
      overlay.currentState!.run(
        () => unawaited(controller.setChoice(AppThemeChoice.dark)),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      expect(identical(state, t.state<DraftState>(find.byType(Draft))), true);
      expect(find.text('draft=1'), findsOneWidget);
      expect(
        Theme.of(t.element(find.byType(Draft))).brightness,
        Brightness.dark,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('theme_choice'),
        'dark',
      );
      nav.currentState!.pop();
      await t.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
    },
  );
}

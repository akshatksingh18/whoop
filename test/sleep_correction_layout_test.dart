import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/sleep_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';

void main() {
  for (final rejected in [false, true]) {
    for (final view in [(390.0, 1.0), (320.0, 2.0), (430.0, 3.1)]) {
      testWidgets(
        'corrected unknown night keeps reviewed actions at $view rejected=$rejected',
        (t) async {
          final app = AppState.forTesting();
          addTearDown(app.dispose);
          t.view.physicalSize = Size(view.$1, 2400 * view.$2);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            ChangeNotifierProvider.value(
              value: app,
              child: MaterialApp(
                theme: buildTheme(Brightness.light),
                locale: const Locale('en'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(
                    c,
                  ).copyWith(textScaler: TextScaler.linear(view.$2)),
                  child: child!,
                ),
                home: SleepDetail(
                  data: SleepData(
                    day: '2021-04-06',
                    days: const ['2021-04-06', '2021-04-05'],
                    night: {
                      'has_sleep': false,
                      'sleep_source': rejected ? 'rejected' : 'auto',
                      'sleep_correction': {
                        'action': rejected ? 'rejected' : 'clear',
                        'pending': false,
                        'usable': false,
                      },
                    },
                  ),
                ),
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('Naps'), findsOneWidget);
          expect(find.text('Breathing pattern in sleep'), findsOneWidget);
          expect(find.text('Fix sleep times'), findsNothing);
          expect(
            find.textContaining('The previous result is kept for recovery.'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Undo'),
            rejected ? findsOneWidget : findsNothing,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}

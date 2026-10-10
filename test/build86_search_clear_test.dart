// Search fields clear in one tap (build 86 follow-up): the × appears only
// while there is text, and tapping it empties the field.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/journal_compose.dart' show OsTextField;
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  testWidgets('the clear button empties a search and hides again', (t) async {
    final q = TextEditingController();
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: OsTextField(controller: q, label: 'Search', clearable: true),
      ),
    ));
    expect(find.bySemanticsLabel('Clear Search'), findsNothing);
    await t.enterText(find.byType(TextField), 'oats');
    await t.pump();
    expect(find.bySemanticsLabel('Clear Search'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Clear Search'));
    await t.pump();
    expect(q.text, isEmpty);
    expect(find.bySemanticsLabel('Clear Search'), findsNothing);
  });
}

// Actual navigation targets and primary scroll ownership; no app destinations
// are enabled solely for this check and no production layout is changed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

void main() {
  setUpAll(loadAuditFonts);
  for (final domain in ShellDomain.values) {
    testWidgets(
      '${domain.label} reselection returns its own scroll to the top and emits every repeat',
      (t) async {
        final original = shellReselect.value;
        addTearDown(() => shellReselect.value = original);
        final selected = <ShellDomain>[];
        final controllers = <ShellDomain, ScrollController>{};
        final visited = <ShellDomain>{};
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: AppShell(
              initial: domain,
              onSelect: selected.add,
              builder: (c, d) => Builder(
                builder: (inner) {
                  visited.add(d);
                  controllers[d] = PrimaryScrollController.of(inner);
                  return ListView.builder(
                    primary: true,
                    itemExtent: 60,
                    itemCount: 50,
                    itemBuilder: (_, i) => Text('${d.name} item $i'),
                  );
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(visited, {domain}, reason: 'Other tabs are still lazy');
        final own = controllers[domain]!;
        own.jumpTo(600);
        await t.pump();
        final tab = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == domain.label,
        );
        final count = shellReselect.value.$2;
        await t.tap(tab);
        await t.pumpAndSettle();
        expect(own.offset, 0);
        expect(shellReselect.value, (domain, count + 1));
        await t.tap(tab);
        await t.pumpAndSettle();
        expect(shellReselect.value, (domain, count + 2));
        expect(selected, [domain, domain]);
        final next =
            ShellDomain.values[(domain.index + 1) % ShellDomain.values.length];
        await t.tap(
          find.byWidgetPredicate(
            (w) => w is Pressable && w.semanticLabel == next.label,
          ),
        );
        await t.pumpAndSettle();
        expect(visited, {domain, next});
        expect(shellReselect.value, (
          domain,
          count + 2,
        ), reason: 'A new tab is not a reselection');
        expect(identical(controllers[domain], own), true);
        expect(identical(controllers[next], own), false);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}

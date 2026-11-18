import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whoop_companion/ble/ble_state.dart';
import 'package:whoop_companion/ble/band_status_l10n.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import 'package:whoop_companion/ui2/profile/devices.dart';
import 'package:whoop_companion/ui2/profile/profile.dart';
import 'package:whoop_companion/ui2/profile/settings.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

void main() {
  setUpAll(loadAuditFonts);
  for (final enabled in [false, true]) {
    testWidgets(
      'COV-44 localized settings retain units, privacy and explicit actions: $enabled',
      (t) async {
        var changes = 0;
        await localizedPage(
          t,
          MoreSettingsView(
            phoneSteps: enabled,
            barcodeLookup: enabled,
            devMode: enabled,
            version: '1.0.0 (1)',
            weightUnit: 'lb',
            distanceUnit: 'mi',
            heightUnit: 'ft, in',
            onCycleWeight: () => changes++,
            onToggleBarcodeLookup: () => changes++,
          ),
        );
        expect(find.text('Settings'), findsOneWidget);
        await reveal(t, find.text('Weight'));
        final weight = t.widget<SetRow>(
          find.ancestor(of: find.text('Weight'), matching: find.byType(SetRow)),
        );
        expect(weight.value, 'lb');
        weight.onTap!();
        await reveal(t, find.text('Look barcodes up online'));
        final barcode = t.widget<SetRow>(
          find.ancestor(
            of: find.text('Look barcodes up online'),
            matching: find.byType(SetRow),
          ),
        );
        expect(barcode.value, enabled ? 'On' : 'Off');
        barcode.onTap!();
        expect(changes, 2);
        await reveal(t, find.text('Reset all data'));
        expect(find.text('Reset all data'), findsOneWidget);
      },
    );
  }
  for (final loaded in [false, true]) {
    testWidgets(
      'COV-44 localized notification permission and switches stay honest: $loaded',
      (t) async {
        NotificationPrefs? selected;
        var requested = 0;
        await localizedPage(
          t,
          NotificationSettingsView(
            loaded: loaded,
            granted: false,
            onRequestPermission: () => requested++,
            onChanged: (p) async => selected = p,
          ),
        );
        expect(find.text('Notifications'), findsOneWidget);
        if (loaded) {
          final content = (await readPage(t)).join(' ');
          expect(content, contains('Quiet hours'));
          t
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await t.pumpAndSettle();
          final rows = t.widgetList<SetRow>(find.byType(SetRow));
          final interactive = rows.where((r) => r.onTap != null).toList();
          expect(interactive, isNotEmpty);
          // The rendered master switch changes a typed preference, not OS permission.
          interactive.first.onTap!();
          expect(selected, isNotNull);
          expect(requested, 0);
        }
      },
    );
  }
  for (final condition in BandCondition.values) {
    testWidgets(
      'COV-44 localized band condition keeps fault and repair provenance: $condition',
      (t) async {
        late BandStatus rendered;
        await localizedPage(
          t,
          Scaffold(
            body: Builder(
              builder: (c) {
                rendered = localizedBandStatus(
                  c,
                  BandStatus(
                    condition,
                    'original title',
                    'original reason',
                    fix: 'original fix',
                    bondRefusals: 3,
                  ),
                );
                return Text(rendered.title);
              },
            ),
          ),
        );
        expect(rendered.condition, condition);
        expect(rendered.title, isNot('original title'));
        expect(rendered.reason, isNotEmpty);
        expect(
          rendered.isFault,
          ![
            BandCondition.connected,
            BandCondition.connecting,
            BandCondition.scanning,
            BandCondition.disconnected,
          ].contains(condition),
        );
        if (condition == BandCondition.reconnectPaused) {
          expect(rendered.bondRefusals, 3);
          expect(rendered.reason, contains('3'));
          expect(rendered.fix, isNotEmpty);
        }
      },
    );
  }
  for (final connected in [false, true]) {
    testWidgets(
      'COV-44 localized phone source cannot imply a paired band: $connected',
      (t) async {
        var paired = 0;
        await localizedPage(
          t,
          MyDevicesView(
            sources: [
              HealthSource(
                name: 'Synthetic phone',
                kind: 'Phone',
                tier: SourceTier.phone,
                icon: LucideIcons.smartphone,
                connected: connected,
              ),
            ],
            onPair: () => paired++,
          ),
        );
        expect(find.text('Synthetic phone'), findsOneWidget);
        expect(
          find.text(connected ? 'Reporting steps' : 'No steps arriving'),
          findsOneWidget,
        );
        final card = t.widget<StatusCard>(find.byType(StatusCard));
        expect(card.fix, 'Pair a band');
        card.onFix!();
        expect(paired, 1);
      },
    );
  }
  final outcomes = [
    const ImportOutcome(source: 'Synthetic', error: 'synthetic read refusal'),
    const ImportOutcome(source: 'Synthetic'),
    const ImportOutcome(source: 'Synthetic', rejectedRows: ['line 1 refused']),
    const ImportOutcome(
      source: 'Synthetic',
      days: 1,
      workouts: 2,
      skippedDays: 3,
      journalRows: 2,
      records: 4,
      lateRows: 5,
      strandedDays: 2,
      corruptTables: {'synthetic_table'},
      rejectedRows: ['line 2 refused'],
      readError: 'synthetic partial read',
      rollupError: 'synthetic rollup refusal',
    ),
    const ImportOutcome(source: 'Synthetic', workouts: 1),
    const ImportOutcome(source: 'Synthetic', records: 2),
    const ImportOutcome(source: 'Synthetic', journalRows: 1),
  ];
  for (var i = 0; i < outcomes.length; i++) {
    testWidgets(
      'COV-44 localized import report distinguishes committed, absent and refused inputs: $i',
      (t) async {
        final o = outcomes[i];
        await localizedPage(
          t,
          Scaffold(body: SingleChildScrollView(child: ImportReport(o))),
        );
        final cards = t
            .widgetList<StatusCard>(find.byType(StatusCard))
            .toList();
        if (o.error != null || o.nothingLanded) {
          expect(cards, hasLength(1));
          expect(cards.single.fix, 'Try another file');
          expect(
            cards.single.why,
            contains(
              o.error ?? (o.rejectedRows.isNotEmpty ? 'refused' : 'nothing'),
            ),
          );
        } else if (i == 3) {
          expect(cards, hasLength(4));
          expect(
            cards.map((c) => c.why).join(' '),
            contains('synthetic_table'),
          );
          expect(cards.map((c) => c.why).join(' '), contains('line 2 refused'));
        } else {
          expect(cards, isEmpty);
        }
      },
    );
  }
  for (final family in [null, 'whoop4', 'whoop5', 'unknown']) {
    for (final connected in [false, true]) {
      testWidgets(
        'COV-44 localized device detail retains source limits $family $connected',
        (t) async {
          var calls = 0;
          final source = HealthSource(
            name: 'Synthetic band',
            kind: 'Wrist optical',
            tier: SourceTier.wristOptical,
            icon: LucideIcons.watch,
            isBand: true,
            family: family,
            connected: connected,
            batteryPct: connected ? 42 : null,
            lastData: connected ? DateTime(2021, 4, 6, 12) : null,
          );
          await localizedPage(
            t,
            DeviceDetailView(
              source,
              liveHr: connected ? 60 : null,
              onRename: connected ? () => calls++ : null,
              onFind: connected ? () => calls++ : null,
              health: connected
                  ? {'charge_cycles': 2, 'full_charge_mv': 4180}
                  : null,
            ),
          );
          final content = (await readPage(t)).join(' ');
          expect(content, contains('Synthetic band'));
          expect(content, contains('Calibration'));
          if (connected) {
            expect(content, contains('42%'));
            expect(content, contains('60 bpm'));
            expect(content, contains('2 charges logged'));
          } else
            expect(content, contains('Not reported since the last connection'));
          if (family == null || family == 'unknown')
            expect(content, contains('Not stated yet'));
          if (family == 'whoop5' || family == 'unknown')
            expect(content, contains('Experimental'));
          expect(calls, 0);
        },
      );
    }
  }
  for (final busy in [false, true]) {
    testWidgets(
      'COV-44 localized welcome disables both choices while busy $busy',
      (t) async {
        var calls = 0;
        await localizedPage(
          t,
          WelcomeView(
            busy: busy,
            onNew: () => calls++,
            onImport: () => calls++,
          ),
          settle: !busy,
        );
        final buttons = t
            .widgetList<BigButton>(find.byType(BigButton))
            .toList();
        expect(buttons, hasLength(2));
        for (final b in buttons) {
          expect(b.onTap == null, busy);
          if (b.onTap != null) b.onTap!();
        }
        expect(calls, busy ? 0 : 2);
      },
    );
  }
  for (final commit in [false, true]) {
    testWidgets(
      'COV-44 notification quiet-time ${commit ? 'confirmation' : 'cancel'} retains typed policy',
      (t) async {
        NotificationPrefs? changed;
        await localizedPage(
          t,
          NotificationSettingsView(
            loaded: true,
            granted: true,
            onChanged: (p) async => changed = p,
          ),
        );
        final label = find.text('Starts');
        await reveal(t, label);
        final row = find.ancestor(of: label, matching: find.byType(SetRow));
        t.widget<SetRow>(row).onTap!();
        await t.pumpAndSettle();
        await t.tap(find.text(commit ? 'OK' : 'Cancel'));
        await t.pumpAndSettle();
        if (commit) {
          expect(changed!.quietStartMin, 22 * 60);
          expect(changed!.quietEndMin, 7 * 60);
          expect(changed!.quietEnabled, true);
        } else
          expect(changed, isNull);
      },
    );
  }
}

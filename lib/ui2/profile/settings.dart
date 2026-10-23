// Settings, and editing the profile.
//
// Two deliberate departures from the reference design:
//
//   · "Log out" is "Reset all data". Logging out of an app with no server is
//     theatre — it clears a session that does not exist while leaving every
//     byte on disk. The destructive action here is the honest one, and it says
//     what it destroys.
//   · Email, username, bio, location and date of birth are gone from the edit
//     form. None of them feed a metric, and a field that changes nothing is a
//     field that implies an account.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/auto_backup.dart';
import '../../data/body_log.dart' show BodyLogDb;
import '../../compute/findings.dart' show FindingKind;
import '../../data/off_lookup.dart';
import '../../l10n/app_localizations.dart';
import '../../notify/notification_prefs.dart';
import '../../notify/notification_service.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../state/units_controller.dart';
import '../../theme/theme_controller.dart';
import '../ui2.dart';
import '../activity/live.dart' show LiveDraft;
import 'alarm.dart';
import 'data.dart';
import 'devices.dart';
import 'status.dart';
import 'gallery.dart';
import 'profile.dart';

/// Unwind the profile stack back to the gate.
///
/// `_Gate` is `MaterialApp.home` — the BOTTOM of the navigator stack — so an
/// action that changes `AppState.route` swaps what is under everything without
/// popping any of it. Resetting all data, forgetting the band and asking to
/// pair again are all route changes taken from a pushed screen, and all three
/// used to leave the user staring at the screen they tapped from, describing a
/// state that no longer existed.
void backToRoot(BuildContext c) => Navigator.of(c).popUntil((r) => r.isFirst);

// ══════════════════ MORE SETTINGS ══════════════════

/// Taps on the version row that reveal the developer group. The conventional
/// gesture, for the conventional reason: it is discoverable by anyone who
/// already knows it and invisible to everyone else.
const kDevTaps = 7;

class MoreSettings extends StatefulWidget {
  const MoreSettings({super.key});

  @override
  State<MoreSettings> createState() => _MoreSettingsState();
}

class _MoreSettingsState extends State<MoreSettings> {
  bool _dev = Prefs.getBool(Prefs.devMode, false);

  /// Whether a food barcode may be looked up online. Not on AppState: it is a
  /// screen-local preference like the map basemap's, read straight off Prefs.
  bool _barcode = offLookupAllowed;
  String _version = '';
  int _taps = 0;

  @override
  void initState() {
    super.initState();
    _readVersion();
  }

  Future<void> _readVersion() async {
    try {
      final i = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = '${i.version} (${i.buildNumber})');
    } catch (_) {
      /* no version, no row — and no way in */
    }
  }

  void _tapVersion() {
    if (_dev || ++_taps < kDevTaps) return;
    _setDev(true);
  }

  /// The one preference here that is awaited. A revocation that never reached
  /// storage is back ON at the next launch, so it does not get to fail quietly
  /// — the switch still moves (in-session it really is off, nothing is sent),
  /// and the person is told it did not stick.
  Future<void> _toggleBarcode(BuildContext c) async {
    final want = !_barcode;
    final messenger = ScaffoldMessenger.of(c);
    final saved = await setOffLookupAllowed(want);
    if (!mounted) return;
    setState(() => _barcode = want);
    if (!saved) {
      final l = AppLocalizations.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l?.settingsBarcodeSaveFailed ??
                'That could not be saved — it may be back next time you '
                    'open the app.',
          ),
        ),
      );
    }
  }

  void _setDev(bool on) {
    Prefs.setBool(Prefs.devMode, on);
    setState(() {
      _dev = on;
      _taps = 0;
    });
  }

  Future<void> _setting(Future<dynamic> Function() write) async {
    try {
      await write();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not save that setting. Try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final units = c.watch<UnitsController>();
    final theme = c.watch<ThemeController>();
    return MoreSettingsView(
      version: _version,
      devMode: _dev,
      onVersionTap: _tapVersion,
      onToggleDev: () => _setDev(false),
      onGallery: () => goto(c, const GalleryScreen()),
      weightUnit: units.weightUnit,
      distanceUnit: units.distanceUnit,
      heightUnit: units.heightUnit == HeightUnit.ftIn ? 'ft, in' : 'cm',
      appearance: theme.choice.label,
      phoneSteps: app.phoneStepsEnabled,
      barcodeLookup: _barcode,
      onEditProfile: () => goto(c, const EditProfile()),
      onDevices: () => goto(c, const MyDevices()),
      onAlarm: () => goto(c, const AlarmScreen()),
      onNotifications: () => goto(c, const NotificationSettings()),
      onData: () => goto(c, const DataScreen()),
      onCycleWeight: () =>
          _setting(() => units.setWeightUnit(units.isLb ? 'kg' : 'lb')),
      onCycleDistance: () =>
          _setting(() => units.setDistanceUnit(units.isMiles ? 'km' : 'mi')),
      onCycleHeight: () => _setting(
        () => units.setHeightUnit(
          units.heightUnit == HeightUnit.ftIn ? HeightUnit.cm : HeightUnit.ftIn,
        ),
      ),
      onCycleAppearance: () => theme.setChoice(
        AppThemeChoice.values[(theme.choice.index + 1) %
            AppThemeChoice.values.length],
      ),
      onTogglePhoneSteps: () => _setting(
        () => app.phoneStepsEnabled
            ? app.disablePhoneSteps()
            : app.requestPhoneSteps(),
      ),
      onToggleBarcodeLookup: () => _toggleBarcode(c),
      onReset: () => _confirmReset(c, app),
    );
  }
}

Future<void> _confirmReset(BuildContext c, AppState app) async {
  final l = AppLocalizations.of(c);
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(l?.settingsResetTitle ?? 'Delete everything?'),
      // Names what this app holds; the wipe below removes all of it.
      content: Text(
        l?.settingsResetBody ??
            'This deletes, permanently and with no copy anywhere else:\n\n'
                '· every measured day, sleep, nap, workout and route\n'
                '· your food log, saved foods and meals\n'
                '· Body weights, tape measurements and progress photos\n'
                '· Lift Log sets and splits, and Pushups history\n'
                '· your profile, goal, every preference and every scheduled '
                'reminder\n'
                '· automatic backups kept on this phone\n\n'
                'The band is unpaired, and it cannot re-send history it has already '
                'handed over. Export from Your data first if you want a copy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(d).pop(false),
          child: Text(l?.settingsResetKeepData ?? 'Keep my data'),
        ),
        TextButton(
          onPressed: () => Navigator.of(d).pop(true),
          child: Text(l?.settingsResetDeleteEverything ?? 'Delete everything'),
        ),
      ],
    ),
  );
  if (ok != true) return;
  while (true) {
    try {
      await app.resetAllData();
      break;
    } catch (_) {
      if (!c.mounted) return;
      final retry = await showDialog<bool>(
        context: c,
        builder: (d) => AlertDialog(
          scrollable: true,
          title: const Text('Reset did not finish'),
          content: const Text(
            'Some data may already be deleted. Settings, reminders, the saved backup passphrase or device cleanup did not finish. Retry to complete deletion.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Retry reset'),
            ),
          ],
        ),
      );
      if (retry != true) return;
    }
  }
  // The live screen's draft is UI state AppState cannot reach.
  LiveDraft.clear();
  // "with no copy anywhere else" was false while automatic backup was on:
  // `wipeAll` deletes rows and cannot touch files, so up to [kBackupsKept]
  // gzipped whole-database copies survived in a folder the user can browse and
  // Import a file can read straight back.
  // `pruneBackups` swallows per-file failures, so check what is left rather
  // than assume the folder is empty: a permission/storage error must not be
  // reported as "no copy remains" (B86-12).
  while (true) {
    var left = 0;
    try {
      final dir = await backupDirectory();
      await pruneBackups(dir, keep: 0);
      left = sortBackupsNewestFirst(dir.listSync()).length;
      // Progress photos are files, not rows (build 86): the wipe cannot
      // reach them, so they go here and are counted if any remain.
      final photos = await BodyLogDb.photoDir();
      for (final f in photos.listSync().whereType<File>()) {
        try {
          await f.delete();
        } catch (_) {}
      }
      left += photos.listSync().whereType<File>().length;
    } catch (_) {
      left = -1;
    }
    if (left == 0 || !c.mounted) break;
    final retry = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Some files were not deleted'),
        content: Text(
          left > 0
              ? 'Your data was deleted, but $left backup or photo '
                    '${left == 1 ? 'file' : 'files'} could not be removed.'
              : 'Your data was deleted, but the automatic backup folder '
                    'could not be checked, so a copy may remain.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Leave them'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
    if (retry != true) break;
  }
  // resetAllData swaps the gate to Welcome, which is UNDER this screen —
  // without this the user stays on Settings, reading a profile that has been
  // deleted.
  if (c.mounted) backToRoot(c);
}

class MoreSettingsView extends StatelessWidget {
  /// 'kg' / 'lb', 'km' / 'mi', 'cm' / 'ft, in'.
  final String weightUnit, distanceUnit, heightUnit;
  final String appearance;
  final bool phoneSteps, barcodeLookup;

  /// `0.9.26 (57)`, or empty until package_info answers — the About group is
  /// the whole reveal gesture, so it is not drawn against a blank.
  final String version;

  /// Off by default and off on every fresh install. The group it gates is not
  /// a feature: nothing in it is for anyone who has not deliberately asked.
  final bool devMode;

  final VoidCallback? onVersionTap, onToggleDev, onGallery;

  final VoidCallback? onEditProfile,
      onDevices,
      onAlarm,
      onNotifications,
      onData,
      onCycleWeight,
      onCycleDistance,
      onCycleHeight,
      onCycleAppearance,
      onTogglePhoneSteps,
      onToggleBarcodeLookup,
      onReset;

  const MoreSettingsView({
    super.key,
    this.weightUnit = 'kg',
    this.distanceUnit = 'km',
    this.heightUnit = 'cm',
    this.appearance = 'System',
    this.phoneSteps = false,
    this.barcodeLookup = true,
    this.version = '',
    this.devMode = false,
    this.onVersionTap,
    this.onToggleDev,
    this.onGallery,
    this.onEditProfile,
    this.onDevices,
    this.onAlarm,
    this.onNotifications,
    this.onData,
    this.onCycleWeight,
    this.onCycleDistance,
    this.onCycleHeight,
    this.onCycleAppearance,
    this.onTogglePhoneSteps,
    this.onToggleBarcodeLookup,
    this.onReset,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final on = l?.stateOn ?? 'On';
    final off = l?.stateOff ?? 'Off';
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(l?.settingsNavTitle ?? 'Settings'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  settingsGroup(c, l?.settingsGroupTheBand ?? 'The band', [
                    SetRow(
                      LucideIcons.watch,
                      C.blue,
                      'My band',
                      sub: 'Battery, sync and pairing',
                      onTap: onDevices,
                    ),
                    SetRow(
                      LucideIcons.userPen,
                      C.purple,
                      'Profile',
                      sub: 'Sex, age, height, weight',
                      onTap: onEditProfile,
                    ),
                    SetRow(
                      LucideIcons.alarmClock,
                      C.orange,
                      l?.settingsAlarmRowTitle ?? 'Alarm',
                      sub:
                          l?.settingsAlarmRowSub ??
                          'Buzzes on your wrist, on the band’s own clock',
                      onTap: onAlarm,
                    ),
                  ]),
                  // NOT in Preferences. Units and Appearance change how numbers
                  // are drawn; this one asks the OS for a sensor and decides
                  // where a measurement comes from. Its own group, next to the
                  // band, because the two together are the step ladder — the
                  // band covers the workout, the phone covers the rest — and
                  // "This phone" is what the sources screen already calls it.
                  settingsGroup(c, l?.settingsGroupThisPhone ?? 'This phone', [
                    SetRow(
                      LucideIcons.footprints,
                      C.teal,
                      l?.settingsStepsRowTitle ?? 'Steps',
                      // Steps are counted on the phone only.
                      sub:
                          l?.settingsStepsRowSubPhoneOnly ??
                          'This phone’s step counter is the only source '
                              'of steps. Time without the phone has none. '
                              'Nothing leaves the device',
                      value: phoneSteps ? on : off,
                      onTap: onTogglePhoneSteps,
                    ),
                  ]),
                  settingsGroup(
                    c,
                    l?.settingsGroupNotifications ?? 'Notifications',
                    [
                      SetRow(
                        LucideIcons.bell,
                        C.blue,
                        l?.settingsManageNotificationsRowTitle ??
                            'Manage notifications',
                        sub:
                            l?.settingsManageNotificationsRowSub ??
                            'What may interrupt you, quiet hours, and off '
                                'switches for all of them',
                        onTap: onNotifications,
                      ),
                    ],
                  ),
                  // Build 95: one choice per measure. Weight is the unit Body,
                  // Today, Food, Progress and the profile all use.
                  settingsGroup(c, l?.settingsUnitsRowTitle ?? 'Units', [
                    SetRow(
                      LucideIcons.scale,
                      C.body,
                      l?.settingsWeightUnitRow ?? 'Weight',
                      value: weightUnit,
                      onTap: onCycleWeight,
                    ),
                    SetRow(
                      LucideIcons.route,
                      C.blue,
                      l?.settingsDistanceUnitRow ?? 'Distance',
                      sub:
                          l?.settingsDistanceUnitSub ??
                          'Workouts, pace, splits and spoken updates',
                      value: distanceUnit,
                      onTap: onCycleDistance,
                    ),
                    SetRow(
                      LucideIcons.ruler,
                      C.teal,
                      l?.settingsHeightUnitRow ?? 'Height',
                      value: heightUnit,
                      onTap: onCycleHeight,
                    ),
                  ]),
                  settingsGroup(c, l?.settingsGroupYourData ?? 'Your data', [
                    SetRow(
                      LucideIcons.download,
                      C.green,
                      l?.settingsExportBackupImportRowTitle ??
                          'Export, backup, import',
                      sub:
                          l?.settingsExportBackupImportRowSub ??
                          'Spreadsheets, a full copy, and bringing history in',
                      onTap: onData,
                    ),
                  ]),
                  settingsGroup(c, l?.settingsGroupPrivacy ?? 'Privacy', [
                    // The food log's one outbound call. Named by what it sends,
                    // not by the feature it powers — a scan is the only thing
                    // that triggers it and the barcode is the whole payload.
                    SetRow(
                      LucideIcons.scanBarcode,
                      C.domFood,
                      l?.settingsBarcodeLookupRowTitle ??
                          'Look barcodes up online',
                      sub:
                          l?.settingsBarcodeLookupRowSub ??
                          'Sends a scanned barcode to openfoodfacts.org. '
                              'Nothing about you goes with it',
                      value: barcodeLookup ? on : off,
                      onTap: onToggleBarcodeLookup,
                    ),
                  ]),
                  settingsGroup(c, l?.settingsGroupAbout ?? 'About', [
                    // Signing expiry, newest band data, last backup, build and
                    // source — the facts that decide whether this install keeps
                    // working, in one place.
                    SetRow(
                      LucideIcons.activity,
                      C.green,
                      'Status',
                      sub: 'Signing, sync, backup and build',
                      onTap: () => goto(c, const StatusScreen()),
                    ),
                    if (version.isNotEmpty)
                      SetRow(
                        LucideIcons.info,
                        C.n500,
                        l?.settingsVersionRowTitle ?? 'Version',
                        value: version,
                        chevron: false,
                        onTap: onVersionTap,
                      ),
                    // Where the licences of what this app uses are written out
                    // in full. Open Food Facts' ODbL asks for the notice to be
                    // reachable, not only for the credit beside the numbers.
                    SetRow(
                      LucideIcons.scale,
                      C.n500,
                      l?.settingsNoticesLicencesRowTitle ??
                          'Notices and licences',
                      sub:
                          l?.settingsNoticesLicencesRowSub ??
                          'Who this app is not, and whose data it uses',
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://github.com/akshatksingh18/whoop/blob/main/NOTICE.md',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ]),
                  if (devMode)
                    settingsGroup(c, l?.settingsGroupDeveloper ?? 'Developer', [
                      SetRow(
                        LucideIcons.layoutGrid,
                        C.purple,
                        l?.settingsComponentGalleryRowTitle ??
                            'Component gallery',
                        sub:
                            l?.settingsComponentGalleryRowSub ??
                            'Every component, at any text scale, in either '
                                'theme',
                        onTap: onGallery,
                      ),
                      SetRow(
                        LucideIcons.code,
                        C.n500,
                        l?.settingsDeveloperModeRowTitle ?? 'Developer mode',
                        value: on,
                        chevron: false,
                        onTap: onToggleDev,
                      ),
                    ]),
                  const SizedBox(height: S.x6),
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: SetRow(
                      LucideIcons.trash2,
                      C.red,
                      l?.settingsResetAllDataRowTitle ?? 'Reset all data',
                      danger: true,
                      chevron: false,
                      onTap: onReset,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════ NOTIFICATIONS ══════════════════
//
// Every kind of notification this app can send has its own switch here, plus
// quiet hours. The alarm is the exception: its off switch is cancelling it on
// the Alarm screen, so it cannot be silenced by accident.

class NotificationSettings extends StatefulWidget {
  const NotificationSettings({super.key});

  @override
  State<NotificationSettings> createState() => _NotificationSettingsState();
}

class _NotificationSettingsState extends State<NotificationSettings>
    with WidgetsBindingObserver {
  NotificationPrefs? _prefs;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Build 92 (Codex audit concern 1): permission granted or revoked in iOS
  /// Settings while this screen stayed open is read again on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    NotificationService.instance.hasPermission().then((g) {
      if (mounted && g != _granted) setState(() => _granted = g);
    }, onError: (_) {});
  }

  Future<void> _load() async {
    final p = await NotificationPrefs.load();
    final granted = await NotificationService.instance.hasPermission();
    if (!mounted) return;
    setState(() {
      _prefs = p;
      _granted = granted;
    });
  }

  Future<void> _apply(NotificationPrefs next) async {
    final before = _prefs;
    setState(() => _prefs = next);
    try {
      await next.save();
    } catch (_) {
      // Build 92: a switch that did not save goes back, and says so.
      if (!mounted) return;
      if (identical(_prefs, next)) setState(() => _prefs = before);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not save that setting. Try again.'),
        ),
      );
      return;
    }
    // Re-run the scheduler so a switch that was just turned off actually
    // cancels what it was standing for, rather than taking effect at some
    // later resume. Through AppState, which reads the week the lookback
    // summarises.
    if (mounted) await context.read<AppState>().refreshReminders();
    // the low-battery threshold is restored once per process — push the new
    // value into the alert pipeline or it applies only after a restart.
    if (mounted) {
      await context.read<AppState>().refreshBatteryThreshold(next);
    }
  }

  /// The one contextual moment left where prompting is honest: the user is
  /// standing in the notifications screen, having just asked for one.
  Future<void> _requestPermission() async {
    final ok = await NotificationService.instance.ensurePermission();
    if (mounted) setState(() => _granted = ok);
    // Build 93 (Codex full-flow audit F11): once denied, iOS never asks
    // again, so the button opens this app's page in iPhone Settings; the
    // permission is read again on return (didChangeAppLifecycleState).
    if (!ok) {
      try {
        await Geolocator.openAppSettings();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = _prefs;
    return NotificationSettingsView(
      prefs: p ?? const NotificationPrefs(),
      loaded: p != null,
      granted: _granted,
      onChanged: _apply,
      onRequestPermission: _requestPermission,
    );
  }
}

class NotificationSettingsView extends StatelessWidget {
  final NotificationPrefs prefs;
  final bool loaded, granted;

  final Future<void> Function(NotificationPrefs next)? onChanged;
  final VoidCallback? onRequestPermission;

  const NotificationSettingsView({
    super.key,
    this.prefs = const NotificationPrefs(),
    this.loaded = true,
    this.granted = true,
    this.onChanged,
    this.onRequestPermission,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final on = l?.stateOn ?? 'On';
    final off = l?.stateOff ?? 'Off';
    void set(NotificationPrefs next) => onChanged?.call(next);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                l?.settingsNotificationsNavTitle ?? 'Notifications',
                sub: l?.settingsNotificationsNavSub ?? 'WHAT MAY INTERRUPT YOU',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  if (!granted)
                    StatusCard(
                      l?.settingsNotificationsOffSystemTitle ??
                          'Notifications are off at the system level',
                      l?.settingsNotificationsOffSystemBody ??
                          'Nothing below can reach you until the OS lets it.',
                      fix: l?.settingsTurnThemOn ?? 'Turn them on',
                      icon: LucideIcons.bellOff,
                      onFix: onRequestPermission,
                    ),
                  if (loaded) ...[
                    settingsGroup(
                      c,
                      l?.settingsGroupManageNotifications ??
                          'Manage notifications',
                      [
                        SetRow(
                          LucideIcons.heartPulse,
                          C.red,
                          l?.settingsHealthExceptionsRowTitle ??
                              'Health exceptions',
                          sub:
                              l?.settingsHealthExceptionsRowSub ??
                              'One a day at most, and only when something in '
                                  'your own baseline moved',
                          value: prefs.healthEnabled ? on : off,
                          chevron: false,
                          onTap: () => set(
                            prefs.copyWith(healthEnabled: !prefs.healthEnabled),
                          ),
                        ),
                        // B88-12 (C8): each health-alert kind on or off. A
                        // muted kind stays in the in-app findings log. The
                        // irregular-rhythm screen never pushes (C1), and the
                        // temperature kind only exists where skin temperature
                        // is shown.
                        if (prefs.healthEnabled)
                          for (final (kind, title) in [
                            (FindingKind.illness, 'Possible illness onset'),
                            (FindingKind.anomaly, 'Unusual night'),
                            (FindingKind.lowReadiness, 'Low readiness'),
                            (FindingKind.rhrShift, 'Resting heart-rate shift'),
                          ])
                            SetRow(
                              LucideIcons.heartPulse,
                              C.red,
                              title,
                              value: prefs.mutedFindings.contains(kind.name)
                                  ? off
                                  : on,
                              chevron: false,
                              onTap: () {
                                final m = {...prefs.mutedFindings};
                                if (!m.remove(kind.name)) m.add(kind.name);
                                set(prefs.copyWith(mutedFindings: m));
                              },
                            ),
                        SetRow(
                          LucideIcons.watch,
                          C.orange,
                          l?.settingsBandAlertsRowTitle ?? 'Band alerts',
                          sub:
                              l?.settingsBandAlertsRowSub ??
                              'Flat battery, on the charger, gone quiet',
                          value: prefs.deviceEnabled ? on : off,
                          chevron: false,
                          onTap: () => set(
                            prefs.copyWith(deviceEnabled: !prefs.deviceEnabled),
                          ),
                        ),
                        // The low-battery threshold, only while band alerts are
                        // on — an interval for a muted alert is furniture, same
                        // rule as the water row below.
                        if (prefs.deviceEnabled)
                          SetRow(
                            LucideIcons.batteryLow,
                            C.orange,
                            l?.settingsAlertMeAtRowTitle ?? 'Alert me at',
                            sub:
                                l?.settingsAlertMeAtRowSub ??
                                'Warn when the band drops under this charge '
                                    'level',
                            value: '${prefs.batteryAlertPct}%',
                            chevron: false,
                            onTap: () => set(
                              prefs.copyWith(
                                batteryAlertPct: _nextBatteryPct(
                                  prefs.batteryAlertPct,
                                ),
                              ),
                            ),
                          ),
                        // The retained recovery-channel switch, now with a real
                        // event behind it again: the morning "recovery is ready"
                        // note. It was cut in the three-class cull and sat dead —
                        // emitted, classified null, dropped.
                        SetRow(
                          LucideIcons.activity,
                          C.green,
                          l?.settingsRecoveryReadyRowTitle ?? 'Recovery ready',
                          sub:
                              l?.settingsRecoveryReadyRowSub ??
                              'One note when your morning recovery score '
                                  'lands',
                          value: prefs.recoveryEnabled ? on : off,
                          chevron: false,
                          onTap: () => set(
                            prefs.copyWith(
                              recoveryEnabled: !prefs.recoveryEnabled,
                            ),
                          ),
                        ),
                        // Says what it DOES now: the finding is computed from the
                        // week's own crossday rollup (medical flags first, then a
                        // plainly-stated resting-HR drift), and most weeks still
                        // say nothing — which is the point.
                        SetRow(
                          LucideIcons.calendarDays,
                          C.purple,
                          l?.settingsWeeklyLookbackRowTitle ??
                              'Weekly lookback',
                          sub:
                              l?.settingsWeeklyLookbackRowSub ??
                              'Sunday evening, but only for a week that '
                                  'actually found something. Most weeks are quiet',
                          value: prefs.remindersEnabled ? on : off,
                          chevron: false,
                          onTap: () => set(
                            prefs.copyWith(
                              remindersEnabled: !prefs.remindersEnabled,
                            ),
                          ),
                        ),
                        // The auto-detector's off switch, asked for twice (#102,
                        // #149) and never built: the bouts were written, the
                        // prompt was emitted, and nothing anywhere could stop
                        // either. The sub-line says exactly what it stops,
                        // because it does NOT stop the detection itself.
                        SetRow(
                          LucideIcons.radar,
                          C.green,
                          l?.settingsDetectedWorkoutsRowTitle ??
                              'Detected workouts',
                          sub:
                              l?.settingsDetectedWorkoutsRowSub ??
                              'Ask about efforts the band spotted that you did '
                                  'not start, and about a workout left running. '
                                  'Off hides these prompts and the review cards; '
                                  'the band goes on measuring either way',
                          value: prefs.autoDetectEnabled ? on : off,
                          chevron: false,
                          onTap: () => set(
                            prefs.copyWith(
                              autoDetectEnabled: !prefs.autoDetectEnabled,
                            ),
                          ),
                        ),
                      ],
                    ),
                    settingsGroup(
                      c,
                      l?.settingsGroupQuietHours ?? 'Quiet hours',
                      [
                        SetRow(
                          LucideIcons.moon,
                          C.indigo,
                          l?.settingsQuietHoursRowTitle ?? 'Quiet hours',
                          sub:
                              l?.settingsQuietHoursRowSub ??
                              'Alerts stay quiet here. Reminders you set (Food, Body, Pushups) keep their own times',
                          value: prefs.quietEnabled ? on : off,
                          chevron: false,
                          onTap: () => set(
                            prefs.copyWith(quietEnabled: !prefs.quietEnabled),
                          ),
                        ),
                        SetRow(
                          LucideIcons.sunset,
                          C.blue,
                          l?.settingsQuietHoursStartsRowTitle ?? 'Starts',
                          value: _hhmm(prefs.quietStartMin),
                          chevron: false,
                          onTap: () async {
                            final v = await _pickMinute(c, prefs.quietStartMin);
                            if (v != null) {
                              set(prefs.copyWith(quietStartMin: v));
                            }
                          },
                        ),
                        SetRow(
                          LucideIcons.sunrise,
                          C.yellow,
                          l?.settingsQuietHoursEndsRowTitle ?? 'Ends',
                          value: _hhmm(prefs.quietEndMin),
                          chevron: false,
                          onTap: () async {
                            final v = await _pickMinute(c, prefs.quietEndMin);
                            if (v != null) set(prefs.copyWith(quietEndMin: v));
                          },
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: S.x3),
                  StatusCard(
                    l?.settingsAlarmNotOnListTitle ??
                        'The alarm is not on this list',
                    l?.settingsAlarmNotOnListBody ??
                        'Cancel it on the Alarm screen instead.',
                    icon: LucideIcons.alarmClock,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Low-battery alert thresholds, tapped through in place.
  /// Bounds match NotificationPrefs.batteryPctMin/Max, so every choice here is
  /// one the pref will store unclamped.
  static const batteryChoices = [10, 15, 20, 25, 30, 40];

  static int _nextBatteryPct(int pct) {
    final i = batteryChoices.indexOf(pct);
    return batteryChoices[(i + 1) % batteryChoices.length];
  }

  static String _hhmm(int minuteOfDay) => formatMinuteOfDay(minuteOfDay);

  static Future<int?> _pickMinute(BuildContext c, int current) async {
    final picked = await showTimePicker(
      context: c,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }
}

// ══════════════════ EDIT PROFILE ══════════════════

class EditProfile extends StatelessWidget {
  const EditProfile({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.read<AppState>();
    return EditProfileView(
      initial: app.user ?? const {},
      // The app SHOWED lb and EDITED kg: Health converted on the way out, this
      // form did not convert on the way in, so typing back the 172 lb the app
      // had just printed stored 172 kg.
      units: c.watch<UnitsController>(),
      onSave: (fields) async {
        // A field the user CLEARED must be removed, not merged over — the
        // profile map is a merge, so writing only what is present would keep
        // a stale value alive and score the day against a body that is no
        // longer described.
        await app.updateProfile({
          for (final k in const [
            'name',
            'sex',
            'age',
            'height_cm',
            'weight_kg',
          ])
            k: fields[k],
        });
        if (c.mounted) Navigator.of(c).maybePop();
      },
    );
  }
}

class EditProfileView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  /// Display units for the height and weight fields. Null is metric, which is
  /// also what the storage is — the conversion only exists for imperial.
  final UnitsController? units;

  const EditProfileView({
    super.key,
    required this.onSave,
    this.initial = const {},
    this.units,
  });

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  late final UnitsController _u = widget.units ?? UnitsController.withUnits();
  late final _name = TextEditingController(
    text: '${widget.initial['name'] ?? ''}',
  );
  late final _age = TextEditingController(text: _s(widget.initial['age']));
  late final _height = TextEditingController(
    text: _u.heightField(widget.initial['height_cm'] as num?),
  );
  late final _weight = TextEditingController(
    text: _u.weightField(widget.initial['weight_kg'] as num?),
  );
  late String? _sex = (widget.initial['sex'] as String?)?.toLowerCase();

  static String _s(Object? v) => v == null ? '' : '$v';

  /// What the form held when it opened, for the unsaved-changes guard.
  late final String _start = _snapshot;
  String get _snapshot =>
      [_name.text, _age.text, _height.text, _weight.text, _sex].join('\u0000');

  @override
  void initState() {
    super.initState();
    _start;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// A field that cannot be read is NOT a cleared field.
  ///
  /// Every key here is written unconditionally, precisely so a cleared one is
  /// removed rather than merged over — which meant a typo ("78 kg", "78,5")
  /// parsed to null and wiped the stored weight while the screen popped as if
  /// it had saved. Blank still clears; a typo now stops the save and says so.
  bool _saving = false;
  Future<void> _save() async {
    if (_saving) return;
    final l = AppLocalizations.of(context);
    final age = Typed.of(_age.text);
    final height = Typed.of(_height.text);
    final weight = Typed.of(_weight.text);
    final bad = [
      if (age.bad) (l?.settingsAgeFieldLabel ?? 'Age'),
      if (height.bad) _u.heightLabel,
      if (weight.bad) _u.weightLabel,
    ];
    if (bad.isNotEmpty) {
      sayUnreadable(context, bad);
      return;
    }
    final cm =
        _height.text == _u.heightField(widget.initial['height_cm'] as num?)
        ? (widget.initial['height_cm'] as num?)?.toDouble()
        : _u.heightToCm(_height.text);
    final kg =
        _weight.text == _u.weightField(widget.initial['weight_kg'] as num?)
        ? (widget.initial['weight_kg'] as num?)?.toDouble()
        : _u.weightToKg(_weight.text);
    if ((age.value != null &&
            (age.value! < 1 ||
                age.value! > 120 ||
                age.value! != age.value!.roundToDouble())) ||
        (cm != null && (!cm.isFinite || cm < 30 || cm > 280)) ||
        (kg != null && (!kg.isFinite || kg < 1 || kg > 500))) {
      sayUnreadable(context, [
        'Age, height or weight is outside its supported range',
      ]);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave({
        'name': _name.text.trim().isEmpty ? null : _name.text.trim(),
        'sex': _sex,
        'age': age.value?.round(),
        // Typed in the units on the label, stored in metric.
        'height_cm': height.value == null ? null : cm,
        'weight_kg': weight.value == null ? null : kg,
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile could not save. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return DirtyPopScope(
      dirty: () => !_saving && _snapshot != _start,
      listenables: [_name, _age, _height, _weight],
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x4),
                child: NavBar(
                  l?.settingsEditProfileNavTitle ?? 'Edit profile',
                  trailing: Pressable(
                    semanticLabel: l?.actionSave ?? 'Save',
                    onTap: _saving ? null : _save,
                    child: Text(
                      _saving ? 'Saving…' : l?.actionSave ?? 'Save',
                      style: F.body.copyWith(
                        color: p.on(C.green),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                  children: [
                    _text(
                      c,
                      _name,
                      l?.settingsNameFieldLabel ?? 'NAME',
                      TextInputType.name,
                    ),
                    const SizedBox(height: S.x4),
                    Text(
                      l?.settingsSexFieldLabel ?? 'SEX',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                    const SizedBox(height: S.x2),
                    Wrap(
                      spacing: S.x2,
                      runSpacing: S.x2,
                      children: [
                        for (final (key, label) in [
                          ('m', l?.settingsSexMale ?? 'Male'),
                          ('f', l?.settingsSexFemale ?? 'Female'),
                          (
                            'other',
                            l?.settingsSexPreferNotToSay ?? 'Prefer not to say',
                          ),
                        ])
                          Pressable(
                            onTap: () => setState(() => _sex = key),
                            semanticLabel: label,
                            selected: _sex == key,
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: S.x4,
                                vertical: S.x2,
                              ),
                              decoration: BoxDecoration(
                                color: _sex == key ? p.wash(C.green) : p.card,
                                borderRadius: R.rPill,
                                border: Border.all(
                                  color: _sex == key ? p.on(C.green) : p.line,
                                ),
                              ),
                              child: Text(
                                label,
                                style: F.cap.copyWith(
                                  color: _sex == key ? p.on(C.green) : p.ink2,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: S.x4),
                    _text(
                      c,
                      _age,
                      l?.settingsAgeYearsFieldLabel ?? 'AGE (YEARS)',
                      TextInputType.number,
                    ),
                    const SizedBox(height: S.x4),
                    _text(
                      c,
                      _height,
                      _u.heightLabel.toUpperCase(),
                      const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: S.x4),
                    _text(
                      c,
                      _weight,
                      _u.weightLabel.toUpperCase(),
                      const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: S.x6),
                    StatusCard(
                      l?.settingsFourFieldsTitle ??
                          'These four change your numbers',
                      l?.settingsFourFieldsBody ??
                          'They feed heart-rate zones, calorie estimates and training '
                              'load. Clear one and only the metrics that need it stay '
                              'unavailable.',
                      icon: LucideIcons.info,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _text(
    BuildContext c,
    TextEditingController ctl,
    String label,
    TextInputType kind,
  ) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: F.over.copyWith(color: p.ink3)),
        TextField(
          controller: ctl,
          keyboardType: kind,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(c).unfocus(),
          onTapOutside: (_) => FocusScope.of(c).unfocus(),
          style: F.head.copyWith(color: p.ink),
          decoration: InputDecoration(
            hintText: l?.settingsNotSetHint ?? 'Not set',
            hintStyle: F.head.copyWith(color: p.ink3),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: S.x3),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.line),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: p.on(C.green)),
            ),
          ),
        ),
      ],
    );
  }
}

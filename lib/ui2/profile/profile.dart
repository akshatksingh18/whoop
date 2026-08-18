// Profile.
//
// Reached from the Home avatar, never a sixth tab — the shell has five
// destinations and the type system says so.
//
// The reference design had a Premium badge and a Following/Followers pair.
// Both are gone, and not for lack of screen space: there is no account and no
// social graph, so a follower count would have to be invented and a premium
// tier would have to be sold. What replaces them is what this app actually
// knows — how much it has measured, and from what.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../health/health_import_state.dart' show storeName;
import '../../state/app_state.dart';
import '../ui2.dart';
import 'devices.dart';
import 'phone_import.dart';
import 'settings.dart';

// ══════════════════ shared list furniture ══════════════════

/// One row in a settings list. Shared by all three profile screens.
class SetRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub, value;
  final bool danger, chevron;
  final VoidCallback? onTap;

  const SetRow(this.icon, this.color, this.title,
      {super.key,
      this.sub = '',
      this.value = '',
      this.danger = false,
      this.chevron = true,
      this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final accent = danger ? C.red : color;
    return Pressable(
      onTap: onTap,
      semanticLabel: sub.isEmpty ? title : '$title. $sub',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: p.wash(accent), borderRadius: R.rSm),
            child: Icon(icon, size: 16, color: p.on(accent)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: F.body.copyWith(color: danger ? p.on(C.red) : p.ink)),
              if (value.isNotEmpty && bigText(c))
                Text(value,
                    style: F.cap.copyWith(
                        color: p.ink3, fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty)
                Text(sub, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
          // THE ROW RULE (see MetricRow): the title is the only flexible part,
          // so every value in a settings list ends on one right edge. Two flex
          // children would split the width by ratio and break that column.
          // The value moves UNDER the title at accessibility sizes instead —
          // "2026-08-16 04:12" is arbitrary-length, and at 3.1× it pushed
          // itself and the chevron off the right of every settings screen.
          if (value.isNotEmpty && !bigText(c)) ...[
            const SizedBox(width: S.x2),
            Text(value, style: F.cap.copyWith(color: p.ink3)),
          ],
          if (chevron && !danger) ...[
            const SizedBox(width: S.x2),
            Icon(LucideIcons.chevronRight, size: 17, color: p.ink3),
          ],
        ]),
      ),
    );
  }
}

/// A titled card of [SetRow]s, hairline-separated.
Widget settingsGroup(BuildContext c, String title, List<Widget> rows) {
  final p = P.of(c);
  return Section(
    title,
    Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) Divider(color: p.line, height: 1),
        ],
      ]),
    ),
  );
}

/// Push a screen, keeping the enclosing domain accent. Returns when it pops,
/// so a caller whose own numbers the pushed screen can change is able to
/// re-read them.
Future<void> goto(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

/// The one way into the profile stack. Home's avatar calls this — profile is
/// a pushed route, never a sixth tab.
void openProfile(BuildContext c) => goto(c, const ProfileHome());

/// Human-readable byte size. No dependency for four lines of arithmetic.
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}

// ══════════════════ 1 · PROFILE HOME ══════════════════

/// What the profile screen still shows: who you are, how many sources are
/// live, and how much room the data takes.
///
/// The workouts / records / days / sessions counters are gone with the tile
/// that displayed them. They cost a `getRecords()` and a whole year-of-workouts
/// query on every open, so leaving the fields behind would have kept paying for
/// numbers nobody reads.
class ProfileStats {
  final String? name;
  final int sources;
  final int? storageBytes;

  const ProfileStats({this.name, this.sources = 0, this.storageBytes});
}

class ProfileHome extends StatefulWidget {
  const ProfileHome({super.key});

  @override
  State<ProfileHome> createState() => _ProfileHomeState();
}

class _ProfileHomeState extends State<ProfileHome> {
  /// Re-read after every screen this one pushes. It used to be a single
  /// `late final` Future, so pairing a band from My sources (which auto-pops
  /// straight back here) left the row reading "0 sources", and an import or a
  /// reset left Storage on the old size until the screen was left and
  /// re-entered.
  late Future<ProfileStats> _stats = _load();

  Future<ProfileStats> _load() async {
    final app = context.read<AppState>();
    final repo = app.repo;
    final sources = liveSources(app).length;
    if (repo == null) {
      return ProfileStats(
          name: app.user?['name'] as String?, sources: sources);
    }
    final bytes = await app.dataFileBytes();
    return ProfileStats(
      name: app.user?['name'] as String?,
      sources: sources,
      storageBytes: bytes,
    );
  }

  Future<void> _open(BuildContext c, Widget w) async {
    await goto(c, w);
    if (mounted) setState(() => _stats = _load());
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<ProfileStats>(
        future: _stats,
        builder: (c, snap) => ProfileHomeView(
          stats: snap.data,
          onDevices: () => _open(c, const MyDevices()),
          onSettings: () => _open(c, const MoreSettings()),
          onEdit: () => _open(c, const EditProfile()),
          onPhoneImport: () => _open(c, const PhoneImport()),
        ),
      );
}

class ProfileHomeView extends StatelessWidget {
  /// Null while the counts are still being read — the numbers are absent, not
  /// zero, and a zero rendered during a load is a wrong number on screen.
  final ProfileStats? stats;
  final VoidCallback? onDevices, onSettings, onEdit, onPhoneImport;

  const ProfileHomeView(
      {super.key,
      this.stats,
      this.onDevices,
      this.onSettings,
      this.onEdit,
      this.onPhoneImport});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final s = stats;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Profile',
                trailing: Pressable(
                  onTap: onSettings,
                  semanticLabel: 'Settings',
                  child: Icon(LucideIcons.settings, size: 20, color: p.ink2),
                )),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                const SizedBox(height: S.x4),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.wash(C.green, strength: 2),
                    ),
                    child:
                        Icon(LucideIcons.user, size: 42, color: p.on(C.green)),
                  ),
                ),
                const SizedBox(height: S.x4),
                Center(
                  child: Text(
                    (s?.name?.trim().isNotEmpty ?? false) ? s!.name! : 'You',
                    style: F.t2.copyWith(color: p.ink),
                  ),
                ),
                const SizedBox(height: S.x3),
                const Center(
                    child: Pill('Local · no cloud', C.green,
                        icon: LucideIcons.shieldCheck)),
                const SizedBox(height: S.x6),
                settingsGroup(c, 'Quick access', [
                  SetRow(LucideIcons.watch, C.blue, 'My devices',
                      sub: s == null
                          ? ''
                          : '${s.sources} source${s.sources == 1 ? '' : 's'}',
                      onTap: onDevices),
                  SetRow(LucideIcons.userPen, C.purple, 'Edit profile',
                      sub: 'Sex, age, height, weight', onTap: onEdit),
                  // What is LEFT on that screen, described honestly. Height,
                  // weight and workouts moved to the screens they fill — Edit
                  // profile and Workout › History — so this row no longer
                  // promises them. There is a second door under More settings ›
                  // Your data.
                  SetRow(LucideIcons.smartphone, C.blue, 'From $storeName',
                      sub: 'Resting heart rate, and readings from instruments '
                          'this band does not have',
                      onTap: onPhoneImport),
                ]),
                settingsGroup(c, 'Your data', [
                  SetRow(LucideIcons.database, C.green, 'Storage',
                      value: s?.storageBytes == null
                          ? ''
                          : formatBytes(s!.storageBytes!),
                      chevron: false),
                  SetRow(LucideIcons.settings, C.n500, 'More settings',
                      sub: 'Export, backup, units, privacy, reset',
                      onTap: onSettings),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

}

// Soft, dismissible community asks — never a blocking dialog, never sticky.
// Two independent nudges (join Discord / support the project on GitHub
// Sponsors), each shown at most once per cooldown and never again once the
// user says so, via the same `Prefs` facade every other one-time UI flag
// uses. At most one shown at a time — asking about both in one breath is
// exactly the nagging feel this was asked not to have.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/prefs.dart';
import 'community_links.dart';
import 'ui2.dart';

enum _Ask { discord, donate }

/// A card Home renders last, after everything it actually measured — never
/// above the fold, never in the way of the numbers someone opened the app
/// for.
class CommunityNudge extends StatefulWidget {
  const CommunityNudge({super.key});

  @override
  State<CommunityNudge> createState() => _CommunityNudgeState();
}

class _CommunityNudgeState extends State<CommunityNudge> {
  // Two weeks between reappearances of a snoozed ask — long enough that it
  // never reads as nagging, short enough it is not gone for good on a tap
  // that was just a slip.
  static const _cooldownMs = 14 * 24 * 60 * 60 * 1000;

  static String _dismissedKey(_Ask a) => 'nudge.${a.name}.dismissed';
  static String _lastShownKey(_Ask a) => 'nudge.${a.name}.last_shown_ms';

  static bool _eligible(_Ask a) {
    if (Prefs.getBool(_dismissedKey(a), false)) return false;
    final last = Prefs.getInt(_lastShownKey(a), 0);
    return DateTime.now().millisecondsSinceEpoch - last > _cooldownMs;
  }

  /// Discord before the sponsor ask — joining a community is a smaller thing
  /// to ask for than money, so it goes first when both are due.
  static _Ask? _pick() {
    if (_eligible(_Ask.discord)) return _Ask.discord;
    if (_eligible(_Ask.donate)) return _Ask.donate;
    return null;
  }

  late _Ask? _ask = _pick();

  void _snooze(_Ask a) {
    Prefs.setInt(_lastShownKey(a), DateTime.now().millisecondsSinceEpoch);
    setState(() => _ask = null);
  }

  void _silence(_Ask a) {
    Prefs.setBool(_dismissedKey(a), true);
    setState(() => _ask = null);
  }

  @override
  Widget build(BuildContext c) {
    final a = _ask;
    if (a == null) return const SizedBox.shrink();
    final p = P.of(c);

    final (icon, color, title, body, cta, url) = switch (a) {
      _Ask.discord => (
          LucideIcons.usersRound,
          C.indigo,
          'Come say hi',
          'Other OpenStrap users hang out on Discord — bugs, ideas, and '
              'people running the same band as you.',
          'Join Discord',
          kDiscordUrl,
        ),
      _Ask.donate => (
          LucideIcons.heartHandshake,
          C.pink,
          'Enjoying OpenStrap?',
          'It is a free, one-person project with no subscription. '
              'Sponsoring keeps it maintained.',
          'Support the project',
          kSponsorUrl,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: S.x5),
      child: Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: p.wash(color), borderRadius: R.rSm),
              child: Icon(icon, size: 16, color: p.on(color)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: F.body.copyWith(
                            color: p.ink, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(body, style: F.over.copyWith(color: p.ink3)),
                  ]),
            ),
            const SizedBox(width: S.x2),
            Pressable(
              onTap: () => _snooze(a),
              semanticLabel: 'Not now',
              child: Icon(LucideIcons.x, size: 16, color: p.ink3),
            ),
          ]),
          const SizedBox(height: S.x3),
          BigButton(cta,
              icon: LucideIcons.externalLink,
              color: color,
              soft: true,
              onTap: () {
                open3rdPartyLink(url);
                // Acted on, not just seen — no reason to ask again.
                _silence(a);
              }),
          const SizedBox(height: S.x2),
          Center(
            child: Pressable(
              onTap: () => _silence(a),
              semanticLabel: "Don't show this again",
              child: Text("Don't show this again",
                  style: F.over.copyWith(
                      color: p.ink3, decoration: TextDecoration.underline)),
            ),
          ),
        ]),
      ),
    );
  }
}

// Soft, dismissible community asks — never a blocking dialog, never sticky.
// Two independent nudges (join Discord / support the project on GitHub
// Sponsors), each shown at most once per cooldown and never again once the
// user says so, via the same `Prefs` facade every other one-time UI flag
// uses. Both can be up at once, stacked — each is dismissed on its own.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../state/prefs.dart';
import 'community_links.dart';
import 'ui2.dart';

enum _Ask { discord, donate }

/// Home renders one of these per eligible ask, right under the rings.
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
    // Developer mode is someone deliberately testing the app, not a real
    // reader being nagged — silencing or a cooldown here would just make
    // this unreachable on every build after the first tap.
    if (Prefs.getBool(Prefs.devMode, false)) return true;
    if (Prefs.getBool(_dismissedKey(a), false)) return false;
    final last = Prefs.getInt(_lastShownKey(a), 0);
    return DateTime.now().millisecondsSinceEpoch - last > _cooldownMs;
  }

  // Discord above the sponsor ask when both are due — joining a community
  // is a smaller thing to ask for than money.
  final List<_Ask> _asks = [
    for (final a in _Ask.values)
      if (_eligible(a)) a,
  ];

  void _snooze(_Ask a) {
    Prefs.setInt(_lastShownKey(a), DateTime.now().millisecondsSinceEpoch);
    _hide(a);
  }

  void _silence(_Ask a) {
    Prefs.setBool(_dismissedKey(a), true);
    _hide(a);
  }

  void _hide(_Ask a) {
    // Dev mode ignores its own dismissal/cooldown (see _eligible) — writing
    // it above is harmless, but re-adding it here is what testing it needs.
    final devMode = Prefs.getBool(Prefs.devMode, false);
    setState(() => devMode ? null : _asks.remove(a));
  }

  @override
  Widget build(BuildContext c) => Column(
      children: [for (final a in _asks) _AskCard(a, onSnooze: _snooze, onSilence: _silence)]);
}

class _AskCard extends StatelessWidget {
  final _Ask ask;
  final void Function(_Ask) onSnooze, onSilence;

  const _AskCard(this.ask, {required this.onSnooze, required this.onSilence});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final (icon, color, title, body, cta, url) = switch (ask) {
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
              onTap: () => onSnooze(ask),
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
                onSilence(ask);
              }),
          const SizedBox(height: S.x2),
          Center(
            child: Pressable(
              onTap: () => onSilence(ask),
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

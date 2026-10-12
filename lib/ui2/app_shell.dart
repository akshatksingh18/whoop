// The stable five-tab shell: Today, Trends, Food, Train and Progress.
// Each domain owns its contextual controls; the bottom navigation stays fixed.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'grammar.dart';
import 'theme.dart';

/// The five primary destinations, in bar order.
enum ShellDomain {
  home('Today', LucideIcons.house, C.domHome),
  health('Trends', LucideIcons.chartLine, C.domHealth),
  nutrition('Food', LucideIcons.utensils, C.domFood),
  workout('Train', LucideIcons.dumbbell, C.domMove),
  // Build 86: the one recomposition page, with Body inside it. Last, so the
  // saved tab index of the first four is unchanged.
  progress('Progress', LucideIcons.trendingUp, C.teal);

  const ShellDomain(this.label, this.icon, this.accent);

  final String label;
  final IconData icon;

  /// The domain's pigment. Use `P.of(context).on(accent)` for text and
  /// `.fill(accent)` for a filled surface — the raw value is not AA-safe.
  final Color accent;
}

/// A re-tap of the tab already showing, with a counter so two re-taps in a
/// row both notify. A domain that keeps a sub-state (Food's day and sub-tab,
/// Trends' range) listens and returns to its first view; scrolling back to
/// the top is done by the shell for every tab.
final shellReselect = ValueNotifier<(ShellDomain, int)>((ShellDomain.home, 0));

// There is no `Domain` InheritedWidget. There was one, promising that a screen
// "and anything it pushes" could pick up its accent without threading it — but
// nothing ever read it, and a pushed route could not have: `MaterialApp.home`
// is the gate, so `Navigator.of` pushes above the shell entirely. Screens take
// their accent as a parameter, which is honest about where it comes from.

class AppShell extends StatefulWidget {
  /// Builds the body of one domain. Called lazily — a tab is not built until
  /// it is first selected, then kept alive by the [IndexedStack].
  final Widget Function(BuildContext context, ShellDomain domain) builder;

  final ShellDomain initial;

  /// Notified on every tab change, including a re-tap of the current tab
  /// (which domains conventionally use to scroll to top).
  final void Function(ShellDomain domain)? onSelect;

  /// Pinned between the domain and the tab bar, above every tab. This is not
  /// a general slot — it exists for state that is RUNNING and is not on
  /// screen, which today means a minimised workout. A domain's own content
  /// belongs inside the domain.
  final Widget? banner;

  const AppShell({
    super.key,
    required this.builder,
    this.initial = ShellDomain.home,
    this.onSelect,
    this.banner,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late ShellDomain _current = widget.initial;
  late final Set<ShellDomain> _built = {widget.initial};

  /// One primary scroll controller per tab: each tab's page list adopts it,
  /// so a re-tap can take that tab back to the top.
  final _scroll = {for (final d in ShellDomain.values) d: ScrollController()};

  @override
  void dispose() {
    for (final c in _scroll.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _select(ShellDomain d) {
    if (d == _current) {
      final c = _scroll[d]!;
      // One attached list only: a tab mid-rebuild can briefly hold two.
      if (c.hasClients && c.positions.length == 1 && c.offset > 0) {
        c.animateTo(
          0,
          duration: motion(context, Motion.slow),
          curve: Curves.easeOutCubic,
        );
      }
      shellReselect.value = (d, shellReselect.value.$2 + 1);
    }
    setState(() {
      _current = d;
      _built.add(d);
    });
    widget.onSelect?.call(d);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _current.index,
                    children: [
                      // An unvisited tab is an empty box, not a built screen — the
                      // old shell built all forty screens' worth of state on launch.
                      for (final d in ShellDomain.values)
                        if (_built.contains(d))
                          PrimaryScrollController(
                            controller: _scroll[d]!,
                            child: widget.builder(c, d),
                          )
                        else
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
                if (widget.banner != null) widget.banner!,
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _TabBar(current: _current, onTap: _select),
    );
  }
}

class _TabBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;

  const _TabBar({required this.current, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final labelHeight = ShellDomain.values.fold<double>(0, (height, d) {
      final text =
          TextPainter(
            text: TextSpan(
              text: d.label,
              style: F.over.copyWith(fontWeight: FontWeight.w600),
            ),
            textDirection: Directionality.of(c),
            textScaler: MediaQuery.textScalerOf(c),
          )..layout(
            maxWidth: MediaQuery.sizeOf(c).width / ShellDomain.values.length,
          );
      final measured = text.height;
      text.dispose();
      return measured > height ? measured : height;
    });
    // Build 88: the tab bar is paper over the kraft, like the system bar.
    return ColoredBox(
      color: p.card,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: S.x1),
        child: Container(
          height: (labelHeight + 38).clamp(62, double.infinity),
          decoration: BoxDecoration(
            color: p.card,
            border: Border(top: BorderSide(color: p.line)),
          ),
          child: Row(
            children: [
              for (final d in ShellDomain.values)
                Expanded(
                  child: _Tab(
                    domain: d,
                    on: d == current,
                    onTap: () => onTap(d),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final ShellDomain domain;
  final bool on;
  final VoidCallback onTap;

  const _Tab({required this.domain, required this.on, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // Build 88: the active tab is the recovery green (DESIGN.md).
    final ink = on ? p.on(C.recovery) : p.ink3;
    return Semantics(
      selected: on,
      child: Pressable(
        onTap: onTap,
        semanticLabel: domain.label,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Stable icon target; labels can wrap at accessibility sizes.
            AnimatedContainer(
              duration: motion(c, Motion.base),
              padding: const EdgeInsets.symmetric(
                horizontal: S.x3,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: on ? p.fill(C.recovery) : const Color(0x00000000),
                borderRadius: R.rMd,
              ),
              child: Icon(
                domain.icon,
                size: 20,
                color: on ? p.inkOnFill : ink,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              domain.label,
              textAlign: TextAlign.center,
              style: F.over.copyWith(
                color: ink,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Theme-reactive routes. Colours are global statics (AppColors.x), so the
// framework has no dependency edge telling it what to rebuild when the mode
// flips. Every route rebuilds instead: the home stack watches the controller
// (see app.dart), and pushed routes go through [themedRoute], whose body is a
// [_ThemeReactive] that depends on the controller and reconstructs its screen
// on change (State is preserved — same type at the same position).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme_controller.dart';

/// Wrap a screen builder so the route rebuilds on every mode change.
/// Use everywhere instead of `MaterialPageRoute(builder: ...)`.
///
/// NAVIGATION CONTRACT — this MUST stay a [MaterialPageRoute] (or another
/// route mixing in Material/Cupertino route-transition machinery). A raw
/// PageRouteBuilder has no interactive back-gesture support, which silently
/// kills the iOS edge-swipe-back on every pushed screen. The app's shared-axis
/// transition policy therefore lives in the active ui2 theme's
/// pageTransitionsTheme. Its existing gate wraps the SDK builders, including
/// the iOS/macOS Cupertino transition with swipe-back. [name] is retained as
/// RouteSettings.name so each pushed route can keep its destination identity.
PageRoute<T> themedRoute<T>(
  WidgetBuilder builder, {
  bool fullscreenDialog = false,
  String? name,
}) => MaterialPageRoute<T>(
  fullscreenDialog: fullscreenDialog,
  settings: RouteSettings(name: name),
  builder: (ctx) => _ThemeReactive(builder: builder),
);

class _ThemeReactive extends StatelessWidget {
  final WidgetBuilder builder;
  const _ThemeReactive({required this.builder});
  @override
  Widget build(BuildContext context) {
    // Depend on the controller → this route's body rebuilds when the mode flips,
    // reconstructing the screen with fresh AppColors while keeping its State.
    context.watch<ThemeController>();
    return builder(context);
  }
}

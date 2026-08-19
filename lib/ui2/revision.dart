// "The data under this screen changed — re-read it."
//
// One idiom, not two. A screen that loads in `initState` and never reads
// again is correct exactly until something else writes: an import lands sixty
// sessions, a derive rewrites the day, a workout is logged from the sheet, and
// the screen keeps rendering what it read at launch. Three of the five tabs
// are kept alive forever by the shell's IndexedStack, so "for the life of the
// widget" means "until the app is relaunched" — which is why the workaround
// was to leave the tab and come back.
//
// The signal already existed: [AppState.insightsRevision], a ValueNotifier the
// derive, the session writer and now the importers tick. Home and Workouts had
// each hand-rolled the same twenty lines of subscribe/compare/dispose around
// it; this is those twenty lines, once.
//
// WHY A ValueNotifier AND NOT notifyListeners: AppState ticks at ~1 Hz while a
// session is live (live HR, log lines). Anything watching AppState broadly
// rebuilds on every one of those — the reason `select` is used everywhere in
// this app. `insightsRevision` moves only when DURABLE data changed, and it is
// off the ChangeNotifier path entirely, so a subscriber re-reads on a derive
// or an import and never on a heartbeat.
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Re-read on [AppState.insightsRevision].
///
/// The screen keeps its own first load in `initState`; this only says when to
/// do it again. Mix in, implement [reload], and delete the plumbing.
mixin RevisionReload<T extends StatefulWidget> on State<T> {
  /// Held so [dispose] can unsubscribe without a context, and so a second
  /// `didChangeDependencies` cannot subscribe twice — `addListener` stacks
  /// duplicates.
  ValueNotifier<int>? _rev;

  /// The revision this screen's data was read at.
  int _seen = -1;

  /// Read the database again. Called ONLY when the revision actually moves —
  /// never on a rebuild, so it is safe for it to be expensive.
  void reload();

  /// False for a screen that was handed its data (a golden, the gallery, a
  /// preview): there is nothing behind it to re-read.
  bool get revisionReloads => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!revisionReloads) return;
    // No AppState above us in a golden or a widget test — such a screen just
    // renders what it has, exactly as it did before this mixin existed.
    final AppState app;
    try {
      app = context.read<AppState>();
    } catch (_) {
      return;
    }
    if (identical(_rev, app.insightsRevision)) return;
    _rev?.removeListener(_onRevision);
    _rev = app.insightsRevision..addListener(_onRevision);
    _seen = app.insightsRevision.value;
  }

  // ponytail: a parked tab re-reads too — the IndexedStack keeps all five
  // alive, so a derive costs five loads instead of one. They are the same
  // queries opening the tab would run, and they run on a derive or an import,
  // not on a frame. Gate on route/tab visibility if profiling ever says so.
  void _onRevision() {
    final r = _rev;
    // A bump that landed while this screen was being torn down, or one it has
    // already read, is not a reason to hit the database.
    if (!mounted || r == null || r.value == _seen) return;
    _seen = r.value;
    reload();
  }

  @override
  void dispose() {
    _rev?.removeListener(_onRevision);
    super.dispose();
  }
}

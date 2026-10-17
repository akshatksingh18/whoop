// Build 90 contract: the one way another tab opens Progress. Today, Food and
// Train call [openProgress] with where they want to land; nothing outside
// Progress pushes its screens directly, so Progress can change its pages
// without breaking the links into it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/progress_review.dart' show ProgressRange;
import '../../state/app_state.dart';
import 'progress_screen.dart'
    show BodyEntryScreen, ProgressData, progressDetailPage;

/// Where in Progress a link lands.
enum ProgressDest {
  overview,
  weight,
  waist,
  strength,
  food,
  training,
  recovery,
  entry,
}

/// Open Progress at [dest].
///
/// The overview switches to the Progress tab. Every other destination opens
/// its page over the screen that asked, so Back returns there with its day,
/// range, filter and scroll intact. [initial] lets Progress hand over what it
/// has already read, so the page draws at once.
Future<void> openProgress(
  BuildContext c, [
  ProgressDest dest = ProgressDest.overview,
  ProgressData? initial,
  ProgressRange? range,
]) async {
  if (dest == ProgressDest.overview) {
    c.read<AppState>().navRequest.value = 5;
    return;
  }
  if (dest == ProgressDest.entry) {
    var unit = 'kg';
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getString('body.unit') == 'lb') unit = 'lb';
    } catch (_) {}
    if (!c.mounted) return;
    await Navigator.of(c).push(
      MaterialPageRoute<bool>(builder: (_) => BodyEntryScreen(unit: unit)),
    );
    return;
  }
  await Navigator.of(c).push(
    MaterialPageRoute<void>(
      builder: (_) => progressDetailPage(dest, initial: initial, range: range),
    ),
  );
}

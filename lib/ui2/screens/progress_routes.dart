// Build 90 contract: the one way another tab opens Progress. Today, Food and
// Train call [openProgress] with where they want to land; nothing outside
// Progress pushes its screens directly, so Progress can change its pages
// without breaking the links into it.

import 'package:flutter/material.dart';

import '../../data/progress_review.dart' show ProgressRange;
import 'progress_screen.dart' show ProgressData, progressDetailPage;

/// Where in Progress a link lands.
enum ProgressDest {
  overview,
  weight,
  waist,
  strength,
  food,
  training,
  recovery,
}

/// Open Progress at [dest].
///
/// The page opens over the screen that asked, so Back returns there with its day,
/// range, filter and scroll intact. [initial] lets Progress hand over what it
/// has already read, so the page draws at once.
Future<void> openProgress(
  BuildContext c,
  ProgressDest dest, [
  ProgressData? initial,
  ProgressRange? range,
]) async {
  await Navigator.of(c).push(
    MaterialPageRoute<void>(
      builder: (_) => progressDetailPage(dest, initial: initial, range: range),
    ),
  );
}

// Build 90 contract: the one way another tab opens Progress. Today, Food and
// Train call [openProgress] with where they want to land; nothing outside
// Progress pushes its screens directly, so Progress can change its pages
// without breaking the links into it.

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

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

/// The destination the next Progress build should open, consumed (reset to
/// null) by Progress. Until Build 90's detail pages land, Progress opens its
/// overview for every destination.
final ValueNotifier<ProgressDest?> progressDestination =
    ValueNotifier<ProgressDest?>(null);

/// Switch to the Progress tab at [dest].
void openProgress(BuildContext c, [ProgressDest dest = ProgressDest.overview]) {
  progressDestination.value = dest;
  c.read<AppState>().navRequest.value = 5;
}

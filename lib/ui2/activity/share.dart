// Share — one card, one photo slot, one button.
//
// This screen used to ask three questions: which of three styles, which four
// of nine stats, and whether to add a photo. Two of them were the screen
// asking the user to do its job. The style list offered a textured card whose
// texture a lift and a flow session could not have; the chip row asked which
// of your own measurements to leave off a card with room for all of them.
//
// What is left is the one question only the user can answer — is there a
// picture of this — and the card rearranges itself around the answer:
//
//   · no photo  → the basemap IS the card, whole, start to stop
//   · a photo   → the photograph is the card, and the route dissolves into
//                 its bottom-right corner with no frame of its own
//
// Nothing on the card is invented. If a session has no distance, "Distance"
// is not printed, so it cannot be shared.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/units_controller.dart';
import '../grammar.dart';
import '../profile/profile.dart' show SetRow;
import '../theme.dart';
import 'poster.dart';
import 'summary.dart';
import 'tiles.dart';

/// The rect an iPad or Mac share popover points at.
///
/// `UIActivityViewController` is a popover on those, and `share_plus` throws
/// rather than guessing when it is given no anchor — which is how every iPad
/// share in this app failed silently. Any `share_plus` call from a widget
/// should pass this.
Rect shareOrigin(BuildContext c) {
  final box = c.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return const Rect.fromLTWH(0, 0, 1, 1);
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

class ShareSheet extends StatefulWidget {
  final ActivityResult result;
  const ShareSheet(this.result, {super.key});

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  /// The card, as pixels. Sharing a picture of it means capturing the thing on
  /// screen rather than re-drawing a second, slightly different one.
  final _card = GlobalKey();
  bool _sharing = false;

  /// The user's own picture, and only ever the user's. Nothing here fetches
  /// or generates one.
  File? _photo;

  /// Where the card is going. The one thing besides the photo that changes it.
  PosterFormat _format = PosterFormat.post;

  /// The basemap. Fetched per FORMAT, because the mosaic is built at the
  /// card's aspect — see the note on [kPosterMapH]. Held so that flipping
  /// back to a format already fetched does not re-hit the tile server, which
  /// the usage policy in tiles.dart is explicit about.
  final _mosaics = <PosterFormat, RouteMosaic>{};
  final _mapTried = <PosterFormat>{};

  RouteMosaic? get _mosaic => _mosaics[_format];
  bool get _mapTried_ => _mapTried.contains(_format);

  ActivityResult get r => widget.result;

  /// Whether this session went anywhere. Decides whether there is a map at
  /// all — not which of several cards to draw, because there is one card.
  bool get _hasRoute => r.geo.length >= 2;

  Future<void> _share() async {
    if (_sharing) return;
    _sharing = true;
    // Both read the tree, so both are read before the first await.
    final origin = shareOrigin(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final boundary =
          _card.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      await Share.shareXFiles(
        [
          XFile.fromData(png.buffer.asUint8List(),
              mimeType: 'image/png', name: '${r.activity.typeKey}.png'),
        ],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      // A share that quietly does nothing is worse than one that says it
      // failed: this swallowed every iPad share for the life of the screen.
      if (mounted) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not open the share sheet.')));
      }
      debugPrint('share failed: $e');
    } finally {
      _sharing = false;
    }
  }

  /// The user's own picture, from this phone. No upload, no fetch, no stock
  /// backdrop picked by activity type — the card either has their photo on it
  /// or it has the accent gradient.
  Future<void> _pickPhoto() async {
    try {
      final picked = await FilePicker.platform
          .pickFiles(type: FileType.image, allowMultiple: false);
      final path = picked?.files.single.path;
      if (path != null && mounted) setState(() => _photo = File(path));
    } catch (e) {
      debugPrint('photo pick failed: \$e');
    }
  }

  /// Fetch the basemap once, for a session that went somewhere.
  ///
  /// It used to be deferred until the Poster style was selected, so a session
  /// whose owner never opened it never hit the tile server. There is no style
  /// to select now — a card with no photo IS the map — so a session with
  /// coordinates always needs one, and it is fetched once, on open, and held.
  Future<void> _ensureMap() async {
    final f = _format;
    if (_mapTried.contains(f) || !_hasRoute) return;
    _mapTried.add(f);
    // Midnight, both ends, and NOT the reader's palette.
    //
    // This card is exported and sent to someone else — it is dark whichever
    // theme drew it, so tinting the basemap to the viewer's surface produced
    // a bright map on a dark card for half the users. `mapFloor`/`mapCeil`
    // are the card's own map styling: near-black land and water, and a dim
    // slate ceiling so roads, buildings and the labels baked into the raster
    // sit down as texture rather than standing up as type.
    final m = await buildRouteMosaic(
      r.geo,
      // The card's own map box, at export resolution (`toImage` runs at 3x).
      width: kPosterMapW.round() * 3,
      height: kPosterMapH(f).round() * 3,
      bg: C.mapFloor,
      ink: C.mapCeil,
    );
    if (!mounted) {
      m?.dispose();
      return;
    }
    setState(() {
      if (m != null) _mosaics[f] = m;
    });
  }

  @override
  void initState() {
    super.initState();
    if (_hasRoute) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureMap());
    }
  }

  @override
  void dispose() {
    for (final m in _mosaics.values) {
      m.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: const NavBar('Share'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x8),
                children: [
                  // One card. There is no style list any more, and no chip row
                  // deciding which of the session's own measurements to leave
                  // off it — the card prints everything the session has, and
                  // the only thing the reader chooses is whether their photo
                  // is behind it.
                  Center(
                    child: RepaintBoundary(
                      key: _card,
                      child: PosterCard(
                        r,
                        photo: _photo == null ? null : FileImage(_photo!),
                        mosaic: _mosaic,
                        format: _format,
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x6),
                  // Not a style picker coming back. A format is where the
                  // card is GOING — Instagram crops anything that is not its
                  // own ratio, so this is the difference between posting the
                  // card and posting a crop of it.
                  SubTabs(
                    [for (final f in PosterFormat.values) f.label],
                    PosterFormat.values.indexOf(_format),
                    (i) {
                      setState(() => _format = PosterFormat.values[i]);
                      _ensureMap();
                    },
                    color: r.activity.color,
                  ),
                  const SizedBox(height: S.x6),
                  Text('YOUR PHOTO', style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x3),
                  Surface(
                    pad: const EdgeInsets.symmetric(horizontal: S.x4),
                    child: Column(children: [
                      SetRow(LucideIcons.imagePlus, r.activity.color,
                          _photo == null ? 'Add a photo' : 'Change photo',
                          sub: _photo == null
                              ? 'From this phone. Nothing is uploaded'
                              : _photo!.path.split('/').last,
                          onTap: _pickPhoto),
                      if (_photo != null) ...[
                        Divider(color: p.line, height: 1),
                        SetRow(LucideIcons.trash2, C.red, 'Remove the photo',
                            chevron: false,
                            onTap: () => setState(() => _photo = null)),
                      ],
                    ]),
                  ),
                  // Only when a map was expected AND is missing. A lift never
                  // had one to lose, and telling its owner the tiles failed
                  // would be explaining an absence that is not one.
                  if (_hasRoute && _mapTried_ && _mosaic == null) ...[
                    const SizedBox(height: S.x3),
                    const StatusCard(
                      'No map for this card',
                      'The map tiles could not be fetched, so the route is '
                          'drawn on its own. Everything else on the card is '
                          'unchanged.',
                      icon: LucideIcons.mapPinOff,
                    ),
                  ],
                  const SizedBox(height: S.x6),
                  // One button, and it is the system share sheet — which is
                  // where "story", "message" and "save" actually live. The
                  // four destination tiles that used to sit here were four
                  // integrations this app does not have.
                  BigButton(
                    'Share',
                    icon: LucideIcons.share2,
                    color: r.activity.color,
                    onTap: _share,
                  ),
                  if (r.private) ...[
                    const SizedBox(height: S.x4),
                    const StatusCard(
                      'This session is private',
                      'Hidden from summaries and exports.',
                      icon: LucideIcons.lock,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// that list answers about the numbers, and it must stay in step with `_art`.
/// The session's average pace in the reader's unit, or null when there is no
/// pace worth printing — the stat is then not offered at all rather than
/// offered with a placeholder in it.
String? _paceOf(ActivityResult r, UnitsController? u) {
  final secPerKm = r.paceSecPerKm;
  if (secPerKm == null) return null;
  final perUnit = u == null ? 1.0 : u.distanceUnitMeters / 1000;
  return UnitsController.formatPace(secPerKm * perUnit);
}

/// The stats a card may print, in offer order — the public name for
/// [_available], so the poster and the small card cannot drift apart about
/// what a session measured.
List<(String, String)> shareStats(ActivityResult r, [UnitsController? u]) =>
    _available(r, u);

/// The one big number, its unit, and the line under it. Public for the same
/// reason as [shareStats]: two styles describing one session must agree.
(String, String, String) shareHero(ActivityResult r, UnitsController? u) =>
    _heroOf(r, u);

/// The stats this session can honestly put on a card, in offer order.
///
/// [u] is the reader's unit system, null in a golden (and at the one call site
/// that only reads the stat NAMES, which no unit system changes) — metric is
/// what the store holds, so that is what a card without one shows.
List<(String, String)> _available(ActivityResult r, [UnitsController? u]) => [
  ('Time', hms(r.duration)),
  if (r.distanceKm != null)
    (
      'Distance',
      u == null
          ? '${r.distanceKm!.toStringAsFixed(2)} km'
          : u.distance(r.distanceKm! * 1000)!,
    ),
  if (_paceOf(r, u) != null)
    ('Pace', '${_paceOf(r, u)} /${u?.distanceUnit ?? 'km'}'),
  if (r.avgHr != null) ('Heart rate', '${r.avgHr} bpm'),
  // With its unit. A bare "612" on a card is a number nobody can read back.
  if (r.calories != null) ('Calories', '${grouped(r.calories!)} kcal'),
  if (r.gainM != null) ('Elevation', '+${r.gainM!.round()} m'),
  if (r.strength.volumeKg != null)
    ('Volume', '${grouped(r.strength.volumeKg!)} kg'),
  if (!r.strength.isEmpty) ('Sets', '${r.strength.setCount}'),
  if (r.lapCount != null) ('Laps', '${r.lapCount}'),
];


(String, String, String) _heroOf(ActivityResult r, UnitsController? u) {
  final fallback = (hms(r.duration), '', r.activity.name);
  final km = r.distanceKm;
  return switch (r.arch) {
    Arch.route || Arch.journey =>
      km == null
          ? fallback
          : (
              (u == null ? km : u.distanceValue(km * 1000))
                  .toStringAsFixed(2),
              u?.distanceUnit ?? 'km',
              r.gainM == null
                  ? r.activity.name
                  : '+${r.gainM!.round()} m elevation',
            ),
    Arch.strength =>
      r.strength.volumeKg == null
          ? fallback
          : (grouped(r.strength.volumeKg!), 'kg', 'Total volume'),
    Arch.laps =>
      r.swimMetres == null
          ? fallback
          : (grouped(r.swimMetres!), 'm', '${r.lapCount} laps'),
    Arch.interval || Arch.flow || Arch.match || Arch.basic => fallback,
  };
}

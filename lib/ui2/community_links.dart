// The project's public links — one place, shared by the profile screen's
// Community rows and the Home nudge (nudges.dart) that points at two of
// these.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

const kGithubUrl = 'https://github.com/OpenStrap/edge';
const kRedditUrl = 'https://www.reddit.com/r/OpenStrap/';
const kDiscordUrl = 'https://discord.gg/dUXds5MWkd';
const kSponsorUrl = 'https://github.com/sponsors/abdulsaheel';

/// Every link here is external — the browser/app the platform already picks
/// for that URL scheme, never a WebView inside this app.
Future<void> open3rdPartyLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// A brand mark (assets/icons/*.svg — official, single-fill-path logos),
/// tinted to match whatever accent its row is drawn in, same 16×16 as the
/// Lucide glyph it sits beside everywhere else in that list.
Widget Function(Color) brandGlyph(String asset) => (tint) => SvgPicture.asset(
      asset,
      width: 16,
      height: 16,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );

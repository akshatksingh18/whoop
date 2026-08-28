// The project's public links — one place, shared by the profile screen's
// Community rows and the two soft nudges (donate.dart, discord_nudge.dart)
// that point at the same two of these.

import 'package:url_launcher/url_launcher.dart';

const kGithubUrl = 'https://github.com/OpenStrap/edge';
const kRedditUrl = 'https://www.reddit.com/r/OpenStrap/';
const kDiscordUrl = 'https://discord.gg/dUXds5MWkd';
const kSponsorUrl = 'https://github.com/sponsors/abdulsaheel';

/// Every link here is external — the browser/app the platform already picks
/// for that URL scheme, never a WebView inside this app.
Future<void> open3rdPartyLink(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

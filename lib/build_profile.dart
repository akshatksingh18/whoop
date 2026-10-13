/// Build-time capability profile for Akshat's minimal iPhone sideload.
///
/// The public/upstream-capable source remains the default. The private manual
/// iOS workflow opts into this profile with `--dart-define-from-file=.env`.
const bool kPersonalSideload = bool.fromEnvironment(
  'PERSONAL_SIDELOAD',
  defaultValue: false,
);

/// Whether temperature-labelled rows/charts may appear (B88-01). The personal
/// build pairs a WHOOP 4.0, whose stored `skin_temp_*` history comes from an
/// unknown optical count, not a temperature; Akshat chose to hide those rows
/// while retaining the stored history. The upstream build keeps them (a gen5
/// strap's channel is verified).
const bool kShowSkinTemp = !kPersonalSideload;

/// Whether the band's own step counts may enter any step total. The personal
/// build counts phone steps only (Akshat, Build 89): he carries the phone on
/// every walk and run, and the wrist reads walks low. Band step rows are still
/// stored; they are never counted — not to fill time the phone did not cover,
/// not for a workout, not as a whole-day fallback. A day or workout the phone
/// did not measure has no step count ("—"), never a band one.
const bool kBandSteps = !kPersonalSideload;

/// The name a person sees, in every build: "WHOOP" on the home screen, so
/// nothing the app shows or names (exports, backups, logs) says OpenStrap.
const String kAppName = 'WHOOP';

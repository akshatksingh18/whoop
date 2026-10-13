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

/// The name a person sees, in every build: "WHOOP" on the home screen, so
/// nothing the app shows or names (exports, backups, logs) says OpenStrap.
const String kAppName = 'WHOOP';

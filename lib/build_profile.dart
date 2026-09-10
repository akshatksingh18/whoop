/// Build-time capability profile for Akshat's minimal iPhone sideload.
///
/// The public/upstream-capable source remains the default. The private manual
/// iOS workflow opts into this profile with `--dart-define-from-file=.env`.
const bool kPersonalSideload = bool.fromEnvironment(
  'PERSONAL_SIDELOAD',
  defaultValue: false,
);

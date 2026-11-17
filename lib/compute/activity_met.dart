// The catalogue's MET per stored `sessions.type` key, readable without the UI.
//
// `ui2/activity/catalogue.dart` owns the activity list (names, icons, METs).
// The data layer cannot import it, yet from Build 90 it stores the same active
// calories the screens show (`sessionActiveKcal`), which needs the MET. Same
// shape as `gps/route_types.dart`: one copy here, pinned equal to the
// catalogue by `activity_met_match_catalogue_test.dart`, so adding or
// re-pricing an activity without updating this table is a red test.

/// Compendium MET by `typeKey`; null where the catalogue names no activity.
const Map<String, double?> kActivityMetByKey = {
  'running': 9.8,
  'trail_running': 10.5,
  'walking': 3.5,
  'hiking': 6.0,
  'cycling': 8.0,
  'indoor_bike': 7.0,
  'rowing': 7.0,
  'swimming': 8.3,
  'elliptical': 5.0,
  'stair_climber': 9.0,
  'treadmill': 8.3,
  'jump_rope': 12.3,
  'weight_training': 6.0,
  'powerlifting': 6.0,
  'bodyweight': 4.5,
  'calisthenics': 5.0,
  'kettlebell': 8.0,
  'crossfit': 9.0,
  'hiit': 10.0,
  'circuit_training': 7.5,
  'functional': 5.5,
  'football': 8.0,
  'basketball': 8.0,
  'cricket': 5.0,
  'tennis': 7.3,
  'badminton': 5.5,
  'table_tennis': 4.0,
  'squash': 12.0,
  'volleyball': 6.0,
  'hockey': 8.0,
  'baseball': 5.0,
  'rugby': 8.3,
  'golf': 4.8,
  'bowling': 3.8,
  'boxing': 12.8,
  'martial_arts': 10.3,
  'wrestling': 6.0,
  'climbing': 8.0,
  'sprinting': 23.0,
  'track_intervals': 11.8,
  'cross_country': 9.0,
  'hurdles': 10.0,
  'long_jump': 6.0,
  'shot_put': 4.0,
  'javelin': 4.0,
  'pole_vault': 6.0,
  'mountain_biking': 8.5,
  'kayaking': 5.0,
  'surfing': 5.0,
  'paddleboard': 6.0,
  'skiing': 7.0,
  'snowboarding': 5.3,
  'skating': 7.0,
  'horse_riding': 5.5,
  'yoga': 3.0,
  'pilates': 3.8,
  'stretching': 2.3,
  'mobility': 3.0,
  'tai_chi': 3.0,
  'breathwork': 1.5,
  'meditation': 1.3,
  'housework': 3.3,
  'gardening': 3.8,
  'dog_walking': 3.0,
  'childcare': 3.0,
  'diy': 4.5,
  'shopping': 2.3,
  'stairs': 8.0,
  'general_workout': null,
  'dancing': 7.8,
  'intimacy': 5.8,
  'physiotherapy': 3.0,
  'sauna': 1.5,
  'cold_plunge': 2.0,
};

/// The catalogue MET for a stored type (case and spaces ignored, as
/// `activityByName` does). Null for an unknown type or one with no MET.
double? catalogueMetFor(String? type) => type == null
    ? null
    : kActivityMetByKey[type.toLowerCase().replaceAll(' ', '_')];

/// One projection for an accepted correction whose replacement is not usable.
/// Originals live in the transactional recovery ledger, never in current output.
class SleepCorrection {
  static const nightKeys = {
    'rhr',
    'rhr_nocturnal',
    'rmssd',
    'rmssd_whole',
    'rmssd_secondary',
    'rmssd_secondary_method',
    'ln_rmssd',
    'ln_rmssd_v2',
    'sdnn',
    'readiness',
    'resp_rate',
    'skin_temp_z',
    'skin_temp_adc',
    'skin_temp_coverage_frac',
    'skin_temp_settled_frac',
    'prsa_dc',
    'prsa_dc_anchors',
    'dip_pct',
    'sleeping_hr_nadir',
    'sleeping_hr_nadir_ts',
    'rem_min',
    'deep_min',
    'light_min',
    'tst_min',
    'lf_hf',
    'hrv_cv',
    'brv_cv',
    'brv_slope',
    'efficiency',
    'unobserved_min',
    'awakenings',
    'rr_omitted_share',
    'longest_sleep_min',
    'sol_min',
    'midsleep_sec',
    'sleep_onset_sec',
  };

  static Map<String, dynamic> unknown(
    Map<String, dynamic> old,
    Map<String, dynamic> intent,
  ) {
    Map<String, dynamic> block(String key) => old[key] is Map
        ? Map<String, dynamic>.from(old[key] as Map)
        : <String, dynamic>{};
    final note = intent['action'] == 'rejected'
        ? 'sleep_correction_rejected'
        : intent['pending'] == true
        ? 'sleep_correction_pending'
        : 'sleep_correction_no_replacement';
    final absent = <String, dynamic>{
      'value': null,
      'confidence': 0,
      'note': note,
    };
    final scalars = block('scalars');
    for (final key in nightKeys) {
      if (scalars.containsKey(key)) scalars[key] = null;
    }
    final clinical = block('clinical');
    for (final key in [
      'hrv_time',
      'hrv_freq',
      'cv',
      'irregular',
      'brv',
      'rmssd_sleep_session',
      'rmssd_nocturnal',
      'resting_hr',
      'hr_dip',
      'prsa_dc',
      'prsa_ac',
      'readiness_lnrmssd',
      'readiness_composite',
    ]) {
      if (clinical.containsKey(key)) clinical[key] = absent;
    }
    final series = block('series')..['hypnogram'] = <dynamic>[];
    final coverage = block('coverage');
    for (final key in [
      'rr_beats',
      'rr_reporting',
      'nn_clean',
      'clean_fraction',
      'sleep_seconds',
    ]) {
      if (coverage.containsKey(key)) coverage[key] = null;
    }
    return {
      ...old,
      'sleep': {'window': absent, 'accounting': absent},
      'sleep_source': intent['action'] == 'clear' ? 'auto' : intent['action'],
      'sleep_correction': {
        for (final key in ['generation', 'action', 'pending', 'usable'])
          key: intent[key],
      },
      'scalars': scalars,
      'clinical': clinical,
      'series': series,
      'coverage': coverage,
      'hrv_night_shape': absent,
      'respiration': {
        for (final key in {...block('respiration').keys, 'rsa'}) key: absent,
      },
      'readiness_absent_diag': {'sleep_correction': note},
      'absent_notes': {
        ...block('absent_notes'),
        for (final key in nightKeys) key: note,
      },
    };
  }
}

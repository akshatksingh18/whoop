// One independent cold launch with a stalled native display adapter.
import '../support/cold_boot_preference_case.dart';

void main() => coldBootPreferenceRecovery('none', holdOptionalService: true);

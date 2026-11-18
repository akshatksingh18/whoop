// A separate test isolate models one cold launch,not repeated runApp epochs.
import 'support/cold_boot_preference_case.dart';

void main() => coldBootPreferenceRecovery('units');

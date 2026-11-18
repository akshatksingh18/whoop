import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';

// Standalone forms retain their English copy without repeating literal strings.
// A supplied localization stays authoritative,including its locale and identity.
final _english = AppLocalizationsEn();

AppLocalizations withEnglishFallback(AppLocalizations? strings) =>
    strings ?? _english;

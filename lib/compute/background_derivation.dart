// background_derivation.dart — TOMBSTONE of the removed WorkManager scheduling.
//
// This file used to register two Android WorkManager periodic tasks (sync +
// heavy derive) at the 15-min floor with NO constraints (requiresCharging:
// false, requiresBatteryNotLow: false) and a dispatcher that initialized
// Firebase in every background isolate. `BackgroundDerivation.init()` was
// deliberately un-wired from main.dart (it collided with AppState's own
// persistent-connection background session — see the note there, "don't
// re-add"), which left the registration + dispatcher as dead code whose latent
// configuration was a battery disaster by construction if anyone ever re-wired
// it. It is deleted now; background derivation is owned by DeriveScheduler +
// DeriveDebouncer (background tier) on the persistent connection.
//
// ONLY the unique task names remain: main.dart cancels both by name on every
// Android cold start, because registrations persisted by the OS survive app
// updates. Keep the constants (and the cancel calls) until it is reasonable to
// assume no installed device still carries the old registrations.
//
// Public (not `_`-prefixed): main.dart needs these unique names to scope its
// startup cancelByUniqueName() cleanup to exactly these two tasks, without
// touching unrelated WorkManager jobs (e.g. the native KeepAliveWorker
// watchdog, which shares the same OS-level WorkManager instance and would
// otherwise get wiped by an unscoped cancelAll()).

const String kHeavyDeriveTaskName = 'openstrap.derive.heavy';
const String kSyncTaskName = 'openstrap.sync';

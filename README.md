# WHOOP companion

A personal iPhone app that talks to a WHOOP band over Bluetooth, decodes the band's own data on
the phone and works out recovery, strain and sleep there — no subscription, no account and no
backend. It started as a fork of [OpenStrap Edge](https://github.com/OpenStrap/edge) (MIT) and
has since been cut down and reshaped around one person's training, food and sleep.

It is not affiliated with, sponsored by or endorsed by WHOOP, Inc.; see [NOTICE.md](NOTICE.md).
It is a personal project built for one iPhone and sideloaded with a free Apple ID: there is no App
Store or TestFlight build, and none is planned. Every number is computed from the band's raw
signals by published methods; no parity with WHOOP's own algorithms is claimed.

## What it does

- **Today:** recovery, strain and sleep at a glance; live and all-day heart rate; steps from the
  iPhone's own pedometer; the day's food and maintenance calories; a bell with every
  notification the app has shown, by day, for 90 days.
- **Trends:** each metric over 7 days, 30 days and 3 months against its own history, and
  "What changed" — the week in review and anything unusual, day by day.
- **Sleep:** stages estimated on the phone, overnight heart rate, HRV and breathing, naps, and
  sleep times that can be corrected.
- **Food:** a diary with meals, saved foods and meals, quick add, barcode lookup (opt-in, against
  Open Food Facts) and calories and macros left for the day.
- **Train:** GPS runs and walks with the route, splits, best efforts, pace zones and spoken
  updates; lifts as timed sessions with a set log; pushup reminders; a recorded-activity streak.
- **Progress:** body weight, waist and photos, and a goal check that says when it can first judge
  and what it still needs.
- **Units:** weight, distance and height are chosen separately, and runs and walks follow the
  distance unit throughout, splits included.

## Your data stays on the phone

Everything is stored in a local SQLite database and computed on the device. There is no
telemetry, no analytics, no crash reporting and no account. The app makes two kinds of network
request, neither carrying health data: Apple Maps draws the map under a recorded route, and a
scanned barcode is looked up on Open Food Facts once you have agreed to it. Backups are encrypted
with a passphrase and kept in the app's folder in Files; exports are spreadsheets you open
yourself.

## How it is built

- **Flutter** app at the repository root; the Bluetooth codecs live in
  [`packages/protocol`](packages/protocol) and the metric engine in
  [`packages/analytics`](packages/analytics), both from OpenStrap.
- **Bands:** WHOOP 4.0 is the one used every day; the WHOOP 5.0 decoder is kept but less tested.
- **CI on GitHub Actions:** Linux runs the analyzer, the app's full suite and independent
  protocol/analytics package suites. App checks retain instrumented Dart line coverage, which
  identifies exercised code rather than proving every line or native behavior. A parallel visual job retains full-scroll
  page/form captures and checks layout at normal and enlarged text; these do not replace native
  iPhone acceptance or a pixel baseline. A manual macOS workflow builds the unsigned iPhone IPA from the
  committed Xcode project, checks it carries nothing but the app (no extensions, no HealthKit, no
  secrets) and publishes it with a checksum.
- **Install:** the IPA is signed and installed from Windows with Sideloadly and refreshed every
  seven days ([guides/IOS_SIDELOAD.md](guides/IOS_SIDELOAD.md),
  [guides/IOS_INSTALLATION.md](guides/IOS_INSTALLATION.md)).

## Repo layout

```
lib/ble/       Bluetooth link and the history-sync state machine
lib/compute/   runs the analytics pipeline and writes results
lib/data/      local storage and the repository the screens read from
lib/gps/       route recording, splits, best efforts and spoken updates
lib/import/    backup restore and data import
lib/l10n/      translations
lib/models/    shared models
lib/notify/    the single notification emitter, alert policies and the notification log
lib/platform/  phone pedometer, signing profile, error log
lib/state/     AppState and the unit, theme and locale choices
lib/sync/      background and headless sync
lib/theme/     design tokens and theming
lib/ui2/       every screen
ios/           the iPhone app (Runner only)
packages/      protocol codecs and the analytics engine
tool/          the iPhone build contract and helpers
```

`CLAUDE.md` holds the architecture map, the invariants the code keeps and how changes are
reviewed.

## Licence

MIT, as the OpenStrap projects it comes from: see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
The protocol and analytics packages keep their own licence files.

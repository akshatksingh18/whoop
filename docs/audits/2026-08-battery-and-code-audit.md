# Battery & code audit — 2026-08-19

**Trigger:** Pixel reports Edge as the top battery consumer without the app being
opened. **Scope:** full repo — battery drain first, plus custom code replaceable
by stdlib/native/in-repo helpers (the ponytail ladder, `.claude/skills/ponytail/`).
**Method:** 7 subsystem reviews (BLE engine, Android native, sync/lifecycle,
PR #256 diff, notify/widgets, data/import, compute/GPS) → adversarial
verification of every critical/high finding → fixes → 3 independent review
passes over the resulting diff. 46 raw findings; 12 verified deeply, 2 refuted.

Some Edge attribution is by design — a permanent foreground service holding a
BLE link is billed to the app. The audit's target was the avoidable part.

## Exonerated

- **PR #256 (live HR card)**: pure renderer; arms nothing; no timers, no new
  BLE traffic. The background HR stream predates it (2026-07-05).
- **WorkManager derive tasks**: never scheduled in the shipped app —
  `BackgroundDerivation.init()` had no callers and main.dart cancels the old
  persisted registrations by name on every cold start.

## Confirmed drains fixed in this change set

Each row's drain path is fixed here; where a residual remains (row 6: the native
plugin still processes every notification even with the relay off), it is listed
under Follow-ups, not claimed fixed.

| # | Finding | Fix |
|---|---------|-----|
| 1 | Backgrounded "HR-only" live mode kept a 1 Hz BLE notification armed 24/7 with zero consumers — ~86k CPU wakes/day (decode → state mutation → `notifyListeners`), plus a blind `toggleRealtimeHr` re-arm write every 30 s | Android: live fully OFF while backgrounded with no consumer (`_maybeDowngradeLiveForBackground`, background reconnect, and the gesture-stopped-workout path). Liveness: keep-alive forces the battery poll past 45 s silence; resume staleness uses a 90 s no-stream bar (`isLinkStale(liveStreamArmed:)`). iOS keeps HR-only — the inbound 1 Hz notification is what keeps the suspended process schedulable; iOS background cold-launch now arms it too (it previously armed nothing). Re-arm is now evidence-gated on `liveHrAt` staleness |
| 2 | Derive gate was iOS-only: Android ran a light pass (isolate spawn + day recompute + Firebase trace) every ~5 min all night, and a heavy pass per reconnect on a flappy link | `DeriveDebouncer` background tier (quiet 20 min / max-wait 45 min); background reconnect heavy throttled to 1/30 min (light otherwise); Firebase trace only on heavy/force passes. The debouncer's 2 s poll became a computed one-shot (`nextCheckDelay`), poked on `setBackground` so foreground still derives in ≤15 s |
| 3 | Health export delete+rewrote the entire non-finalized day (hourly buckets, sleep, minute-HR) every drain/derive pass — success had no throttle by design | 30-min success-side floor per non-finalized day (`ok_ms` in the existing retry-state JSON). Finalization and `forceRetry` bypass; finalized-prefix cursor semantics unchanged |
| 4 | Full FlutterEngine + Dart `main()` on EVERY process start, and four background triggers start the process (15-min KeepAliveWorker even when unpaired, two 30-min widget alarms serving a 24–26 h staleness bit, CDM binds on routine dropouts, Tasker) | Engine is lazy (`EdgeApplication.ensureEngine`) — created from MainActivity and the tracking service (after `startForeground`); widget/worker/CDM/Tasker wakes run zero Dart. KeepAliveWorker paired-gated + self-cancels when unpaired + re-scheduled from `onStartCommand`. Widget alarms 30 min → 6 h. CDM start guarded on `EdgeTrackingService.running` |
| 5 | Bluetooth-off nights: failing `connect(autoConnect:true)` arm every ~5 s, forever | Adapter-off parks on the native `adapterState` stream (event-driven); arm failures get `ReconnectPolicy` backoff; the OS-autoConnect cancellation poll went 5 s → 60 s |
| 6 | Notification relay held the stream + a 120 s heal timer even with zero apps selected (every phone notification crossed into Dart before filtering) | Gate on `active` (includes non-empty package list); heal 120 s → 15 min. Native-side filtering needs the vendored listener (follow-up below) |
| 7 | Sustained small wakers: 10 s LINK_VALID writes all night; per-line fsync unbounded sync log; ~15 binder calls + Watch sync per unchanged derive; 10-min wake-window DB re-plan; 1-min reconnect supervisor; per-tick RegExp/prefs work in `_onEngineState`; step-sensor prefs-file rewrite per minute | Heartbeat 60 s in background; FileLog 2 MB rotation, no per-line fsync; widget push fingerprint-gated; wake-window re-plan 25 min in background; supervisor 5 min; strap-name change-gated + hoisted regexes + minute-gate on the battery forecast; step sensor batches at 5 min (matches its 5-min bins) |

## Replace-with-native / correctness (ponytail rungs 2–5)

- whoop_import's line-based CSV reader tore quoted embedded newlines → now the
  repo's RFC 4180 `parseCsv` (journal_csv_import). Known regression: lone-CR
  (classic Mac) line endings — inert for machine-generated exports.
- Hand-rolled deep-equals → `package:collection` `DeepCollectionEquality`
  (now a direct dep).
- Duplicated day-label formatting → `dayLabelOf`/`todayLabel` (day_label.dart).
- 4× hand-rolled `SDK >= O` service-start branches → one
  `EdgeTrackingService.start` on `ContextCompat.startForegroundService`.
- `String.format` without a locale on the widgets → `Locale.ROOT`
  (mixed digit-systems on ar/fa/bn).
- min/max reduce lambdas → `dart:math`.
- `background_derivation.dart` gutted to a tombstone: only the task-name
  constants main.dart's cancel-migration needs survive.
- Live-HR trace now clears on disconnect (two sessions no longer splice into
  one chart); route recording no longer copies the whole vertex list per GPS
  fix (`pathEmitEvery`, ~1/s, final emit on stop).

## Deliberate semantic changes

- Widget `updated_at` now means "last **value** change", not "last push" —
  natives may flip to no-data up to ~half a day earlier when data genuinely
  stops. Arguably more honest; noted in OpenStrapWidget.swift.
- An engine-less process start can delay relay buzzes ≤15 min (CDM presence or
  the KeepAliveWorker recovers it). Documented in EdgeApplication.
- On Android in background, `state.wristOn`/`liveHr` stop updating in realtime;
  wrist state still lands via the historical records each backfill round.

## Follow-ups (found, not implemented)

1. **Vendor a ~100-line native NotificationListenerService** with native-side
   package filtering. The plugin extracts/compresses icons and pictures for
   EVERY phone notification (even with the relay toggle off — the OS keeps the
   listener bound while the grant exists), and the heal path drives the
   plugin's private channel handlers (an API contract it never made). Biggest
   remaining per-notification cost on chatty phones; needs device testing.
2. **Stream the telemetry `.db` upload** (health_uploader buffers the full
   snapshot + its gzip in memory; auto_backup already streams the identical
   pipeline). OOM risk on large DBs, not battery — upload is charging+Wi-Fi
   gated.
3. **`DrainController.awaitComplete`**: 1 s poll → Completer completed from
   `onComplete()`/`onLinkDown()` (bounded to active bursts; low value now).
4. **Standing reminders** re-cancel 27 ids + re-arm ~24 alarms per foreground
   resume — fingerprint-skip when nothing changed.
5. **PhoneStepCounter storage**: prefs holds ~2,880 bucket keys rewritten per
   batch; a small SQLite table would make each batch one row upsert.
6. **Live-workout 1 Hz UI tick** keeps ticking while backgrounded mid-workout —
   pause/resume via lifecycle observer (elapsed is wall-clock-derived, loss-free).
7. `docs/internal/GATES.md` is referenced from code comments but absent from
   the repo.

## Maintainer considerations

- **Measure the win.** A before/after night of `adb shell dumpsys batterystats`
  (or Battery Historian) on a Pixel would quantify this change set — the
  dominant fixes (1 Hz stream off in background, ~5-min derives → ~45-min,
  engine cold-boots eliminated) predict a large drop, and a number makes both
  the release note and any regression later measurable.
- **Revisit the Doze-exemption steering.** Onboarding pushes users into the
  battery-optimization exemption; that was necessary while the design depended
  on unthrottled background work, and it also amplified every waste this audit
  removed (the exemption is why Doze never damped any of it). Still worth
  keeping for link survival, but the strength of the steering copy can be
  softened once lower drain is confirmed on-device.
- The two entries under *Deliberate semantic changes* (widget `updated_at`
  meaning, realtime `wristOn` in background) are judgment calls that deserve
  explicit maintainer sign-off, not silent acceptance.
  **Sign-off status: PENDING** — owner: the repo maintainer, via review of
  PR #262. This audit is not "complete" until that review records accept/revert
  on each; update this line with the decision (and PR link) when it lands.

## Verification status

No Flutter toolchain on the audit machine — the diff was verified by three
independent full-file review passes (compile-surface + call-site + test-impact)
instead of `flutter analyze`. Known test surface: five route_tracker tests take
`pathEmitEvery: Duration.zero`; everything else was checked call-site-compatible.
CI is the real gate.

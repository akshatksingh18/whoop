# Tasker integration — buzz your strap, and hear back

OpenStrap Edge can vibrate your WHOOP strap in response to a Broadcast intent
from Tasker (or any automation app). Use it to buzz the strap for phone calls,
timers, geofences — anything Tasker can react to.

Android only. The app must be paired with your strap, and the strap must be in
BLE range for the buzz to fire (if the app was killed, the buzz is queued and
delivered once it reconnects).

## What you need from the app

Open **Settings → Automation** in OpenStrap Edge. You'll find:

- The broadcast action: `wtf.openstrap.openstrap_edge.BUZZ_STRAP`
  (long-press the row to copy it)
- Your **automation token** — a per-install secret (long-press to copy).
  Broadcasts without a matching token are silently ignored, so nothing else
  on your phone can buzz your strap.

## Setting up the Tasker action

Create a Task and add an action: **System → Send Intent**. Fill it in like
this:

| Field | Value |
|---|---|
| Action | `wtf.openstrap.openstrap_edge.BUZZ_STRAP` |
| Package | `wtf.openstrap.openstrap_edge` |
| Extra | `token:YOUR_AUTOMATION_TOKEN` |
| Target | **Broadcast Receiver** |

Common mistakes, since Tasker's form makes them easy:

1. **Action goes in the Action field** at the top — not in Package, and not
   in an Extra.
2. **Package is just the app package** (`wtf.openstrap.openstrap_edge`), not
   the full action string. It must be set: the app rejects broadcasts that
   aren't explicitly targeted at it.
3. **Extras use `key:value` format.** The token extra must literally read
   `token:YOUR_AUTOMATION_TOKEN` (with your token pasted after the colon).
   If the `token:` key is missing, the app never sees a token and refuses
   to buzz.
4. **Target must be Broadcast Receiver** — scroll down past Package to find
   it. Activity or Service won't reach the app.

Wire the Task to whatever Profile you like (event, time, state) and it
should buzz.

## Choosing a vibration pattern

Optionally add a second Extra to pick a different haptic pattern:

```text
pattern:1
```

It's an int; the default is `2` (a quick double buzz) when the extra is
omitted. `pattern:1` buzzes until acked by tapping the strap, which makes it
ideal for phone-call notifications. See [BUZZ_MEANINGS.md](BUZZ_MEANINGS.md)
for the full list.

## The other direction: OpenStrap tells Tasker

**Android only.** iOS does not get this and is not going to: a Shortcuts
personal automation can only trigger on a fixed system list of events, and
there is no public mechanism for an app to add one. Donating an intent buys
Siri suggestions and discoverability, not a trigger. So on iOS you get more
things *you* can invoke; you do not get events that invoke *your* shortcut.

One event ships today. When an offload from the strap finishes, the app sends
a broadcast:

| Field | Value |
|---|---|
| Action | `wtf.openstrap.openstrap_edge.SYNC_COMPLETE` |
| Extra `records` | int — how many records that sync stored |
| Extra `at` | int — unix seconds when it finished |

Catch it with a Tasker Profile → **Event → System → Intent Received**, with
Action set to the string above. Leave Package empty.

Rate-limited to one outbound event a minute, so a reconnect storm cannot spam
your profile.

### What the extras deliberately do not contain

No token. This is an implicit broadcast, so anything on your phone can read
the extras — putting your buzz token in there would hand every installed app
the ability to buzz your strap, which is the one thing that token exists to
stop. There is nothing to protect in this direction: the worst a forged
`SYNC_COMPLETE` can do is run your own profile early.

No readiness, no recovery, no strain, no sleep. Those numbers are sometimes
*absent* — not zero, absent, with a reason attached — and the app shows you
which. Once a number leaves the app that context is gone, and a Shortcut that
received `readiness=0` would have no way to tell "you scored zero" from "we
did not measure it". Only facts about the sync itself go out.

## Troubleshooting

- Rapid repeat broadcasts are rate-limited (about 1.5 s between accepted
  buzzes) — a tight Tasker loop won't buzz on every iteration.
- If nothing happens, check `TaskerReceiver` lines in logcat: it logs why a
  broadcast was rejected (wrong target, missing/incorrect token, or
  rate-limited).

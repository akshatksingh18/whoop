# Home Workout In Train (proposal)

**Status:** Planned for Build 90 (Claude lane), awaiting the build's go-ahead; no code exists.
The source audit and the smallest changes are in `todo.md` ("Home bodyweight workout"), which
supersede points 2 and 3 below: variations live inside one exercise through its existing setup
note, now labelled Variation, and a blank Added weight logs a bodyweight-only set, with no new
load mode. The original analysis is kept below for context.

## Idea

Akshat wants a home bodyweight workout in the Train tab for rest days and for days the gym is
skipped. The routine is five exercises: push-ups (hardest version he can do), rows, dips, split
squats and a core exercise, 2-3 sets each, taken 1-2 reps short of failure. He has only the floor,
a bed edge and a loaded backpack, so the progression is harder variations, not heavier plates.

## Analysis: mostly already built

`lift-log-integration-plan.md` says the Lift flow already covers `bodyweight` and `calisthenics`
activity types (`isLiftType`) with saved splits, Empty workout, set logging with the band
disconnected, previous-performance lookup and one combined summary. So the first answer is a saved
split, not a new section:

1. **A "Home full body" split** (or "Home") under the existing Calisthenics/Bodyweight activity type.
   Zero schema change if the exercise modes below are already supported.
2. **Exercise names encode the variation.** Last-performance lookup keys on normalized name plus
   load mode, so "Push-up", "Push-up, feet raised" and "Close-grip push-up" must be separate
   exercises. Harder variation means a new name; same name means comparable.
3. **Load modes to verify, not assume.** Known modes: plates per side, per hand, stack setting,
   added bodyweight load, weight loaded, known total. Check whether a reps-only set (no load) is
   already valid for push-ups, rows and split squats; if not, a minimal "Bodyweight (reps only)"
   mode is the one addition. Use "added bodyweight load" for a backpack. A plank needs seconds;
   prefer a reps-based core move (leg raises) before adding a timed mode (ponytail: YAGNI).
4. **Quick entry.** The routine is short and done between study blocks. It must be possible to start
   with no band, log sets fast (repeat last set exists), and finish without a long summary.
5. **Do not add:** target reps, RPE/RIR, programming, progression suggestions, volume totals across
   modes, or 1RM. The integration plan lists these as deferred; they would need separate approval.

## Open decisions for Akshat

- A home session counts as lifting for weekly frequency, or is shown as a separate "Home" count?
  The fitness plan counts gym lifts as the training sessions; home work is supplementary.
- Whether reps-only needs a new mode, or an existing mode with an empty load is acceptable.
- Whether a timed hold (plank) is wanted at all in the first version.
- How home sessions are marked in history (split name only is enough).

## Acceptance criteria

- A Home split can be created in two minutes, started without a band, logged set by set, finished,
  and appears in Train history with the split name.
- Last-performance shows the previous sets of the same exercise name and mode.
- Existing Lift Log behavior, data and exports are unchanged; no new entitlement, schema break or
  notification owner.
- No copied personal data in the public repository; no new calorie model (the single lifting
  estimate stays as is, separate from maintenance).

## Brief to give the WHOOP session

> Read `CLAUDE.md`, `todo.md`, `lift-log-integration-plan.md`, `fitness-app-plan.md` and
> `build-90-audit.md`. I want a home bodyweight workout in Train for rest days and skipped gym days:
> push-ups, rows, dips, split squats and a core move, 2-3 sets each. First report, without writing
> code, whether a saved split under the bodyweight/calisthenics activity can already do this:
> reps-only sets, "added bodyweight load" for a loaded backpack, repeat last set, no band, same-name
> previous performance. List exactly what is missing and the smallest change that fixes it. Make
> variations separate exercise names. Do not add programming, RPE, targets, or new calorie logic.
> Follow the ponytail skill, keep Build 89's gates intact, and add the item to `todo.md` for my
> approval before implementing.

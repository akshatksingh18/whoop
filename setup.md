# Local Repository Setup

## Current repository state

This folder is one Git repository on `main`. It preserves the OpenStrap histories and currently
contains:

- edge base `daf6011d3aa0312e22b991713b7af9e5c4433b32`
- protocol `471034cb84b85edb37e72b6f6add79a2d7929294` under `packages/protocol/`
- analytics `1fa8144a5e3b728ce91eeed6ecbc15d482933b44` under `packages/analytics/`

The official sources are named `upstream-edge`, `upstream-protocol`, and `upstream-analytics`.
There is deliberately no `origin`: creating a private repository on Akshat's main GitHub account,
adding it as `origin`, and pushing are a separate future phase.

The app's `pubspec.yaml` uses tracked local paths for both packages, so a checkout of this one
repository is self-contained. Do not restore floating Git refs or create a
`pubspec_overrides.yaml` for the imported packages. `packages/upstream-revisions.yaml` records the
reviewed source revisions and must move with any deliberate package update.

## First local build (not run yet)

Flutter and Dart were not available on `PATH` during repository setup. After installing a Flutter
SDK compatible with the project's constraints, run from this repository root:

```bash
cp .env.example .env
flutter pub get
flutter analyze
flutter test
```

`.env` is ignored. Keep provider keys, signing material, device exports, BLE captures, databases,
health records, and other personal data out of Git. The checked-in analytics CSVs are upstream
test fixtures, not Akshat's personal health exports.

## Updating from OpenStrap

Fetch and review each named upstream independently. Protocol or analytics changes must be merged
into their existing package histories and reviewed together with the app behavior they affect.
Never copy a floating upstream worktree over a package, and never change an algorithm revision
without following `AGENTS.md`'s `kAlgoVersion` requirements.

## Deferred private GitHub and iOS pipeline

No GitHub repository, authentication, personal remote, or push is part of this setup. When a
private repository is created later, GitHub Actions usage will be metered; macOS runners consume
substantially more billed minutes than Linux runners.

The intended iOS experiment remains: run `flutter build ios --no-codesign` on a macOS runner,
package the unsigned app as an artifact, download it on Windows, and sideload it with Sideloadly.
That workflow and any Apple/GitHub credentials must be configured only in the future private
hosting phase.

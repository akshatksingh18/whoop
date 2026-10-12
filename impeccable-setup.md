# Impeccable Design Tooling

**Status:** Requested tooling installed locally and executable verified. Claude project hooks
are enabled; the Codex project manifest and native context adapter are installed. Codex first-use
trust and actual automatic delivery in a WHOOP-rooted session are not verified.
The native Flutter design audit remains necessary because the web detector does not audit Dart.
No production app, metrics, permissions, version or IPA changed through this setup.

## Installed Source

- Canonical skill: `.claude/skills/impeccable/`, shared through the `CLAUDE.md` instruction chain.
- Upstream: [pbakaus/impeccable](https://github.com/pbakaus/impeccable), pinned source commit
  `c63b8dd7dd5a5f3c32eaabe1af76d0694f863ed2`; installed skill version `4.5.2`.
- Windows x64 engine: `0.1.14`, read from the pinned launcher's `scripts/VERSION`.
- Engine location: `.claude/skills/impeccable/scripts/bin/windows-x64/impeccable.exe`.
- Release: `https://github.com/pbakaus/impeccable/releases/download/engine-v0.1.14/impeccable-windows-x64.exe`.
- SHA-256: `38e09451694973ba664a24e67e1502a6913e6d0e533a0a5ae1e04c5963a804b1`;
  19,219,856 bytes, checked against the release's `.sha256` before execution.
- Apache licence and upstream `NOTICE.md` are retained in the skill folder. The skill-installer
  copied pinned source without running an npm installer; no global package or browser extension
  was installed. No source or health data was uploaded.

Hash matching establishes downloaded-file integrity against that release, not independent
publisher verification or proof that all upstream code is safe. Updates require a deliberate
source/version review; do not run a floating update as a side effect of design work.

## Commands And Boundaries

Run from the WHOOP repository in PowerShell:

```powershell
& powershell.exe -NoLogo -NoProfile -NonInteractive -File '.\tool\impeccable-hook.ps1' -Mode engine-probe
& '.\.claude\skills\impeccable\scripts\impeccable.cmd' context --target lib/ui2/screens/home_screen.dart
& '.\.claude\skills\impeccable\scripts\impeccable.cmd' hooks status
```

Run the checksum-pinned probe first. The direct launcher commands are manual operations after
that check; unlike the hook wrapper, upstream launchers can download a missing binary. Stop and
repair an absent installation with explicit network approval rather than triggering that path.

Load context once per design session, then read the relevant installed playbook. Build 88 must
use Impeccable's native `shape`, critique/audit, distill/clarify, layout/colour and harden/polish
discipline, with the selected direction reviewed before production changes. A command name is
not evidence that its audit has run. The command-menu references define agent workflows; not
every menu item is a standalone binary subcommand.

The engine probe returned `impeccable-engine 0.1.14`. The initial context command succeeded,
but correctly found no product adapter and therefore could not identify iOS. Lowercase
`product.md` now declares `ios` using the upstream's accepted filename/schema and links the
owning documents rather than duplicating their feature/status inventory. The installed native
reference was read directly after adding it; no repeat context run or design choice is claimed.
No accepted `DESIGN.md` or visual direction is invented
by installing tooling.

Use the bundled local executable, not an arbitrary PATH version or remote script. A missing
binary is a setup failure to repair deliberately, not permission for an automatic network
download during an edit hook. Do not enable image APIs, browser asset fetching, cloud services,
telemetry or uploads from the existence of this skill. Native iPhone design does not need a
web preview server or a DOM scanner. The app remains independent of this developer tooling.

## Hooks

`impeccable hooks on` enabled `.impeccable/config.json`, recorded local consent in
`.impeccable/config.local.json` and installed `.claude/settings.local.json`. Existing unrelated
hooks/settings must be preserved. Codex requires its own project-native manifest; a Claude
manifest does not prove that Codex is invoking the hook. `.codex/hooks.json` adapts the pinned
upstream event/matcher manifest, including a Windows command and PostToolUse/Stop events. Both
providers invoke `tool/impeccable-hook.ps1`, which verifies the pinned binary hash and runs it
directly with the canonical skill context. It has no downloader, PATH fallback, execution-policy
bypass or external command from hook input. Missing/changed binary refuses execution.
Non-Windows Codex hosts receive a setup notice, not an implicit install.

All four provider/config JSON files parse. The wrapper engine probe returns version 0.1.14,
and synthetic PostToolUse/Stop wrapper commands exit 0. The Windows sandbox refused the initial
PowerShell-script run; a permitted unsandboxed verification passed without changing execution
policy or other security settings. No Dart findings are expected from this web detector;
passing commands are configuration validation, not a native design pass or automatic delivery.

Official OpenAI hook documentation confirms project trust and exact-definition review through
`/hooks`. The existing install was explicitly requested in this chat; no additional install
authorization is missing. Approve only this
reviewed project wrapper when prompted in a WHOOP-rooted session. That host trust step cannot
be bypassed or claimed complete here. Actual automatic event delivery is still unverified.
[Official hook documentation](https://learn.chatgpt.com/docs/hooks)

The direct native-skip Stop probe returns exit 0 with empty stdout. Official documentation
expects JSON for successful Stop output; process exit alone has not validated host acceptance.
Before relying on Stop automation, test that contract in the actual host and normalize an empty
native-skip response to a valid no-op JSON object if needed. No wrapper/config change was made
by this audit, and no trust bypass is permitted. Tooling remains advisory, not an app-build blocker.

Hooks are scoped to WHOOP, not other workspace domains. A task rooted at `D:\AI Important Files`
may not discover a child repository's project hooks; use a WHOOP-rooted task for automatic
execution, and state when this session uses direct CLI probes instead. Do not install a global
or workspace-wide hook to work around that without a separate scope decision.

The upstream per-edit/Stop detector is for supported web extensions. It does not validate Dart
widgets, native gestures, Bluetooth or health algorithms. Keep the native platform declaration
so web checks are not misreported as Flutter quality evidence. Native review means source,
Flutter layout/semantics tests, Simulator/phone captures and real hardware behavior; any
automatic native reminder is only a reminder, not a passed audit.

Generated local consent/cache/logs, licence-preserving binaries and test scratch output must
stay out of public Git. Shared source, reviewed manifests and reproducibility instructions may
be versioned with a later implementation commit; no publication is requested by this setup.

## Build 88 Readiness Gaps (Checked Against Skill 4.5.2)

These limits shape how B88-09 can use the tool; `build-88-plan.md` owns the resulting route.
- **No finish reviewer.** The skill's finish review spawns an `impeccable-finish-reviewer` agent,
  and its asset step an `impeccable-asset-producer`. Neither is installed (no `.claude/agents/`):
  only the skill folder was copied. Installing the pinned upstream agent definitions needs a
  separate approval. Until then, use the bundled `reference/degraded/finish-reviewer.md` in a fresh
  session and disclose the substitution.
- **No iOS Simulator.** The iOS reference verifies with `xcrun simctl` screenshots, which a Windows
  machine cannot run. Evidence will come from Flutter render/golden captures at iPhone 17 logical
  size (dark mode, large text, synthetic data) plus Akshat's phone screenshots, each labelled by
  source. A macOS CI Simulator capture would be a new workflow needing approval and must use
  synthetic data only, because the repository is public.
- **Code-led only.** No image-generation tool or API is approved. Palette/fact cards can help
  choose a visual world, but cannot establish structural design acceptance. Pair them with
  actual phone-sized Flutter task composition renders using synthetic data, not another swatch-only
  makeover. These preview artifacts are not production UI or native hardware verification.
- **`DESIGN.md` is locked** (2026-10-12) with the approved screen set.
- **The hook does nothing for Dart.** If delivered, the configured commands return no native
  findings. Stop's 30 seconds is a timeout ceiling, not a mandatory run duration; this chat has
  not proven automatic delivery. Akshat may optionally run
  `impeccable hooks off` during Flutter-only build work to avoid that overhead. This is a
  decision, not a requirement.

## Verification And Recovery

Verify executable identity and JSON shape, direct synthetic hook events and relevant session
trust state separately. A passing direct probe is not proof of automatic delivery in this chat.
Never disable host security or bypass a hook trust prompt. Failed hooks must not corrupt files,
change health results or repeatedly prevent completion over a speculative design warning.

The upstream `hooks on` installer may restore its default launcher commands. After any deliberate
tool update/reinstall, recheck these offline wrapper bindings before approving/running hooks.
Disable via `impeccable hooks off`; verify that unrelated hooks remain. Do not use broad `reset`
or delete provider directories merely to disable this one tool. Keep installed source/licence
and pinned engine until an explicit update or uninstall. `todo.md` owns Build 88 acceptance;
this guide owns tooling setup, not feature implementation progress.

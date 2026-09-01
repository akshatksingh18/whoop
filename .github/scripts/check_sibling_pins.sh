#!/usr/bin/env bash
# Shared by test.yml (test job) and build.yml (preflight job) — a release
# tagged straight off main never runs test.yml, so this guard has to live in
# both places to protect a release.
#
# The repositories used to resolve protocol and analytics from Git refs. They
# now live under packages/, but the original failure classes still matter:
# an accidental override can change dependency resolution, a package update can
# omit the algorithm provenance change, and upstream can move without anyone
# noticing. This guard checks the tracked paths, lockfile, reviewed revision
# manifest, and kAlgoVersion provenance constants together.
set -euo pipefail
fail=0

if [ -e pubspec_overrides.yaml ]; then
  echo "::error::pubspec_overrides.yaml is present in CI."
  echo "::error::The monorepo must resolve its tracked packages directly."
  fail=1
fi

for pkg in openstrap_protocol openstrap_analytics; do
  case "$pkg" in
    openstrap_protocol)
      repo="protocol"
      expected_path="packages/protocol"
      revision_key="protocol"
      constant_name="kProtocolPin"
      ;;
    openstrap_analytics)
      repo="analytics"
      expected_path="packages/analytics"
      revision_key="analytics"
      constant_name="kAnalyticsPin"
      ;;
  esac

  dep_block=$(awk -v p="  $pkg:" '$0==p{f=1;next} /^  [a-z_]+:/{f=0} f' pubspec.yaml)
  declared_path=$(printf '%s' "$dep_block" | grep -E '^\s+path:' | head -1 | awk '{print $2}' || true)

  lock_block=$(awk -v p="  $pkg:" '$0==p{f=1;next} /^  [a-z_]+:/{f=0} f' pubspec.lock)
  locked_path=$(printf '%s' "$lock_block" | grep -E '^\s+path:' | head -1 | awk '{print $2}' | tr -d '"' || true)
  lock_source=$(printf '%s' "$lock_block" | grep -E '^\s+source:' | head -1 | awk '{print $2}' || true)
  lock_relative=$(printf '%s' "$lock_block" | grep -E '^\s+relative:' | head -1 | awk '{print $2}' || true)

  reviewed=$(awk -v key="$revision_key:" '$1==key {print $2}' packages/upstream-revisions.yaml)
  constant_value=$(grep -E "^const String $constant_name = '[0-9a-f]{40}';$" \
    lib/compute/derivation_engine.dart | head -1 | sed -E "s/.*'([0-9a-f]{40})'.*/\1/" || true)

  if [ "$declared_path" != "$expected_path" ]; then
    echo "::error::pubspec.yaml resolves $pkg from '$declared_path', expected '$expected_path'."
    fail=1
  fi
  if [ "$locked_path" != "$expected_path" ] || [ "$lock_source" != "path" ] || [ "$lock_relative" != "true" ]; then
    echo "::error::pubspec.lock does not match the tracked path for $pkg."
    fail=1
  fi
  if ! printf '%s' "$reviewed" | grep -qE '^[0-9a-f]{40}$'; then
    echo "::error::packages/upstream-revisions.yaml has no full reviewed SHA for $repo."
    fail=1
    continue
  fi
  if [ "$constant_value" != "$reviewed" ]; then
    echo "::error::$constant_name disagrees with the reviewed $repo revision."
    echo "::error::Review kAlgoVersion and move the source, manifest, and constant together."
    fail=1
    continue
  fi

  echo "$pkg uses $expected_path at reviewed revision $reviewed."

  # This probe is advisory. A deliberate lag can be valid, and a network
  # failure must not block an otherwise-good test or release.
  if upstream="$(timeout --kill-after=5s 30s git ls-remote "https://github.com/OpenStrap/$repo.git" refs/heads/main 2>/dev/null | awk '{print $1}')" \
      && [ -n "$upstream" ]; then
    if [ "$upstream" != "$reviewed" ]; then
      echo "::warning::$pkg is imported at $reviewed but $repo main has moved to $upstream."
      echo "::warning::Confirm the lag is deliberate before the next package update."
    fi
  else
    echo "::warning::could not reach $repo main to check revision staleness — not failing the build."
  fi
done

[ "$fail" = 0 ]

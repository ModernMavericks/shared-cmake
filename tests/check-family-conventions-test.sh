#!/bin/sh
# The conventions gate. Each check must fail on its own, and a compliant repo must pass cleanly.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-family-conventions.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

mkrepo() {  # $1 = dir
  mkdir -p "$1/.github/workflows" "$1/tests"
  cat > "$1/.github/workflows/release.yml" <<'YML'
name: release
on:
  push:
    tags: ['*-mavericks.*']
concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false
jobs:
  build:
    steps:
      - run: sh "$MSC_SCRIPTS/run-repo-tests.sh"
      - run: gh release create "$TAG" dist/* --notes-file "$NOTES"
YML
  printf '# Build ingredients\n' > "$1/INGREDIENTS.md"
  printf '{"extends":["github>ModernMavericks/shared-cmake"]}\n' > "$1/.github/renovate.json"
  printf '#!/bin/sh\nexit 0\n' > "$1/tests/a-test.sh"
}

# compliant repo passes
mkrepo "$work/ok"; (cd "$work/ok" && sh "$S" >/dev/null) || { echo "FAIL compliant repo should pass"; exit 1; }

# no release.yml at all (shared-cmake itself) -> passes
mkdir -p "$work/norel"; (cd "$work/norel" && sh "$S" >/dev/null) || { echo "FAIL no-release.yml should pass"; exit 1; }

# 1. missing concurrency
mkrepo "$work/c"; grep -v -e '^concurrency:' -e '^  group:' -e '^  cancel-in-progress:' \
  "$work/ok/.github/workflows/release.yml" > "$work/c/.github/workflows/release.yml"
if (cd "$work/c" && sh "$S" >/dev/null 2>&1); then echo "FAIL missing concurrency should fail"; exit 1; fi
(cd "$work/c" && sh "$S" 2>&1 | grep -qi concurrency) || { echo "FAIL should name concurrency"; exit 1; }

# 2. tests exist but CI never runs them
mkrepo "$work/t"; grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/t/.github/workflows/release.yml"
if (cd "$work/t" && sh "$S" >/dev/null 2>&1); then echo "FAIL unrun tests should fail"; exit 1; fi

# ...but a repo with an EMPTY tests dir is fine
mkrepo "$work/te"; rm -f "$work/te/tests/a-test.sh"
grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/te/.github/workflows/release.yml"
(cd "$work/te" && sh "$S" >/dev/null) || { echo "FAIL empty tests dir should pass"; exit 1; }

# 3. missing INGREDIENTS.md
mkrepo "$work/i"; rm -f "$work/i/INGREDIENTS.md"
if (cd "$work/i" && sh "$S" >/dev/null 2>&1); then echo "FAIL missing INGREDIENTS.md should fail"; exit 1; fi

# 4. a Renovate key restating the preset's own value is redundant -> fail
mkrepo "$work/r"
printf '{"extends":["github>ModernMavericks/shared-cmake"],"ignoreTests":false}\n' > "$work/r/.github/renovate.json"
if (cd "$work/r" && sh "$S" >/dev/null 2>&1); then echo "FAIL redundant renovate key should fail"; exit 1; fi
(cd "$work/r" && sh "$S" 2>&1 | grep -qi ignoreTests) || { echo "FAIL should name the key"; exit 1; }

# ...but the SAME key with a DIFFERENT value is a deliberate override, not drift. A repo with no build
# to gate legitimately opts back into blind automerge with ignoreTests:true; the gate must allow it.
mkrepo "$work/r2"
printf '{"extends":["github>ModernMavericks/shared-cmake"],"ignoreTests":true}\n' > "$work/r2/.github/renovate.json"
(cd "$work/r2" && sh "$S" >/dev/null) || { echo "FAIL deliberate ignoreTests:true override should pass"; exit 1; }

# 5. release publishes no notes
mkrepo "$work/n"; grep -v 'notes-file' "$work/ok/.github/workflows/release.yml" > "$work/n/.github/workflows/release.yml"
if (cd "$work/n" && sh "$S" >/dev/null 2>&1); then echo "FAIL no notes should fail"; exit 1; fi

# tests may be run from a DIFFERENT workflow (tailscale runs ctest from ci.yml, not release.yml)
mkrepo "$work/x"; grep -v 'run-repo-tests' "$work/ok/.github/workflows/release.yml" > "$work/x/.github/workflows/release.yml"
printf 'name: CI\njobs:\n  build:\n    steps:\n      - run: ctest --preset cross\n' > "$work/x/.github/workflows/ci.yml"
(cd "$work/x" && sh "$S" >/dev/null) || { echo "FAIL tests run from ci.yml should pass"; exit 1; }

echo "PASS: check-family-conventions"

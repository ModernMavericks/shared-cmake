#!/bin/sh
# Gate: does this repo still look like its siblings? A convention that is not checked is a convention
# that drifts -- seven repos started from one shape and diverged into two publishers, four concurrency
# policies, three repos not running their own tests, and 11 copies of one shell incantation.
#
# Fails loudly and names the fix. A repo with no release.yml (shared-cmake itself) has nothing to check.
#   usage: check-family-conventions.sh
set -eu
REL=".github/workflows/release.yml"
[ -f "$REL" ] || { echo "check-family-conventions: no $REL — not a product repo, nothing to check"; exit 0; }

# Everything under .github/workflows counts as "CI": some repos run their tests from ci.yml, not
# release.yml, and either is fine as long as something does.
CI_FILES="$(ls .github/workflows/*.yml 2>/dev/null || true)"
ci_mentions() {  # $1 = pattern. -e so a pattern starting with '-' (--notes-file) is not read as a flag.
  [ -n "$CI_FILES" ] || return 1
  # shellcheck disable=SC2086  # CI_FILES is a deliberate word-split list of paths
  grep -lq -e "$1" $CI_FILES 2>/dev/null
}

status=0
fail() { echo "check-family-conventions: $1" >&2; echo "    fix: $2" >&2; status=1; }

# 1. Concurrency: two publishes racing the same tag is a corrupt release, not a flaky build.
grep -q '^concurrency:' "$REL" \
  || fail "$REL declares no concurrency: — two publishes can race the same tag" \
          "add a concurrency: block with cancel-in-progress: false"

# 2. Tests that exist must run. Hand-enumeration is how they stop running.
if [ -d tests ] && [ -n "$(ls tests/*.sh tests/*.bats 2>/dev/null || true)" ]; then
  ci_mentions 'run-repo-tests' || ci_mentions 'ctest' \
    || fail "tests/ has test files but no workflow runs them" \
            "add: sh \"\$MSC_SCRIPTS/run-repo-tests.sh\"   (or ctest, where that is the driver)"
fi

# 3. Every product bakes in inputs; say what they are and how each is tracked.
[ -f INGREDIENTS.md ] \
  || fail "no INGREDIENTS.md — the repo's build inputs are undocumented" \
          "list each input, where it is pinned, its Renovate status, and what a bump does"

# 4. A key restating the preset's own value is redundant: it silently stops tracking the preset the day
#    the preset changes. The SAME key with a DIFFERENT value is a deliberate override and stays legal --
#    a repo with no build to gate opts back into blind automerge with ignoreTests:true.
if [ -f .github/renovate.json ]; then
  # preset values, kept next to the preset that sets them (default.json)
  for pair in 'ignoreTests:false'; do
    k="${pair%%:*}"; presetval="${pair#*:}"
    grep -q "\"$k\"[[:space:]]*:[[:space:]]*$presetval" .github/renovate.json \
      && fail "renovate.json sets \"$k\": $presetval, which is exactly what the shared preset sets" \
              "delete the key (the preset owns it); keep it only to override with a different value"
  done
fi

# 4b. The family default is ship-if-green: patch, minor and major automerge once the build passes, and
#     breakage is fixed forward in a -mavericks.N+1 release. A repo restricts automerge only where a bad
#     bump would BUILD FINE AND BE WRONG -- the case a green build cannot catch (swift-toolchain: a
#     minor Swift bump needs LLVM_BRANCH to follow, which no regex can infer). Write that reason down,
#     or the exception is indistinguishable from drift.
if [ -f .github/renovate.json ]; then
  python3 - .github/renovate.json <<'PY' || status=1
import json, sys
bad = []
for r in json.load(open(sys.argv[1])).get('packageRules', []):
    if 'automerge' in r and not (r.get('description') or '').strip():
        bad.append(r.get('matchDepNames') or r.get('matchPackageNames') or '(unnamed rule)')
if bad:
    print("check-family-conventions: automerge exception with no description: %s" % bad, file=sys.stderr)
    print("    fix: say why a green build is not enough here (what would build fine and be wrong),", file=sys.stderr)
    print("         or drop the rule and take the family default (ship-if-green)", file=sys.stderr)
    sys.exit(1)
PY
fi

# 5. Notes must reach readers. An empty Release body ships without anyone noticing (tailscale did,
#    for every release, including hand-tagged ones that had a committed notes file).
# publish-release.yml is the strongest evidence: it OWNS the body and fails on an empty one. The other
# three only show that some step was handed notes -- note that --notes-file also matches a Sparkle
# appcast call, which is not the Release body, so this check is weaker than it reads for repos that
# have not adopted the shared publisher yet.
ci_mentions 'publish-release.yml' || ci_mentions '--notes-file' || ci_mentions 'body_path' \
  || ci_mentions '--generate-notes' \
  || fail "the release publishes no notes body" \
          "publish via publish-release.yml@v1, or pass --notes-file / body_path when creating the release"

[ "$status" -eq 0 ] && echo "check-family-conventions: ok"
exit "$status"

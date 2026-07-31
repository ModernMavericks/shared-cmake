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

# 1b. ...and it must SERIALIZE local_release dispatches. Keying the group on github.run_id makes every
# run its own group (concurrency becomes a no-op), so two dispatches — a manual cut racing the
# ingredient-bump auto-repackage — each compute -mavericks.(N+1) from the same tags and collide on the
# tag. Dispatches must share ONE group (cancel-in-progress:false): a version-bump lock.
if awk '/^concurrency:/{f=1;next} /^[^[:space:]#]/{f=0} f' "$REL" | grep -q 'github\.run_id'; then
  fail "$REL concurrency group keys on github.run_id — local_release dispatches don't serialize, so two can cut the same tag" \
       "share one dispatch group (e.g. \"…workflow_dispatch' && 'local_release'…\") with cancel-in-progress: false"
fi

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
# 7. VERSION is DERIVED, not committed. The shipped state lives in tags; a committed VERSION is a
# second answer to "what version is this?" and it drifts -- container-tools built -mavericks.14 from a
# committed file that still said .2, which also made its tag path (tag must equal VERSION)
# unsatisfiable. An UNTRACKED VERSION in the tree is fine and expected: it is a build product.
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files --error-unmatch VERSION >/dev/null 2>&1; then
    fail "VERSION is committed — it is a build product, and the committed copy goes stale while tags move on" \
         "git rm --cached VERSION; add /VERSION to .gitignore; commit UPSTREAM_VERSION instead"
  fi
else
  # Not a checkout: the gate cannot see what is tracked. Say so rather than pass silently.
  echo "check-family-conventions: not a git checkout — cannot check whether VERSION is committed" >&2
  status=1
fi

# ...and something must be able to SUPPLY the upstream version: a committed UPSTREAM_VERSION, one per
# line for a repo shipping parallel lines (golang), or a script that derives it from the pin (ed25519
# reads the pinned commit's date; tailscale reads upstream's own VERSION.txt).
if [ ! -f UPSTREAM_VERSION ] \
   && [ -z "$(ls lines/*/UPSTREAM_VERSION 2>/dev/null || true)" ] \
   && [ -z "$(ls build/derive-upstream-version.sh scripts/derive-upstream-version.sh 2>/dev/null || true)" ]; then
  fail "no UPSTREAM_VERSION and nothing to derive one — the version cannot be computed" \
       "commit UPSTREAM_VERSION (bare x.y.z or a date), or add build/derive-upstream-version.sh"
fi

# 8. Every workflow must PARSE, with duplicate keys rejected. A second `with:` on one step is legal
# YAML -- last key wins, and every ordinary parser accepts it -- but GitHub refuses to run the
# workflow: the run appears named after the file path, "likely failed because of a workflow file
# issue", with no step logs to read. Nothing else in CI can catch this, because CI never starts.
if [ -n "$CI_FILES" ] && command -v python3 >/dev/null 2>&1; then
  # shellcheck disable=SC2086  # deliberate word-split list of paths
  python3 - $CI_FILES <<'PYEOF' || status=1
import sys, yaml

class Strict(yaml.SafeLoader):
    pass

def no_duplicate_keys(loader, node, deep=False):
    seen = set()
    for key_node, _ in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in seen:
            raise ValueError("duplicate key %r on line %d" % (key, key_node.start_mark.line + 1))
        seen.add(key)
    return yaml.SafeLoader.construct_mapping(loader, node, deep)

Strict.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, no_duplicate_keys)

rc = 0
for path in sys.argv[1:]:
    try:
        with open(path) as fh:
            yaml.load(fh, Strict)
    except Exception as exc:
        sys.stderr.write("check-family-conventions: %s does not parse: %s\n" % (path, exc))
        sys.stderr.write("    fix: GitHub rejects the whole workflow -- it never runs, so no other gate sees this\n")
        rc = 1
sys.exit(rc)
PYEOF
fi

exit "$status"

#!/bin/sh
# run-repo-tests.sh: run a repo's tests the same way everywhere, so a newly added test file runs the
# day it lands. Exit 77 = SKIP (the idiom container-tools already uses for its boot-proof).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/run-repo-tests.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"; mkdir -p tests

# no tests dir at all -> succeed, say so
mkdir -p empty && (cd empty && sh "$S" >/dev/null) || { echo "FAIL no-tests-dir should pass"; exit 1; }

printf '#!/bin/sh\necho ok\n'        > tests/a-test.sh
printf '#!/bin/sh\nexit 77\n'        > tests/b-skips.sh
out="$(sh "$S")" || { echo "FAIL all-passing should exit 0: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'PASS.*a-test.sh' || { echo "FAIL pass line: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'SKIP.*b-skips.sh' || { echo "FAIL skip line: $out"; exit 1; }

# a genuine failure fails the runner, and is not reported as a skip
printf '#!/bin/sh\nexit 1\n' > tests/c-fails.sh
if out="$(sh "$S" 2>&1)"; then echo "FAIL failing test should fail the runner: $out"; exit 1; fi
printf '%s\n' "$out" | grep -q 'FAIL.*c-fails.sh' || { echo "FAIL fail line: $out"; exit 1; }
printf '%s\n' "$out" | grep -q 'SKIP.*c-fails.sh' && { echo "FAIL failure reported as skip"; exit 1; }
rm tests/c-fails.sh

# subdirectories are fixtures/sub-suites with their own entry points, not tests to run
mkdir -p tests/fixtures
printf '#!/bin/sh\nexit 1\n' > tests/fixtures/nested.sh
sh "$S" >/dev/null || { echo "FAIL nested script must not be run"; exit 1; }

echo "PASS: run-repo-tests"

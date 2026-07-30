#!/bin/sh
# previous-release-tag.sh: newest release tag, version-ordered (1.102.0 > 1.98.8, N=10 > N=9).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/previous-release-tag.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q -b main .
git config user.email t@example.com; git config user.name tester
echo hi > f; git add f; git commit -qm base

# no tags at all -> nothing
out="$(sh "$S")"
[ -z "$out" ] || { echo "FAIL no-tags: got '$out'"; exit 1; }

git tag 1.98.8-mavericks.1
git tag 1.98.8-mavericks.2
git tag 1.102.0-mavericks.1
git tag v1                 # not a release tag; must be ignored

# version ordering: 1.102.0 sorts after 1.98.8 (numeric minor, not lexical)
out="$(sh "$S")"
[ "$out" = 1.102.0-mavericks.1 ] || { echo "FAIL newest: got '$out'"; exit 1; }

# excluding the tag being published yields its predecessor
out="$(sh "$S" 1.102.0-mavericks.1)"
[ "$out" = 1.98.8-mavericks.2 ] || { echo "FAIL exclude: got '$out'"; exit 1; }

# N ordering is numeric: .10 beats .9
git tag 1.102.0-mavericks.9; git tag 1.102.0-mavericks.10
out="$(sh "$S")"
[ "$out" = 1.102.0-mavericks.10 ] || { echo "FAIL N-order: got '$out'"; exit 1; }

echo "PASS: previous-release-tag"

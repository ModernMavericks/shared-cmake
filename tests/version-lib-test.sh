#!/bin/sh
# The promoted version scaffolding: one implementation for every repo that derives
# <upstream>-mavericks.N from tags. The three repo copies were byte-identical in logic and differed
# only in comment wording and the name of the root variable.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
V="$here/../scripts/version.sh"
L="$here/../scripts/lib.sh"
w="$(mktemp -d)"; trap 'rm -rf "$w"' EXIT
printf '1.26.5\n' > "$w/UPSTREAM_VERSION"
export MAVERICKS_ROOT="$w"

# upstream_version() reads the committed file, whitespace stripped
got="$(. "$L"; upstream_version)"
[ "$got" = 1.26.5 ] || { echo "FAIL upstream_version: '$got'"; exit 1; }

# auto, no tags yet -> a new upstream is release number 1, and it releases
out="$(MAVERICKS_TAGS='' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL auto/new FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'TAG=1.26.5-mavericks.1'  || { echo "FAIL auto/new TAG: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'RELEASE=yes'             || { echo "FAIL auto/new REL: $out"; exit 1; }

# auto, already released -> the current N, and it does NOT release again
out="$(MAVERICKS_TAGS='1.26.5-mavericks.1
1.26.5-mavericks.3
1.26.5-mavericks.2' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.3' || { echo "FAIL auto/exist FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'RELEASE=no'              || { echo "FAIL auto/exist REL: $out"; exit 1; }

# local -> the next N, and it releases
out="$(MAVERICKS_TAGS='1.26.5-mavericks.3' sh "$V" local)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.4' || { echo "FAIL local FULL: $out"; exit 1; }
printf '%s\n' "$out" | grep -qx 'RELEASE=yes'             || { echo "FAIL local REL: $out"; exit 1; }

# tags for OTHER upstreams are ignored (N resets to 1 when UPSTREAM_VERSION moves)
out="$(MAVERICKS_TAGS='1.26.4-mavericks.7' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL other-upstream: $out"; exit 1; }

# a non-numeric suffix is not an N
out="$(MAVERICKS_TAGS='1.26.5-mavericks.rc1' sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.1' || { echo "FAIL junk suffix: $out"; exit 1; }

# an unknown mode is an error, not a silent default
if sh "$V" sideways >/dev/null 2>&1; then echo "FAIL bad mode should exit non-zero"; exit 1; fi

# with no MAVERICKS_TAGS it reads the repo's tags
( cd "$w" && git init -q -b main . && git config user.email t@e.com && git config user.name t \
  && git add UPSTREAM_VERSION && git commit -qm base && git tag 1.26.5-mavericks.9 )
out="$(sh "$V" auto)"
printf '%s\n' "$out" | grep -qx 'FULL=1.26.5-mavericks.9' || { echo "FAIL git tags: $out"; exit 1; }

echo "PASS: version-lib"

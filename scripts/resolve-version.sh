#!/bin/sh
# Print this repo's full version (<upstream>-mavericks.N), writing VERSION if it is not there yet.
#
#   resolve-version.sh [auto|local]
#
# THE SHIPPED STATE LIVES IN TAGS. VERSION is a build PRODUCT -- written here, read by cmake and the
# updater, gitignored, never committed. The family used to have three answers to "what version is
# this?": a committed VERSION file, the tag being built, or a derivation from tags. They disagreed in
# practice -- container-tools shipped -mavericks.14 while its committed file still said .2, which also
# made its tag-triggered publish path (tag must equal VERSION) impossible to satisfy.
#
# Reusing an existing VERSION is deliberate: within one CI run, an earlier job already resolved it and
# every job must agree. Re-deriving per job would let a tag pushed mid-run change the answer halfway
# through, which is exactly how two halves of one .pkg end up labelled differently.
set -eu
SELF="$(cd "$(dirname "$0")" && pwd)"
. "$SELF/lib.sh"          # MAVERICKS_ROOT, upstream_version()

mode="${1:-auto}"
vfile="$MAVERICKS_ROOT/VERSION"

if [ -f "$vfile" ]; then
  ver="$(tr -d '[:space:]' < "$vfile")"
  # An empty VERSION is worse than a missing one: the build carries on and names artifacts
  # "-mavericks." with nothing in front, which looks almost right.
  [ -n "$ver" ] || { echo "resolve-version: $vfile is empty -- delete it to re-derive" >&2; exit 1; }
  printf '%s\n' "$ver"
  exit 0
fi

upfile="${MAVERICKS_UPSTREAM_FILE:-$MAVERICKS_ROOT/UPSTREAM_VERSION}"
[ -f "$upfile" ] || {
  echo "resolve-version: no VERSION and no UPSTREAM_VERSION ($upfile)" >&2
  echo "  UPSTREAM_VERSION is the committed input; VERSION is derived from it plus the shipped tags." >&2
  exit 1
}

ver="$(sh "$SELF/version.sh" "$mode" | sed -n 's/^FULL=//p')"
[ -n "$ver" ] || { echo "resolve-version: version.sh produced no FULL=" >&2; exit 1; }
printf '%s\n' "$ver" > "$vfile"
printf '%s\n' "$ver"

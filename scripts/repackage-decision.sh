#!/bin/sh
# Decide whether a build-ingredient bump warrants a -mavericks.(N+1) repackage, and its version.
# The caller only runs when an ingredient PIN changed (its push-path filter guarantees that); this
# script answers: did the OWN upstream also change (-> new-upstream N=1, handled elsewhere: SKIP)?
# otherwise compute NEW = <current-upstream>-mavericks.(N+1).
#   env in: CHANGED (newline paths), OWN_UPSTREAM_PATHS (newline paths, may be empty),
#           VERSION_SH (path to version.sh, optional) | CUR_VERSION (<up>-mavericks.N)
#   stdout: NEW=<version>  or  SKIP=<reason>
set -eu

if [ -n "${OWN_UPSTREAM_PATHS:-}" ]; then
  for p in $OWN_UPSTREAM_PATHS; do
    if printf '%s\n' "${CHANGED:-}" | grep -Fxq "$p"; then
      echo "SKIP=own-upstream-changed"; exit 0
    fi
  done
fi

if [ -n "${VERSION_SH:-}" ]; then
  full="$(sh "$VERSION_SH" local | sed -n 's/^FULL=//p')"   # local => <up>-mavericks.(maxN+1)
  [ -n "$full" ] || { echo "SKIP=version.sh-empty"; exit 0; }
  echo "NEW=$full"; exit 0
fi

cur="${CUR_VERSION:?repackage-decision: set CUR_VERSION or VERSION_SH}"
up="${cur%%-mavericks.*}"; n="${cur##*-mavericks.}"
case "$n" in ''|*[!0-9]*) echo "SKIP=bad-version:$cur"; exit 0;; esac
echo "NEW=${up}-mavericks.$((n + 1))"

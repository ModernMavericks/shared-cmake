#!/bin/sh
# Decide whether a build-ingredient bump should DISPATCH a repackage. The caller only runs when an
# ingredient pin changed (its push-path filter guarantees that); this answers the one remaining
# question: did the repo's OWN upstream ALSO change? If so it's a new-upstream (N=1), owned by the
# repo's own new-upstream path -> SKIP. Otherwise -> DISPATCH (the consumer's release workflow, run
# via workflow_dispatch, computes the -mavericks.(N+1) version and publishes inline).
#   env in:  CHANGED (newline-separated paths changed this push), OWN_UPSTREAM_PATHS (newline paths, may be empty)
#   stdout:  DISPATCH  or  SKIP=<reason>
set -eu
if [ -n "${OWN_UPSTREAM_PATHS:-}" ]; then
  for p in $OWN_UPSTREAM_PATHS; do
    if printf '%s\n' "${CHANGED:-}" | grep -Fxq "$p"; then
      echo "SKIP=own-upstream-changed"; exit 0
    fi
  done
fi
echo "DISPATCH"

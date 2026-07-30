#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/repackage-decision.sh"

# own-upstream changed -> SKIP (that's the N=1 path's job)
out="$(CHANGED='UPSTREAM_VERSION' OWN_UPSTREAM_PATHS='UPSTREAM_VERSION' sh "$S")"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL own-upstream: $out"; exit 1; }

# an own-upstream path present among several changed paths -> SKIP
out="$(CHANGED="$(printf 'components/golang/version\ncomponents/tailscale/version')" OWN_UPSTREAM_PATHS='components/tailscale/version' sh "$S")"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL own-upstream-multi: $out"; exit 1; }

# ingredient only, own-upstream declared but unchanged -> DISPATCH
out="$(CHANGED='components/golang/version' OWN_UPSTREAM_PATHS='components/tailscale/version' sh "$S")"
[ "$out" = "DISPATCH" ] || { echo "FAIL ingredient/dispatch: $out"; exit 1; }

# ingredient, empty own-upstream (e.g. container-tools) -> DISPATCH
out="$(CHANGED='components/golang/version' OWN_UPSTREAM_PATHS='' sh "$S")"
[ "$out" = "DISPATCH" ] || { echo "FAIL ingredient/empty-own: $out"; exit 1; }

echo "PASS: repackage-decision"

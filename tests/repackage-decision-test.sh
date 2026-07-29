#!/bin/sh
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/repackage-decision.sh"

# own-upstream changed -> SKIP (that's the N=1 path's job)
out="$(CHANGED='UPSTREAM_VERSION' OWN_UPSTREAM_PATHS='UPSTREAM_VERSION' CUR_VERSION='1.26.4-mavericks.3' sh "$S")"
[ "$out" = "SKIP=own-upstream-changed" ] || { echo "FAIL own-upstream: $out"; exit 1; }

# ingredient changed, committed-VERSION repo -> N+1
out="$(CHANGED='components/golang/version' OWN_UPSTREAM_PATHS='components/tailscale/version' CUR_VERSION='1.98.8-mavericks.1' sh "$S")"
[ "$out" = "NEW=1.98.8-mavericks.2" ] || { echo "FAIL ingredient/committed: $out"; exit 1; }

# ingredient changed, empty own-upstream (container-tools date-based) -> N+1
out="$(CHANGED='components/golang/version' OWN_UPSTREAM_PATHS='' CUR_VERSION='20260727-mavericks.2' sh "$S")"
[ "$out" = "NEW=20260727-mavericks.3" ] || { echo "FAIL ingredient/empty-own: $out"; exit 1; }

# derive-from-tag repo: VERSION_SH local mode supplies FULL
tmp="$(mktemp)"; printf '#!/bin/sh\necho FULL=1.26.4-mavericks.4\n' > "$tmp"; chmod +x "$tmp"
out="$(CHANGED='build/versions.sh' OWN_UPSTREAM_PATHS='UPSTREAM_VERSION' VERSION_SH="$tmp" sh "$S")"
[ "$out" = "NEW=1.26.4-mavericks.4" ] || { echo "FAIL version_sh: $out"; exit 1; }
rm -f "$tmp"

echo "PASS: repackage-decision"

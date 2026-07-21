#!/bin/sh
# Configures tests/standalone-include (LANGUAGES NONE) against the shared package's
# config to prove the à-la-carte modules load without the AppleClang gate.
# Arg 1: the MavericksSharedCMake config dir (holds the Config + the modules).
set -eu
CFGDIR="${1:?config dir required}"
SRC=$(cd "$(dirname "$0")/standalone-include" && pwd)
WORK="$(mktemp -d -t standalone_include)"
trap 'rm -rf "$WORK"' EXIT
cmake -S "$SRC" -B "$WORK" -DMavericksSharedCMake_DIR="$CFGDIR" >/dev/null
echo "standalone-include: OK"

#!/bin/sh
# Prove stage_updater.sh stages a (fake) updater .app + LaunchAgent into a payload root and renders
# its templates with no leftover @TOKENS@, in all three output modes (postinstall / snippet /
# neither). The install dir contains a SPACE (/Library/Application Support/...), so this also pins
# that the rendered paths survive it. Dependency-free; no real Sparkle app needed.
set -eu
ROOT="$1"
T=$(mktemp -d "${TMPDIR:-/tmp}/mav-stageupd.XXXXXX")
trap 'rm -rf "$T"' EXIT

APPDIR="/Library/Application Support/ModernMavericks"
LABEL=dev.modernmavericks.test-updatecheck
APP="$T/TestUpdater.app"
mkdir -p "$APP/Contents/MacOS"
printf '#!/bin/sh\n' > "$APP/Contents/MacOS/TestUpdater"
chmod +x "$APP/Contents/MacOS/TestUpdater"

fail() { echo "stage_updater test: $1" >&2; exit 1; }
no_token() { if grep -q '@MAVERICKS' "$1"; then fail "unsubstituted token in $1"; fi; }

# --- mode 1: full postinstall ------------------------------------------------
STAGE="$T/stage"; SCR="$T/scripts"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE" --app "$APP" \
  --app-dir "$APPDIR" --agent-label "$LABEL" --scripts-out "$SCR"

# The staged file lives under $STAGE; the plist references the INSTALLED path (no $STAGE prefix).
installed_exe="$APPDIR/TestUpdater.app/Contents/MacOS/TestUpdater"
[ -x "$STAGE$installed_exe" ] || fail "app not staged"

PL="$STAGE/Library/LaunchAgents/$LABEL.plist"
[ -f "$PL" ] || fail "no agent plist"
grep -q "<string>$LABEL</string>" "$PL" || fail "agent label not set"
grep -q "<string>$installed_exe</string>" "$PL" || fail "agent exec path not set"
plutil -lint "$PL" >/dev/null || fail "agent plist is not valid"
no_token "$PL"

PI="$SCR/postinstall"
[ -x "$PI" ] || fail "no postinstall"
grep -q "$LABEL.plist" "$PI" || fail "postinstall label wrong"
sh -n "$PI" || fail "rendered postinstall is not valid sh"
no_token "$PI"

# No manual-trigger shim: the daily agent is the only check. Nothing lands in /usr/local/bin.
[ ! -d "$STAGE/usr/local/bin" ] || fail "staged something into /usr/local/bin"

# --- mode 2: snippet for a product with its own postinstall ------------------
STAGE2="$T/stage2"; SNIP="$T/snips/agent-load.sh"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE2" --app "$APP" \
  --app-dir "$APPDIR" --agent-label "$LABEL" --snippet-out "$SNIP"
[ -f "$SNIP" ] || fail "no snippet"
no_token "$SNIP"
sh -n "$SNIP" || fail "snippet is not valid sh"
[ ! -f "$T/snips/postinstall" ] || fail "wrote a postinstall when only a snippet was asked for"
# Sourcing it must neither exit the caller nor clobber the caller's variables.
CONSOLE_USER=mine; PLIST=mine
. "$SNIP"
echo reached-the-end > "$T/sourced"
[ -f "$T/sourced" ] || fail "sourcing the snippet exited the caller"
[ "$CONSOLE_USER" = mine ] && [ "$PLIST" = mine ] || fail "snippet clobbered a caller variable"

# Both outputs render the same logic -- the postinstall is the snippet plus a shebang and exit.
grep -q 'MAV_AGENT_PLIST' "$PI" || fail "postinstall does not carry the shared agent-load logic"

# --- mode 3: payload only ----------------------------------------------------
STAGE3="$T/stage3"
sh "$ROOT/scripts/stage_updater.sh" --stage "$STAGE3" --app "$APP" \
  --app-dir "$APPDIR" --agent-label "$LABEL"
[ -x "$STAGE3$installed_exe" ] || fail "app not staged in payload-only mode"

# Unknown args are rejected, not silently ignored: a caller asking for something this script does not
# do should fail loudly rather than get a payload quietly missing it.
if sh "$ROOT/scripts/stage_updater.sh" --stage "$T/s4" --app "$APP" --app-dir "$APPDIR" \
     --agent-label x --no-such-flag whatever 2>/dev/null; then
  fail "an unknown argument was accepted"
fi

echo "stage_updater OK"

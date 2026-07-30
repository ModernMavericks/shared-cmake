#!/bin/sh
# 10.9 userland compat guard for one or more shipped Mach-O binaries.
# Per binary: (1) no post-10.9 UNDEFINED import, (2) no post-10.9 ObjC selector sent,
# (3) arch exactly x86_64, (4) LC_VERSION_MIN_MACOSX == 10.9. Fail-closed if nothing measured.
#
# This is what makes a newer-SDK cross-build trustworthy: the newer SDK will
# happily let you link post-10.9 symbols that simply are not present on a real
# Mavericks box, and this catches them before they ship.
#
# Knobs:
#   MAVERICKS_POST_10_9_SYMBOLS    extra post-10.9 symbols (grep -E alternation) that must
#                                  not appear as undefined imports.
#   MAVERICKS_POST_10_9_SELECTORS  extra post-10.9 ObjC selectors (grep -E alternation) to deny.
#   MAVERICKS_ALLOW_SELECTORS      post-10.9 selectors the code guards with -respondsToSelector:.
#   MAVERICKS_REQUIRE_DEFINED_SYMBOLS  symbols that MUST be DEFINED (a project's 10.9 shims).
#   MAVERICKS_ALLOW_GUARDED_WEAK   grep -E alternation of post-10.9 symbols permitted ONLY when
#                                  imported *weak*. For runtimes (e.g. mavericks-swift) that
#                                  weak-link post-10.9 SPIs and NULL-check them before use
#                                  (Swift's SWIFT_RUNTIME_WEAK_CHECK). Default empty => strict:
#                                  ANY post-10.9 undefined fails, weak or not (original behavior).
#                                  A HARD post-10.9 import ALWAYS fails, allowlisted or not --
#                                  10.9's dyld-239 aborts on a missing *hard* lazy symbol, and it
#                                  also aborts on a missing *weak* lazy symbol that is actually
#                                  called, so the allowlist is an assertion that the runtime
#                                  guards these with a NULL-check.
set -eu

mav_die() { echo "compat guard CANNOT MEASURE (fail-closed): $*" >&2; exit 4; }

# Post-10.9 APIs that must never appear as UNDEFINED imports. Families use a
# prefix (.*) so ALL members are caught. Matched whole-symbol via grep -xE.
POST_10_9='_clock_gettime|_clock_gettime_nsec_np|_os_unfair_lock_.*|_os_log.*'
if [ -n "${MAVERICKS_POST_10_9_SYMBOLS:-}" ]; then
  POST_10_9="$POST_10_9|$MAVERICKS_POST_10_9_SYMBOLS"
fi

REQUIRE_DEFINED="${MAVERICKS_REQUIRE_DEFINED_SYMBOLS:-}"
ALLOW_WEAK="${MAVERICKS_ALLOW_GUARDED_WEAK:-}"

# Post-10.9 Objective-C SELECTORS. These dispatch through objc_msgSend, so they are NOT undefined
# symbols -- the import check above (nm) cannot see them. A 10.9 binary that SENDS one (e.g.
# -[NSColor labelColor], 10.10+) links clean but no-ops/misbehaves on 10.9 (grey buttons, wrong
# colors). The selector name is a C string in __TEXT,__objc_methname; match it whole-line via
# `strings -a`. This is the exact gap that let an SDK-12 Sparkle (grey "Install" button) pass.
#   MAVERICKS_POST_10_9_SELECTORS  extra post-10.9 selectors (grep -E alternation) to deny.
#   MAVERICKS_ALLOW_SELECTORS      selectors the code guards with -respondsToSelector: (allowlist).
POST_10_9_SEL='labelColor|secondaryLabelColor|tertiaryLabelColor|quaternaryLabelColor|controlAccentColor'
[ -n "${MAVERICKS_POST_10_9_SELECTORS:-}" ] && POST_10_9_SEL="$POST_10_9_SEL|$MAVERICKS_POST_10_9_SELECTORS"
ALLOW_SEL="${MAVERICKS_ALLOW_SELECTORS:-}"

# Undefined imports of a Mach-O as "W <name>" (weak) / "H <name>" (hard), one per line.
# nm -m lines look like: "<addr|spaces> (undefined) [weak] external _sym (from libX)".
# Strip any trailing parenthetical -- " (from libX)" OR " (dynamically looked up)" -- so the symbol
# NAME becomes the last field (nm -u loses the weak flag, so we parse nm -m instead; the undefined
# NAME set is identical). A dynamic_lookup undefined ends " (dynamically looked up)", not " (from ...)";
# stripping only the latter left $NF = "up)" and the hard import slipped past the guard.
mav_undefs() {
  nm -m "$1" 2>/dev/null | grep -F '(undefined)' | sed -E 's/ \([^)]*\)$//' \
    | awk '{ w = (/ weak /) ? "W" : "H"; print w, $NF }'
}

fail=0; checked=0
for b in "$@"; do
  [ -f "$b" ] || { echo "compat guard: MISSING $b" >&2; fail=1; continue; }
  checked=$((checked+1))

  U=$(mav_undefs "$b")
  # HARD post-10.9 imports always fail.
  hard_leak=$(printf '%s\n' "$U" | awk '$1=="H"{print $2}' | grep -xE "($POST_10_9)" || true)
  # WEAK post-10.9 imports fail UNLESS allowlisted (default: no allowlist => all fail = original).
  weak_leak=$(printf '%s\n' "$U" | awk '$1=="W"{print $2}' | grep -xE "($POST_10_9)" || true)
  if [ -n "$ALLOW_WEAK" ]; then
    weak_leak=$(printf '%s\n' "$weak_leak" | grep -vxE "($ALLOW_WEAK)" || true)
  fi
  leak=$(printf '%s\n%s\n' "$hard_leak" "$weak_leak" | grep -v '^$' || true)
  [ -z "$leak" ] || { echo "compat guard: post-10.9 undefined import(s) in $b:" >&2; printf '%s\n' "$leak" | sed 's/^/  /' >&2; fail=1; }

  # Post-10.9 ObjC selectors sent (invisible to nm; live in __objc_methname). See POST_10_9_SEL.
  sel_leak=$(strings -a "$b" 2>/dev/null | grep -xE "($POST_10_9_SEL)" | sort -u || true)
  if [ -n "$ALLOW_SEL" ]; then
    sel_leak=$(printf '%s\n' "$sel_leak" | grep -vxE "($ALLOW_SEL)" || true)
  fi
  sel_leak=$(printf '%s\n' "$sel_leak" | grep -v '^$' || true)
  [ -z "$sel_leak" ] || { echo "compat guard: post-10.9 ObjC selector(s) sent in $b:" >&2; printf '%s\n' "$sel_leak" | sed 's/^/  /' >&2; fail=1; }

  if [ -n "$REQUIRE_DEFINED" ]; then
    # Defined symbols = nm entries whose line is NOT an undefined ('U'/'u') entry.
    defined=$(nm "$b" 2>/dev/null | grep -vE '^[[:space:]]*[Uu] ' | awk '{print $NF}')
    for _req in $(printf '%s\n' "$REQUIRE_DEFINED" | tr '|' ' '); do
      printf '%s\n' "$defined" | grep -xq "$_req" \
        || { echo "compat guard: required symbol '$_req' not DEFINED in $b" >&2; fail=1; }
    done
  fi

  archs=$(lipo -info "$b" 2>/dev/null | sed 's/.*: //' || true)
  [ "$archs" = x86_64 ] || { echo "compat guard: $b arch '$archs' != x86_64" >&2; fail=1; }
  minos=$(otool -l "$b" 2>/dev/null | awk '/LC_VERSION_MIN_MACOSX/{f=1} f&&$1=="version"{print $2; exit}')
  [ "$minos" = 10.9 ] || { echo "compat guard: $b min-OS '$minos' != 10.9" >&2; fail=1; }
done
[ "$checked" -gt 0 ] || mav_die "no binaries checked"
if [ "$fail" = 0 ]; then
  echo "compat guard: $checked binaries clean (x86_64, min-10.9, no post-10.9 imports)"
else
  exit 1
fi

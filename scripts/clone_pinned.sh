#!/bin/sh
# The family's git-source supply-chain boundary. Idempotently fetch a pinned git source into a
# shared, mode/host-independent cache and VERIFY the checkout is exactly the pinned commit -- fail
# closed on any mismatch (a moved/forced tag, a MITM, a wrong ref) rather than silently build other
# code. Consumers pin REF (the human tag or branch -- readable, and what the version derives from)
# and DIGEST (the commit sha), both Renovate-managed via a git-refs/currentDigest customManager, so a
# bump updates both together and a tampered fetch bails.
#   Args: REPO REF DIGEST DEST
# DIGEST may be empty to skip verification (TOFU) -- a migration affordance, not the standard.
#
# ExternalProject pre-creates DEST (empty) before the download step, so we build in a temp sibling and
# atomically rename into place -- never mv into DEST. Shallow by REF for the common case (tag tip ==
# DIGEST is cheap); deepen only when the pinned commit isn't the ref's tip (branch pin, or an older
# commit), and if it isn't present at all, bail.
set -eu
REPO=$1; REF=$2; DIGEST=$3; DEST=$4

verify() {  # $1 = a git worktree; must be at DIGEST (when a DIGEST is pinned)
  [ -n "$DIGEST" ] || return 0
  got=$(git -C "$1" rev-parse HEAD 2>/dev/null || echo none)
  [ "$got" = "$DIGEST" ] && return 0
  echo "clone-verify FAIL: $REPO wanted commit $DIGEST, got $got" >&2
  return 1
}

if [ -d "$DEST/.git" ]; then
  verify "$DEST" || exit 1        # a cached checkout must still be the pinned commit
  echo "src cache hit: $DEST"
  exit 0
fi

mkdir -p "$(dirname "$DEST")"
tmp="$DEST.tmp.$$"; rm -rf "$tmp"
git clone -q --depth 1 --branch "$REF" "$REPO" "$tmp" || { rm -rf "$tmp"; exit 1; }
if [ -n "$DIGEST" ] && [ "$(git -C "$tmp" rev-parse HEAD)" != "$DIGEST" ]; then
  # The ref's shallow tip isn't the pinned commit: deepen and check out the exact sha. If it isn't
  # in the history at all (tag re-pointed to unrelated code, tampering), the checkout fails -> bail.
  git -C "$tmp" fetch -q --unshallow origin 2>/dev/null || git -C "$tmp" fetch -q origin || true
  git -C "$tmp" checkout -q "$DIGEST" 2>/dev/null || { echo "clone-verify FAIL: $DIGEST absent in $REPO@$REF" >&2; rm -rf "$tmp"; exit 1; }
fi
verify "$tmp" || { rm -rf "$tmp"; exit 1; }
rm -rf "$DEST"
mv "$tmp" "$DEST"
echo "src cached ($REF@${DIGEST:-unpinned}): $DEST"

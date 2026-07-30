#!/bin/sh
# Print the release assets in a downloaded artifact directory, one per line: everything except the
# notes file and any pre-existing SHA256SUMS (the publish workflow regenerates that).
#
# Fails when the notes file is missing or empty. Generating notes elsewhere is best-effort (`|| true`)
# because prose must never block a release -- but PUBLISHING is where that promise is kept, and an
# empty Release body is the defect this exists to prevent: tailscale shipped one on every release
# (including hand-tagged ones that had a committed notes file), and swift-runtime set no body at all.
#   usage: release-assets.sh <dir> [notes-name]
set -eu
dir="${1:?release-assets: directory required}"
notes="${2:-RELEASE_NOTES.md}"

[ -d "$dir" ] || { echo "release-assets: no such directory: $dir" >&2; exit 1; }
[ -f "$dir/$notes" ] || { echo "release-assets: $notes missing from $dir -- the release would have an empty body" >&2; exit 1; }
[ -s "$dir/$notes" ] || { echo "release-assets: $notes is empty -- the release would have an empty body" >&2; exit 1; }

found=0
for f in "$dir"/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  case "$b" in
    "$notes"|SHA256SUMS) continue ;;
  esac
  printf '%s\n' "$f"
  found=1
done
[ "$found" -eq 1 ] || { echo "release-assets: no assets in $dir (only $notes) -- nothing to publish" >&2; exit 1; }

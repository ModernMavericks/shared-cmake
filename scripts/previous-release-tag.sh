#!/bin/sh
# Print the newest existing release tag (<upstream>-mavericks.N), or nothing when there is none.
# Generated release notes use it as the "changed since" baseline.
#   usage: previous-release-tag.sh [tag-to-exclude] [upstream-glob]
# The glob scopes the search to one upstream line ('1.26.*'), which a repo shipping parallel lines
# needs: 1.26.7's notes must diff against 1.26.5, not against a 1.27.0 that shipped in between.
# Pass the tag being published so a tag-triggered build compares against its PREDECESSOR, not itself
# (a dispatch-cut repackage has no tag yet, so excluding it is harmless there).
# Ordering is version-aware: sort -V puts 1.102.0 after 1.98.8 and N=10 after N=9, both of which a
# lexical sort gets wrong.
set -eu
exclude="${1:-}"
pattern="*-mavericks.*"
[ -z "${2:-}" ] || pattern="${2}-mavericks.*"
git tag --list "$pattern" \
  | { if [ -n "$exclude" ]; then grep -vxF "$exclude" || true; else cat; fi; } \
  | sort -V \
  | tail -1

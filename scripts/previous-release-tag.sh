#!/bin/sh
# Print the newest existing release tag (<upstream>-mavericks.N), or nothing when there is none.
# Generated release notes use it as the "changed since" baseline.
#   usage: previous-release-tag.sh [tag-to-exclude]
# Pass the tag being published so a tag-triggered build compares against its PREDECESSOR, not itself
# (a dispatch-cut repackage has no tag yet, so excluding it is harmless there).
# Ordering is version-aware: sort -V puts 1.102.0 after 1.98.8 and N=10 after N=9, both of which a
# lexical sort gets wrong.
set -eu
exclude="${1:-}"
git tag --list '*-mavericks.*' \
  | { if [ -n "$exclude" ]; then grep -vxF "$exclude" || true; else cat; fi; } \
  | sort -V \
  | tail -1

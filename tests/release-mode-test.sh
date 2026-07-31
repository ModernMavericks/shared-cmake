#!/bin/sh
# release-mode.sh: which version mode is THIS run? Every job in one run must answer identically.
#
# container-tools proved why this cannot be per-job guesswork: build-macos resolved `local` (a
# repackage, N+1 = .15) while build-iso, having no idea a repackage was in progress, resolved `auto`
# (.14). The two halves of one .pkg reported different versions in the same run.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/release-mode.sh"

got() { printf '%s' "$(env "$@" sh "$S")"; }

# a dispatched repackage -> local (N+1)
out="$(got GITHUB_EVENT_NAME=workflow_dispatch LOCAL_RELEASE=true)"
[ "$out" = local ] || { echo "FAIL dispatch+local_release should be local: '$out'"; exit 1; }

# a plain dispatch is not a repackage
out="$(got GITHUB_EVENT_NAME=workflow_dispatch LOCAL_RELEASE=false)"
[ "$out" = auto ] || { echo "FAIL plain dispatch should be auto: '$out'"; exit 1; }

# ...and an unset LOCAL_RELEASE is not a repackage either
out="$(got GITHUB_EVENT_NAME=workflow_dispatch)"
[ "$out" = auto ] || { echo "FAIL dispatch without the input should be auto: '$out'"; exit 1; }

# a push is never a repackage
out="$(got GITHUB_EVENT_NAME=push LOCAL_RELEASE=true)"
[ "$out" = auto ] || { echo "FAIL push should be auto even with the input set: '$out'"; exit 1; }

# a tag build takes its version from the tag, so the mode is irrelevant -- still answer auto rather
# than inventing a third value the callers would have to handle
out="$(got GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag)"
[ "$out" = auto ] || { echo "FAIL tag should be auto: '$out'"; exit 1; }

# no event at all (a developer running it by hand) -> auto, the safe answer: it never invents a new N
out="$(got PATH="$PATH")"
[ "$out" = auto ] || { echo "FAIL bare invocation should be auto: '$out'"; exit 1; }

echo "PASS: release-mode"

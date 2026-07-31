#!/bin/sh
# Artifact conformance: an artifact must match ITSELF, its NEIGHBOURS, and its SIBLINGS, unless the
# product declares a deviation with a reason.
#
# The checker consumes a fact stream so it can be tested without fabricating real .pkg files; the
# extraction that produces those facts is exercised for real in CI at package time.
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
S="$here/../scripts/check-artifact-conformance.sh"

ok() {  # facts on stdin must pass
  printf '%s\n' "$2" | sh "$S" >/dev/null 2>&1 || { echo "FAIL $1: expected pass"; exit 1; }
}
no() {  # facts on stdin must fail, and name the check
  out="$(printf '%s\n' "$3" | sh "$S" 2>&1)" && { echo "FAIL $1: expected failure"; exit 1; }
  printf '%s\n' "$out" | grep -qi "$2" || { echo "FAIL $1: should mention '$2', got: $out"; exit 1; }
}

GOOD='expected 1.26.5-mavericks.5
pkg golang-1.26.5-native-mavericks.5.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
appcast appcast.xml 1.26.5-mavericks.5 golang-1.26.5-native-mavericks.5.pkg 4096 10.9.5
asset golang-1.26.5-native-mavericks.5.pkg 4096
asset appcast.xml 700'
ok "a coherent release" "$GOOD"

# --- matches ITSELF -------------------------------------------------------------------------------
no "pkg version disagrees with the tag" "version" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.4 10.9.5 dev.modernmavericks.golang.go126
asset p.pkg 10'

no "appcast version disagrees with the pkg" "version" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
appcast appcast.xml 1.26.5-mavericks.4 p.pkg 10
asset p.pkg 10
asset appcast.xml 700'

no "appcast points at an asset that was not published" "enclosure" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.modernmavericks.x
appcast appcast.xml 1.0.0-mavericks.1 ghost.pkg 10
asset p.pkg 10
asset appcast.xml 700'

no "appcast enclosure length disagrees with the real file" "length" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 dev.modernmavericks.x
appcast appcast.xml 1.0.0-mavericks.1 p.pkg 999
asset p.pkg 10
asset appcast.xml 700'

no "a .pkg without the 10.9.5 floor" "floor" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.13 dev.modernmavericks.x
asset p.pkg 10'

no "an identifier outside the family scheme" "identifier" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 10.9.5 com.example.thing
asset p.pkg 10'

# --- matches its SIBLINGS -------------------------------------------------------------------------
no "a version outside the family scheme" "scheme" 'expected 1.0.0
pkg p.pkg 1.0.0 10.9.5 dev.modernmavericks.x
asset p.pkg 10'

# --- matches its NEIGHBOURS -----------------------------------------------------------------------
no "two pkgs of one release disagree about the version" "version" 'expected 1.0.0-mavericks.1
pkg native.pkg 1.0.0-mavericks.1 10.9.5 dev.modernmavericks.x
pkg cross.pkg 1.0.0-mavericks.2 10.9.5 dev.modernmavericks.x-cross
asset native.pkg 10
asset cross.pkg 10'

# a product with no updater ships no appcast, and that is fine
ok "a tools product with no updater" 'expected 20221003-mavericks.2
pkg ed25519-20221003-mavericks.2.pkg 20221003-mavericks.2 10.9.5 dev.modernmavericks.ed25519
asset ed25519-20221003-mavericks.2.pkg 10'

# --- FLOORS: a product archive declares one; a COMPONENT package cannot ----------------------------
# A component .pkg (PackageInfo, no Distribution) has no os-version floor by construction -- floors are
# a productbuild concept. Its effective minimum lives in the appcast that ships it. golang's cross
# product is exactly this: it TARGETS 10.9 but RUNS on 11.0+, so demanding 10.9.5 of it would be wrong.
ok "a component pkg whose appcast declares the minimum" 'expected 1.26.5-mavericks.5
pkg golang-cross.pkg 1.26.5-mavericks.5 none dev.modernmavericks.golang.go126-cross
appcast appcast-cross.xml 1.26.5-mavericks.5 golang-cross.pkg 10 11.0
asset golang-cross.pkg 10
asset appcast-cross.xml 700'

no "a pkg with no floor and no appcast to declare one" "floor" 'expected 1.0.0-mavericks.1
pkg orphan.pkg 1.0.0-mavericks.1 none dev.modernmavericks.x
asset orphan.pkg 10'

ok "a product archive that does declare 10.9.5" 'expected 1.0.0-mavericks.1
pkg native.pkg 1.0.0-mavericks.1 10.9.5 dev.modernmavericks.x
asset native.pkg 10'

# --- DEVIATIONS, declared with a reason -----------------------------------------------------------
no "an undeclared floor deviation still fails" "floor" 'expected 1.0.0-mavericks.1
pkg p.pkg 1.0.0-mavericks.1 11.0 dev.modernmavericks.x
asset p.pkg 10'

ok "a declared floor deviation passes" 'expected 1.0.0-mavericks.1
deviation floor the cross toolchain runs on modern macOS and targets 10.9; it is not itself a 10.9 install
pkg p.pkg 1.0.0-mavericks.1 11.0 dev.modernmavericks.x
asset p.pkg 10'

no "a deviation with no reason is not a deviation" "reason" 'expected 1.0.0-mavericks.1
deviation floor
pkg p.pkg 1.0.0-mavericks.1 11.0 dev.modernmavericks.x
asset p.pkg 10'

# a declared deviation is scoped to its own check: it does not excuse an unrelated failure
no "a floor deviation does not excuse a bad identifier" "identifier" 'expected 1.0.0-mavericks.1
deviation floor targets 10.9 rather than running on it
pkg p.pkg 1.0.0-mavericks.1 11.0 com.example.thing
asset p.pkg 10'

# --- SCOPED deviations: a mirrored third-party artifact is not ours to conform ---------------------
# swift-toolchain republishes swift.org's .pkg verbatim so the correspondence with download.swift.org
# stays checkable. Its version, floor and identifier are UPSTREAM's and must stay that way -- but that
# must not excuse the artifacts we do build alongside it.
MIRROR='expected 6.3.3-mavericks.2
deviation version:upstream-swift-*.pkg mirrored verbatim from swift.org; the version is upstream own
deviation floor:upstream-swift-*.pkg same mirror
deviation identifier:upstream-swift-*.pkg same mirror
pkg upstream-swift-6.3.3-RELEASE-osx.pkg 6.3.3.20260625101 10.11 org.swift.633202606251a
asset upstream-swift-6.3.3-RELEASE-osx.pkg 10'
ok "a scoped deviation excuses the mirrored pkg" "$MIRROR"

no "the same scoped deviation does NOT excuse our own artifact" "version" 'expected 6.3.3-mavericks.2
deviation version:upstream-swift-*.pkg mirrored verbatim from swift.org
pkg ours.pkg 6.3.3-mavericks.1 10.9.5 dev.modernmavericks.swift
asset ours.pkg 10'

# --- the appcast must point INTO THIS RELEASE ------------------------------------------------------
# An enclosure URL carries the release tag. If it names another release, Sparkle serves users a
# different build than the one just published -- the feed and the release silently disagree, and every
# other check still passes because both artifacts are individually fine.
ok "an enclosure pointing at this release" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
appcast appcast.xml 1.26.5-mavericks.5 p.pkg 10 10.9.5
enclosure-url appcast.xml https://github.com/ModernMavericks/golang/releases/download/1.26.5-mavericks.5/p.pkg
asset p.pkg 10
asset appcast.xml 700'

no "an enclosure pointing at a DIFFERENT release" "enclosure-url" 'expected 1.26.5-mavericks.5
pkg p.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
appcast appcast.xml 1.26.5-mavericks.5 p.pkg 10 10.9.5
enclosure-url appcast.xml https://github.com/ModernMavericks/golang/releases/download/1.26.5-mavericks.4/p.pkg
asset p.pkg 10
asset appcast.xml 700'

# --- line-scoped identity -------------------------------------------------------------------------
# Where a repo ships parallel upstream lines, the line IS the product: go126 and go127 must not share
# an identifier, or two products claim one install and the updater cannot tell them apart.
ok "identifiers carrying their line" 'expected 1.26.5-mavericks.5
line 126
pkg native.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
pkg cross.pkg 1.26.5-mavericks.5 none dev.modernmavericks.golang.go126-cross
appcast appcast-cross.xml 1.26.5-mavericks.5 cross.pkg 10 11.0
asset native.pkg 10
asset cross.pkg 10
asset appcast-cross.xml 700'

no "an identifier missing its line" "line" 'expected 1.26.5-mavericks.5
line 126
pkg native.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang
asset native.pkg 10'

# a repo with no lines is not asked the question
ok "a single-line product" 'expected 1.5.2-mavericks.2
pkg p.pkg 1.5.2-mavericks.2 10.9.5 dev.modernmavericks.legacysupport
asset p.pkg 10'

# --- NEIGHBOURS: variants of one release were built from the same ingredients ----------------------
# The artifacts cannot answer this: golang's native .pkg carries the CA bundle and the shim, its cross
# .pkg legitimately does not (cross-built apps look at the native prefix). "Same shim, same CA" is a
# claim about INPUTS, so each variant records what it used and conformance compares the records.
ok "variants agreeing on their ingredients" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt mls_version 1.5.2-mavericks.2
build-info build-info-native.txt ca_sha256 3ff344e30b9b
build-info build-info-cross.txt mls_version 1.5.2-mavericks.2
build-info build-info-cross.txt ca_sha256 3ff344e30b9b
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
asset n.pkg 10'

no "variants built from DIFFERENT shim pins" "mls_version" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt mls_version 1.5.2-mavericks.2
build-info build-info-cross.txt mls_version 1.5.2-mavericks.1
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
asset n.pkg 10'

no "variants built from different CA bundles" "ca_sha256" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt ca_sha256 3ff344e30b9b
build-info build-info-cross.txt ca_sha256 9a1c72b4aa0f
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
asset n.pkg 10'

# keys that SHOULD differ per variant are not evidence of disagreement
ok "per-variant keys may differ" 'expected 1.26.5-mavericks.5
build-info build-info-native.txt variant native
build-info build-info-native.txt arch x86_64
build-info build-info-native.txt prefix /usr/local/go126
build-info build-info-cross.txt variant cross
build-info build-info-cross.txt arch arm64
build-info build-info-cross.txt prefix /usr/local/go126-cross
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
asset n.pkg 10'

# a single-variant product has nothing to compare against
ok "one variant, nothing to disagree with" 'expected 1.5.2-mavericks.2
build-info build-info.txt mls_version 1.5.2-mavericks.2
pkg p.pkg 1.5.2-mavericks.2 10.9.5 dev.modernmavericks.legacysupport
asset p.pkg 10'

ok "a declared disagreement, with a reason" 'expected 1.26.5-mavericks.5
deviation ingredients the cross variant is deliberately built against the previous shim this once
build-info build-info-native.txt mls_version 1.5.2-mavericks.2
build-info build-info-cross.txt mls_version 1.5.2-mavericks.1
pkg n.pkg 1.26.5-mavericks.5 10.9.5 dev.modernmavericks.golang.go126
asset n.pkg 10'

echo "PASS: artifact-conformance"

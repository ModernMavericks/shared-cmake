#!/bin/sh
# Assert that a release's artifacts match ITSELF, its NEIGHBOURS, and its SIBLINGS.
#
# This constrains OUTPUTS, not methods. Products here build in genuinely different ways -- a Go
# toolchain, a boot2docker iso, libswiftCore, an openssh -- and making those look alike would buy
# uniformity by inventing a bespoke "kind" per product. What must not vary is what comes out:
# a release whose .pkg, appcast, checksums and tag disagree is incoherent no matter how it was built.
#
# Every piece here already exists somewhere -- the compat guard checks binaries, set_install_floor
# stamps a floor, sign_and_appcast signs, publish-release checksums -- but nothing asserted they agree
# WITH EACH OTHER. That gap is where a release can be internally wrong while every step is green.
#
# Reads a FACT STREAM on stdin (see artifact-facts.sh), one record per line:
#   expected   <version>                                  the version this release claims to be
#   pkg        <file> <version> <floor> <identifier>      one per shipped .pkg
#   appcast    <file> <version> <enclosure> <length>      one per Sparkle appcast
#   asset      <file> <bytes>                             one per file that will be published
#   deviation  <check> <reason...>                        a declared, reasoned departure
#
# Facts rather than files so the agreement logic is testable without fabricating real .pkg files;
# extraction is thin and exercised for real at package time.
#   usage: artifact-facts.sh dist "$VER" | check-artifact-conformance.sh
set -eu

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
facts="$tmp/facts"; cat > "$facts"

status=0
fail() {  # $1 = check name, $2 = message, $3 = the artifact it concerns (optional)
  # A deviation excuses only its OWN check, only for the artifacts it names, and only with a reason.
  # An unexplained departure is indistinguishable from a mistake, and an unscoped one silently covers
  # artifacts nobody meant to excuse: swift-toolchain republishes swift.org's .pkg verbatim, which must
  # not license the things it builds itself to drift.
  _c="$1"; _msg="$2"; _file="${3:-}"
  # exact-check deviation (applies to every artifact)
  reason="$(sed -n "s/^deviation ${_c} \(..*\)$/\1/p" "$facts" | head -1)"
  if [ -z "$reason" ] && [ -n "$_file" ]; then
    # scoped: deviation <check>:<glob>
    while IFS= read -r line; do
      # line: `deviation <check>:<glob> <reason...>` -- strip the fixed prefix first, then split the
      # glob from the reason. Taking the first WORD of the whole line yields "deviation".
      rest="${line#deviation ${_c}:}"
      glob="${rest%% *}"
      why="${rest#* }"
      [ "$why" = "$rest" ] && why=""      # no space => a glob with no reason, which is not a deviation
      case "$_file" in
        $glob) [ -n "$why" ] && reason="$why" && break ;;
      esac
    done <<EOF
$(grep "^deviation ${_c}:" "$facts" || true)
EOF
  fi
  if [ -n "$reason" ]; then
    echo "conformance: ${_c}: DECLARED DEVIATION${_file:+ (${_file})} -- $reason"
    return 0
  fi
  if grep -q "^deviation ${_c}\$" "$facts"; then
    echo "conformance: ${_c}: deviation declared with no reason -- state why, or fix the artifact" >&2
    status=1; return 0
  fi
  echo "conformance: ${_c}: ${_msg}" >&2
  status=1
}

expected="$(sed -n 's/^expected \(..*\)$/\1/p' "$facts" | head -1)"
[ -n "$expected" ] || { echo "conformance: no expected version in the fact stream" >&2; exit 2; }

# --- SIBLINGS: the family's version scheme --------------------------------------------------------
case "$expected" in
  *-mavericks.[0-9]*) : ;;
  *) fail scheme "version '$expected' is not <upstream>-mavericks.N" ;;
esac

# --- ITSELF / NEIGHBOURS: every .pkg agrees with the tag, the floor, and the identifier scheme -----
while read -r kind file ver floor ident; do
  [ "$kind" = pkg ] || continue
  [ "$ver" = "$expected" ] \
    || fail version "$file says version $ver, the release is $expected" "$file"
  # A PRODUCT ARCHIVE declares its floor in Distribution and it must be 10.9.5. A COMPONENT package
  # (PackageInfo, no Distribution) cannot declare one at all -- floors are a productbuild concept --
  # so its effective minimum lives in the appcast that ships it. golang's cross product is exactly
  # that case: it TARGETS 10.9 but RUNS on 11.0+, so demanding 10.9.5 of it would be wrong.
  if [ "$floor" = none ]; then
    grep -q "^appcast .* $file [0-9][0-9]* [0-9]" "$facts" \
      || fail floor "$file declares no install floor, and no appcast declares a minimum system version for it" "$file"
  else
    [ "$floor" = 10.9.5 ] \
      || fail floor "$file declares an install floor of $floor, not 10.9.5" "$file"
  fi
  case "$ident" in
    dev.modernmavericks.*) : ;;
    *) fail identifier "$file has identifier '$ident', outside dev.modernmavericks.*" "$file" ;;
  esac
done < "$facts"

# --- ITSELF: the appcast describes THIS release, and an asset that exists at the size it claims ----
while read -r kind file ver enclosure length minos; do
  [ "$kind" = appcast ] || continue
  [ "$ver" = "$expected" ] \
    || fail version "$file advertises version $ver, the release is $expected" "$file"
  actual="$(sed -n "s/^asset $enclosure \(..*\)$/\1/p" "$facts" | head -1)"
  if [ -z "$actual" ]; then
    fail enclosure "$file points at '$enclosure', which is not among the published assets" "$file"
  elif [ "$actual" != "$length" ]; then
    fail length "$file says '$enclosure' is $length bytes; it is $actual" "$file"
  fi
done < "$facts"

[ "$status" -eq 0 ] && echo "conformance: ok — $expected"
exit "$status"

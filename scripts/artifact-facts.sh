#!/bin/sh
# Emit the fact stream check-artifact-conformance.sh consumes, by inspecting a built dist/ directory
# and the repo it came from. Deliberately thin: all judgement lives in the checker, so this can be read
# in one sitting and the interesting logic stays testable without fabricating .pkg files.
#
#   usage: artifact-facts.sh <dist-dir> <version> [repo-root]
#
# Runs at PACKAGE TIME, on macOS, where pkgutil exists and the artifacts do -- not in the conventions
# gate, which reads a repo in seconds and gates every PR.
set -eu
dist="${1:?artifact-facts: dist directory required}"
version="${2:?artifact-facts: version required}"
root="${3:-$(pwd)}"

printf 'expected %s\n' "$version"

# Declared deviations live in INGREDIENTS.md, under "## Conformance deviations", as
#   - <check>: <reason>
# A deviation IS a product fact, which is why it belongs with the other product facts rather than in a
# file of its own that could disagree with them.
if [ -f "$root/INGREDIENTS.md" ]; then
  sed -n '/^## Conformance deviations/,/^## /p' "$root/INGREDIENTS.md" \
    | sed -n 's/^- *\([a-z][a-z0-9_-]*\)\(:[^ :]*\)\{0,1\} *: *\(..*\)$/deviation \1\2 \3/p'
fi

for f in "$dist"/*; do
  [ -f "$f" ] || continue
  b="${f##*/}"
  printf 'asset %s %s\n' "$b" "$(wc -c < "$f" | tr -d ' ')"

  case "$b" in
    *.pkg)
      # pkgutil is the only way to read what the .pkg actually declares; a filename is a claim, not a
      # fact, and the whole point here is to compare claims against what shipped.
      x="$(mktemp -d)"
      if pkgutil --expand "$f" "$x/x" >/dev/null 2>&1; then
        if [ -f "$x/x/Distribution" ]; then
          # A product archive: version, floor and identity all live in Distribution.
          ver="$(sed -n 's/.*<pkg-ref[^>]*version="\([^"]*\)".*/\1/p' "$x/x/Distribution" | head -1)"
          floor="$(sed -n 's/.*<os-version[^>]*min="\([^"]*\)".*/\1/p' "$x/x/Distribution" | head -1)"
          ident="$(sed -n 's/.*<pkg-ref[^>]*id="\([^"]*\)".*/\1/p' "$x/x/Distribution" | head -1)"
        else
          # A component package: PackageInfo carries version and identity, and there is NO floor to
          # read -- that is structural, not a defect. The checker requires an appcast to declare the
          # minimum instead.
          # Anchor on a SPACE before the attribute name: `[^>]*version="` also matches
          # generator-version="InstallCmds-864.1 (25E246)", whose value contains a space and so shifts
          # every field of the record after it -- corrupting the floor and identifier as well.
          # Restrict to the <pkg-info> element AND anchor on a space before the attribute. Without the
          # element restriction, line 1's <?xml version="1.0"?> matches first; without the space
          # anchor, generator-version="InstallCmds-864.1 (25E246)" matches and its embedded space
          # shifts every later field. Both bugs read as artifact defects rather than parser defects.
          ver="$(sed -n '/<pkg-info/ s/.*[[:space:]]version="\([^"]*\)".*/\1/p' "$x/x/PackageInfo" 2>/dev/null | head -1)"
          ident="$(sed -n '/<pkg-info/ s/.*[[:space:]]identifier="\([^"]*\)".*/\1/p' "$x/x/PackageInfo" 2>/dev/null | head -1)"
          floor=""
        fi
        # The fact stream is whitespace-delimited, so a value containing a space would silently shift
        # the fields after it. Collapse any to underscores: a mangled-looking value is a visible
        # symptom, where a shifted record is an invisible one that fails the WRONG check.
        printf 'pkg %s %s %s %s\n' "$b" \
          "$(printf '%s' "${ver:-unknown}" | tr -s '[:space:]' '_')" \
          "$(printf '%s' "${floor:-none}" | tr -s '[:space:]' '_')" \
          "$(printf '%s' "${ident:-none}" | tr -s '[:space:]' '_')"
      else
        printf 'pkg %s unreadable none none\n' "$b"
      fi
      rm -rf "$x"
      ;;
    *appcast*.xml)
      # sparkle:version and the minimum system version are ELEMENTS, not attributes -- the enclosure's
      # attributes carry only the URL, length and signature.
      ver="$(sed -n 's|.*<sparkle:version>\([^<]*\)<.*|\1|p' "$f" | head -1)"
      minos="$(sed -n 's|.*<sparkle:minimumSystemVersion>\([^<]*\)<.*|\1|p' "$f" | head -1)"
      url="$(sed -n 's/.*<enclosure[^>]*url="\([^"]*\)".*/\1/p' "$f" | head -1)"
      len="$(sed -n 's/.*<enclosure[^>]*length="\([^"]*\)".*/\1/p' "$f" | head -1)"
      printf 'appcast %s %s %s %s %s\n' "$b" "${ver:-unknown}" "${url##*/}" "${len:-0}" "${minos:-none}"
      ;;
  esac
done

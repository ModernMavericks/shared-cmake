#!/bin/sh
# Prove sign_and_appcast.sh assembles the EdDSA enclosure attrs (edSignature from the signer's bare
# base64 signature + length from the pkg), renders version + notes, and emits the appcast. Uses a stub
# signer -- the real ed25519-sign lives in mavericks-ed25519; this exercises the orchestration, not the
# crypto (so no compiler or network fetch needed).
set -eu
ROOT="$1"
T=$(mktemp -d "${TMPDIR:-/tmp}/mav-signappcast.XXXXXX")
trap 'rm -rf "$T"' EXIT

# stub ed25519-sign: -s <key> <file> -> a fixed, well-formed base64 signature on stdout.
SIG="c3R1YnNpZ25hdHVyZWZvcnRlc3Rpbmdvbmx5QUFBQUFBQUFBQUFBQUFBQUFBQUFBQT09"
cat > "$T/sign" <<EOF
#!/bin/sh
echo "$SIG"
EOF
chmod +x "$T/sign"

printf 'dummy pkg bytes\n' > "$T/x.pkg"
printf '## Notes\n\n- thing one\n- thing two\n' > "$T/notes.md"
LEN=$(wc -c < "$T/x.pkg" | tr -d '[:space:]')

OUT=$(SPARKLE_PRIVATE_KEY="ignored-by-stub" sh "$ROOT/scripts/sign_and_appcast.sh" \
  --signer "$T/sign" --channel-title "Test Channel" --version 1.2.3 \
  --pkg-url "https://example.invalid/x.pkg" --notes-file "$T/notes.md" --pkg "$T/x.pkg")

fail() { echo "sign_and_appcast test: $1" >&2; exit 1; }
printf '%s\n' "$OUT" | grep -q "sparkle:edSignature=\"$SIG\"" || fail "signer's signature not in the enclosure"
printf '%s\n' "$OUT" | grep -q "length=\"$LEN\"" || fail "pkg length not in the enclosure"
printf '%s\n' "$OUT" | grep -q '<sparkle:version>1.2.3</sparkle:version>' || fail "version missing"
printf '%s\n' "$OUT" | grep -q 'https://example.invalid/x.pkg' || fail "enclosure url missing"
printf '%s\n' "$OUT" | grep -q '<li>thing one</li>' || fail "notes not rendered"

echo "sign_and_appcast OK"

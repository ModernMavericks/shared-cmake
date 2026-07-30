#!/usr/bin/env bats

setup() { SCRIPT="${BATS_TEST_DIRNAME}/../scripts/gen_appcast.sh"; }

@test "render-notes converts markdown subset to html" {
  printf '## Head\n\n- one\n- two\n\n**bold** and *em*\n' > "$BATS_TMPDIR/n.md"
  run sh "$SCRIPT" --render-notes "$BATS_TMPDIR/n.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"<h2>Head</h2>"* ]]
  [[ "$output" == *"<li>one</li>"* ]]
  [[ "$output" == *"<strong>bold</strong>"* ]]
}

@test "channel title is parameterized" {
  printf 'notes\n' > "$BATS_TMPDIR/n.md"
  run sh "$SCRIPT" "My Product" "1.2.3" "http://x/y.pkg" "10.9.5" "$BATS_TMPDIR/n.md" 'length="1"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"<title>My Product</title>"* ]]
  [[ "$output" == *"<sparkle:version>1.2.3</sparkle:version>"* ]]
}

# Sparkle's comparator can't order "-mavericks.N", so <sparkle:version> (the compared value) must be
# numeric-only (X.Y.Z.N) while the human string stays in shortVersionString. Without this, same-upstream
# repackages are invisible to auto-update. Regression guard for that bug.
@test "sparkle:version is numeric-only for a -mavericks.N version; short string stays pretty" {
  printf 'notes\n' > "$BATS_TMPDIR/n.md"
  run sh "$SCRIPT" "P" "1.102.0-mavericks.4" "http://x/y.pkg" "10.9.5" "$BATS_TMPDIR/n.md" 'length="1"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"<sparkle:version>1.102.0.4</sparkle:version>"* ]]
  [[ "$output" == *"<sparkle:shortVersionString>1.102.0-mavericks.4</sparkle:shortVersionString>"* ]]
  [[ "$output" != *"<sparkle:version>1.102.0-mavericks.4</sparkle:version>"* ]]
}

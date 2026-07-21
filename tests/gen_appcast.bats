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

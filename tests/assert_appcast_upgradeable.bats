#!/usr/bin/env bats
# Tests for scripts/assert_appcast_upgradeable.sh -- the "auto-update will see this as newer" gate.
# A local fixture repo with prior -mavericks.N tags stands in for a release history; no network, no
# Sparkle framework (the gate reasons over the numeric domain SUStandardVersionComparator orders).

setup() {
  GATE="$BATS_TEST_DIRNAME/../scripts/assert_appcast_upgradeable.sh"
  WORK="$(mktemp -d -t appcast_upgradeable_test)"
  REPO="$WORK/repo"; mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  git -C "$REPO" commit -q --allow-empty -m init
  git -C "$REPO" tag 1.102.0-mavericks.6
  git -C "$REPO" tag 1.102.0-mavericks.7
}
teardown() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }

# write an appcast carrying $1 as <sparkle:version>, echo its path
appcast() {
  f="$WORK/appcast.xml"
  printf '<rss><channel><item><sparkle:version>%s</sparkle:version></item></channel></rss>\n' "$1" > "$f"
  echo "$f"
}

@test "numeric and greater than the highest prior tag: passes" {
  run sh -c "cd '$REPO' && sh '$GATE' --appcast '$(appcast 1.102.0.8)' --version 1.102.0-mavericks.8"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '> previous 1.102.0.7'
}

@test "the shipped bug shape (sparkle:version still carries -mavericks.N): rejected" {
  run sh -c "cd '$REPO' && sh '$GATE' --appcast '$(appcast 1.102.0-mavericks.8)' --version 1.102.0-mavericks.8"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'not purely dotted-numeric'
}

@test "numeric but not greater (re-cut an existing N): rejected" {
  run sh -c "cd '$REPO' && sh '$GATE' --appcast '$(appcast 1.102.0.7)' --version 1.102.0-mavericks.7x"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'does NOT order after previous'
}

@test "lower than the highest prior tag: rejected" {
  run sh -c "cd '$REPO' && sh '$GATE' --appcast '$(appcast 1.102.0.6)' --version 1.102.0-mavericks.6x"
  [ "$status" -ne 0 ]
}

@test "N=10 beats N=9 (numeric, not lexical): passes" {
  git -C "$REPO" tag 1.102.0-mavericks.9
  run sh -c "cd '$REPO' && sh '$GATE' --appcast '$(appcast 1.102.0.10)' --version 1.102.0-mavericks.10"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '> previous 1.102.0.9'
}

@test "first release (no prior tags): skips ordering, but says so" {
  empty="$WORK/empty"; mkdir -p "$empty"; git -C "$empty" init -q
  run sh -c "cd '$empty' && sh '$GATE' --appcast '$(appcast 1.0.0.1)' --version 1.0.0-mavericks.1"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'first release'
}

@test "not a git checkout: fails rather than skipping silently" {
  run sh -c "cd '$WORK' && sh '$GATE' --appcast '$(appcast 1.0.0.1)' --version 1.0.0-mavericks.1"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'refusing to skip silently'
}

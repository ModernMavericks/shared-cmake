#!/usr/bin/env bats
# Tests for scripts/clone_pinned.sh -- the git-source supply-chain boundary. No network: a local
# fixture repo (tag v1 on commit A, then commit B) stands in for upstream.

setup() {
  HELPER="$BATS_TEST_DIRNAME/../scripts/clone_pinned.sh"
  WORK="$(mktemp -d -t clone_pinned_test)"
  UP="$WORK/upstream"; mkdir -p "$UP"
  git -C "$UP" init -q
  git -C "$UP" config user.email t@t; git -C "$UP" config user.name t
  echo a > "$UP/f"; git -C "$UP" add f; git -C "$UP" commit -qm A
  git -C "$UP" tag v1
  A="$(git -C "$UP" rev-parse HEAD)"
  echo b > "$UP/f"; git -C "$UP" commit -qam B
  DEST="$WORK/dest"
}
teardown() { rm -rf "$WORK"; }

@test "pinned digest == the tag's commit: clones and verifies" {
  run sh "$HELPER" "$UP" v1 "$A" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$A" ]
}

@test "unknown digest (moved/forced tag, tamper): bails non-zero, leaves no dest" {
  BAD="$(printf 'a%.0s' $(seq 40))"   # 40 hex chars, not a real commit
  run sh "$HELPER" "$UP" v1 "$BAD" "$DEST"
  [ "$status" -ne 0 ]
  [ ! -d "$DEST/.git" ]
}

@test "empty digest: TOFU clone of the ref (migration affordance)" {
  run sh "$HELPER" "$UP" v1 "" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$A" ]
}

@test "cache hit: second call no-ops even with a bogus repo" {
  run sh "$HELPER" "$UP" v1 "$A" "$DEST"; [ "$status" -eq 0 ]
  run sh "$HELPER" /no/such/repo v1 "$A" "$DEST"
  [ "$status" -eq 0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$A" ]
}

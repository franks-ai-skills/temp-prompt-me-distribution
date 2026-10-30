#!/usr/bin/env bash
# Tests for scripts/sync.sh against throwaway source and distribution
# repositories. Usage: tests/sync_test.sh [test_name...]

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

SOURCE_SUBJECT='feat: distinctive source subject'
SKILL=.agents/skills/prompt-me

setup() {
  TMP=$(mktemp -d)
  SRC=$TMP/src
  DIST=$TMP/dist

  git init -q -b main "$SRC"
  mkdir -p "$SRC/$SKILL/references"
  printf -- '---\nname: prompt-me\n---\n# Prompt me\n' > "$SRC/$SKILL/SKILL.md"
  echo requirements > "$SRC/$SKILL/references/requirements.md"
  : > "$SRC/$SKILL/references/.gitkeep"
  echo readme > "$SRC/README.md"
  git -C "$SRC" add -A
  git -C "$SRC" commit -q -m "$SOURCE_SUBJECT"

  git init -q -b main "$DIST"
  mkdir -p "$DIST/.claude-plugin"
  cp "$REPO_ROOT/.claude-plugin/marketplace.json" "$REPO_ROOT/.claude-plugin/plugin.json" "$DIST/.claude-plugin/"
  cp "$REPO_ROOT/plugin.json" "$REPO_ROOT/.gitattributes" "$REPO_ROOT/.gitignore" "$DIST/"
  # The real manifests carry the last published version; the fixture
  # starts from "nothing published yet".
  set_dist_versions 0.0.0
  git -C "$DIST" add -A
  git -C "$DIST" commit -q -m init
}

# run_sync [args...]: runs sync.sh with cwd ${RUN_DIR:-$DIST}; sets OUT,
# ERR and STATUS.
run_sync() {
  OUT=$(cd "${RUN_DIR:-$DIST}" && "$BASH" "$REPO_ROOT/scripts/sync.sh" "$@" 2> "$TMP/stderr")
  STATUS=$?
  ERR=$(cat "$TMP/stderr")
}

src_commit() {
  git -C "$SRC" add -A
  git -C "$SRC" commit -q -m "$1"
}

dist_commit() {
  git -C "$DIST" add -A
  git -C "$DIST" commit -q -m "$1"
}

set_dist_versions() {
  local f
  for f in "$DIST/.claude-plugin/plugin.json" "$DIST/plugin.json"; do
    jq --arg v "$1" '.version = $v' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
}

dist_versions() {
  echo "$(jq -r .version "$DIST/.claude-plugin/plugin.json") $(jq -r .version "$DIST/plugin.json")"
}

src_sha() { git -C "$SRC" rev-parse HEAD; }
src_tree() { git -C "$SRC" rev-parse "HEAD:$SKILL"; }
dist_tree() { git -C "$DIST" rev-parse HEAD:skills/prompt-me; }
dist_tags() { git -C "$DIST" tag -l | tr '\n' ' ' | sed 's/ $//'; }

# state: everything a refused or no-change run must leave untouched.
state() {
  git -C "$DIST" rev-parse HEAD
  git -C "$DIST" tag -l
  git -C "$DIST" status --porcelain --ignored
}

test_first_run_publishes_0_0_1() {
  local sha
  sha=$(src_sha)
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "0.0.1 0.0.1" "$(dist_versions)" "versions"
  assert_eq "$(src_tree)" "$(dist_tree)" "published tree"
  assert_eq "v0.0.1" "$(dist_tags)" "tags"
  assert_eq tag "$(git -C "$DIST" cat-file -t v0.0.1)" "tag type"
  assert_eq "chore(release): v0.0.1 from prompt-me ${sha:0:7}" "$(git -C "$DIST" log -1 --format=%s)" "subject"
  assert_contains "$(git -C "$DIST" log -1 --format=%b)" "$sha" "body sha"
  assert_contains "$(git -C "$DIST" log -1 --format=%b)" "$SOURCE_SUBJECT" "body subject"
  assert_contains "$(git -C "$DIST" tag -l --format='%(contents)' v0.0.1)" "$sha" "tag sha"
  assert_contains "$(git -C "$DIST" tag -l --format='%(contents)' v0.0.1)" "$SOURCE_SUBJECT" "tag subject"
  assert_eq "" "$(git -C "$DIST" status --porcelain)" "clean tree"
}

test_rerun_without_change_writes_nothing() {
  local before sha
  sha=$(src_sha)
  run_sync "$SRC"
  before=$(state)
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "$before" "$(state)" "state"
  assert_contains "$OUT" "no change: still v0.0.1 (prompt-me ${sha:0:7})" "message"
}

test_source_change_outside_skill_writes_nothing() {
  local before
  run_sync "$SRC"
  before=$(state)
  echo more >> "$SRC/README.md"
  src_commit "docs: readme only"
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "$before" "$(state)" "state"
}

test_changed_file_publishes_0_0_2() {
  run_sync "$SRC"
  echo more >> "$SRC/$SKILL/SKILL.md"
  src_commit "fix: change skill"
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "0.0.2 0.0.2" "$(dist_versions)" "versions"
  assert_eq "v0.0.1 v0.0.2" "$(dist_tags)" "tags"
  assert_eq "$(src_tree)" "$(dist_tree)" "published tree"
}

test_deleted_file_disappears() {
  run_sync "$SRC"
  git -C "$SRC" rm -q "$SKILL/references/requirements.md"
  src_commit "fix: drop requirements"
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "0.0.2 0.0.2" "$(dist_versions)" "versions"
  [ ! -e "$DIST/skills/prompt-me/references/requirements.md" ] || fail "deleted file still present"
  assert_eq "$(src_tree)" "$(dist_tree)" "published tree"
}

test_special_files_published_unchanged() {
  mkdir -p "$SRC/$SKILL/scripts"
  printf '#!/bin/sh\necho hi\n' > "$SRC/$SKILL/scripts/run.sh"
  chmod 755 "$SRC/$SKILL/scripts/run.sh"
  echo log > "$SRC/$SKILL/debug.log"
  printf 'a\r\nb\r\n' > "$SRC/$SKILL/crlf.md"
  src_commit "feat: special files"
  git -C "$SRC" ls-files --error-unmatch "$SKILL/debug.log" > /dev/null || fail "fixture: debug.log not committed"
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "$(src_tree)" "$(dist_tree)" "published tree"
  assert_eq 100755 "$(git -C "$DIST" ls-files -s skills/prompt-me/scripts/run.sh | cut -c1-6)" "exec mode"
  [ -f "$DIST/skills/prompt-me/debug.log" ] || fail "ignored name not published"
  assert_eq "$(printf 'a\r\nb\r\n' | od -An -c)" "$(od -An -c < "$DIST/skills/prompt-me/crlf.md")" "crlf bytes"
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "rerun status ($ERR)"
  assert_contains "$OUT" "no change: still v0.0.1" "rerun message"
}

test_uncommitted_source_files_not_published() {
  echo uncommitted >> "$SRC/$SKILL/SKILL.md"
  echo extra > "$SRC/$SKILL/extra.md"
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "$(src_tree)" "$(dist_tree)" "published tree"
  [ ! -e "$DIST/skills/prompt-me/extra.md" ] || fail "untracked file published"
}

test_bump_is_numeric() {
  set_dist_versions 0.0.9
  dist_commit "chore: at 0.0.9"
  run_sync "$SRC"
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "0.0.10 0.0.10" "$(dist_versions)" "versions"
  assert_eq "v0.0.10" "$(dist_tags)" "tags"
}

test_github_output() {
  export GITHUB_OUTPUT=$TMP/output1
  run_sync "$SRC"
  assert_eq "$(printf 'changed=true\nversion=0.0.1')" "$(cat "$TMP/output1")" "first output"
  export GITHUB_OUTPUT=$TMP/output2
  run_sync "$SRC"
  assert_eq "$(printf 'changed=false\nversion=0.0.1')" "$(cat "$TMP/output2")" "rerun output"
}

test_relative_source_and_subdirectory() {
  RUN_DIR=$DIST/.claude-plugin run_sync ../../src
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "0.0.1 0.0.1" "$(dist_versions)" "versions"
}

# assert_refused <reason>: the run failed with a sync: message naming the
# reason and left the distribution repository as it was in $BEFORE.
assert_refused() {
  assert_eq 1 "$STATUS" "status"
  case "$ERR" in
    "sync: "*) ;;
    *) fail "stderr does not start with 'sync: ': [$ERR]" ;;
  esac
  assert_contains "$ERR" "$1" "reason"
  assert_eq "$BEFORE" "$(state)" "state"
}

fail_commits() {
  printf '#!/bin/sh\nexit 1\n' > "$DIST/.git/hooks/pre-commit"
  chmod 755 "$DIST/.git/hooks/pre-commit"
}

test_refuses_missing_argument() {
  BEFORE=$(state)
  run_sync
  assert_refused "usage: scripts/sync.sh <prompt-me-checkout>"
}

test_refuses_source_not_checkout_root() {
  BEFORE=$(state)
  run_sync "$SRC/.agents"
  assert_refused "root"
  git init -q -b main "$TMP/other"
  cp -R "$SRC" "$TMP/other/copy"
  rm -rf "$TMP/other/copy/.git"
  run_sync "$TMP/other/copy"
  assert_refused "root"
}

test_refuses_missing_skill() {
  git -C "$SRC" rm -q "$SKILL/SKILL.md"
  src_commit "chore: drop skill"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "SKILL.md"
}

test_refuses_symlink_in_source() {
  ln -s ../../../../README.md "$SRC/$SKILL/references/link"
  src_commit "feat: add link"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "symlink"
}

test_refuses_symlinked_ancestor() {
  mkdir -p "$SRC/real"
  git -C "$SRC" mv .agents/skills real/skills
  ln -s ../real/skills "$SRC/.agents/skills"
  src_commit "chore: move skills behind a symlink"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "SKILL.md"
}

test_refuses_dirty_tree() {
  echo dirty >> "$DIST/.gitignore"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "clean"
}

test_refuses_untracked_file() {
  echo notes > "$DIST/notes.txt"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "clean"
  assert_eq "?? notes.txt" "$(git -C "$DIST" status --porcelain)" "untracked file kept"
}

test_refuses_ignored_file_in_target() {
  run_sync "$SRC"
  : > "$DIST/skills/prompt-me/.DS_Store"
  echo more >> "$SRC/$SKILL/SKILL.md"
  src_commit "fix: change skill"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "ignored"
  [ -e "$DIST/skills/prompt-me/.DS_Store" ] || fail "ignored file was deleted"
}

test_refuses_duplicate_marketplace_entry() {
  local f=$DIST/.claude-plugin/marketplace.json
  jq '.plugins += [.plugins[0]]' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  dist_commit "chore: duplicate entry"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "marketplace"
}

test_refuses_mismatched_versions() {
  jq '.version = "0.0.3"' "$DIST/plugin.json" > "$TMP/p" && mv "$TMP/p" "$DIST/plugin.json"
  dist_commit "chore: mismatch"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "version"
}

test_refuses_non_0_0_n_version() {
  set_dist_versions 0.1.0
  dist_commit "chore: 0.1.0"
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "0.0.N"
}

test_refuses_existing_next_tag() {
  git -C "$DIST" tag v0.0.1
  BEFORE=$(state)
  run_sync "$SRC"
  assert_refused "v0.0.1"
}

test_rollback_on_commit_failure() {
  echo log > "$SRC/$SKILL/debug.log"
  src_commit "feat: log file"
  fail_commits
  BEFORE=$(state)
  run_sync "$SRC"
  [ "$STATUS" -ne 0 ] || fail "status: expected failure"
  assert_eq "$BEFORE" "$(state)" "state"
  [ ! -e "$DIST/skills" ] || fail "skills/ left behind"
}

test_rollback_keeps_previous_release() {
  run_sync "$SRC"
  echo more >> "$SRC/$SKILL/SKILL.md"
  echo extra > "$SRC/$SKILL/extra.md"
  src_commit "fix: change skill"
  fail_commits
  BEFORE=$(state)
  run_sync "$SRC"
  [ "$STATUS" -ne 0 ] || fail "status: expected failure"
  assert_eq "$BEFORE" "$(state)" "state"
  assert_eq "0.0.1 0.0.1" "$(dist_versions)" "versions"
  [ ! -e "$DIST/skills/prompt-me/extra.md" ] || fail "partial copy left behind"
}

run_tests "$@"

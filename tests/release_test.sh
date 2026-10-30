#!/usr/bin/env bash
# Tests for scripts/release.sh against a throwaway repository and a stub
# gh. Usage: tests/release_test.sh [test_name...]

# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

setup() {
  TMP=$(mktemp -d)
  REPO=$TMP/repo
  export STUB_GH_LOG=$TMP/gh.log
  export STUB_GH_LOOKUP=404

  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<'EOF'
#!/bin/sh
echo "$*" >> "$STUB_GH_LOG"
case "$1" in
  api)
    case "$STUB_GH_LOOKUP" in
      published) echo '{"draft":false}' ;;
      draft) echo '{"draft":true}' ;;
      404) echo 'gh: Not Found (HTTP 404)' >&2; exit 1 ;;
      error) echo 'gh: Bad credentials (HTTP 401)' >&2; exit 1 ;;
    esac
    ;;
esac
EOF
  chmod 755 "$TMP/bin/gh"

  git init -q -b main "$REPO"
  commit_version 0.0.1
  git -C "$REPO" tag -a v0.0.1 -m "release message"
}

commit_version() {
  echo "{\"version\": \"$1\"}" > "$REPO/plugin.json"
  git -C "$REPO" add plugin.json
  git -C "$REPO" commit -q -m "chore(release): v$1"
}

run_release() {
  OUT=$(cd "$REPO" && PATH="$TMP/bin:$PATH" "$BASH" "$REPO_ROOT/scripts/release.sh" "$@" 2> "$TMP/stderr")
  STATUS=$?
  ERR=$(cat "$TMP/stderr")
}

gh_calls() { cat "$STUB_GH_LOG" 2> /dev/null; }

assert_refused() {
  assert_eq 1 "$STATUS" "status"
  case "$ERR" in
    "release: "*) ;;
    *) fail "stderr does not start with 'release: ': [$ERR]" ;;
  esac
  assert_contains "$ERR" "$1" "reason"
}

assert_no_create() {
  case "$(gh_calls)" in
    *"release create"*) fail "release was created" ;;
  esac
}

test_zero_version_does_nothing() {
  run_release 0.0.0
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "" "$(gh_calls)" "gh calls"
}

test_refuses_invalid_version() {
  run_release 1.0
  assert_refused "0.0.N"
  assert_eq "" "$(gh_calls)" "gh calls"
}

test_refuses_missing_tag() {
  run_release 0.0.2
  assert_refused "v0.0.2"
  assert_eq "" "$(gh_calls)" "gh calls"
}

test_refuses_lightweight_tag() {
  commit_version 0.0.2
  git -C "$REPO" tag v0.0.2
  run_release 0.0.2
  assert_refused "annotated"
  assert_eq "" "$(gh_calls)" "gh calls"
}

test_refuses_tag_with_other_version() {
  git -C "$REPO" tag -a v0.0.3 -m "wrong commit"
  run_release 0.0.3
  assert_refused "0.0.3"
  assert_eq "" "$(gh_calls)" "gh calls"
}

test_accepts_published_release() {
  STUB_GH_LOOKUP=published run_release 0.0.1
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "api repos/{owner}/{repo}/releases/tags/v0.0.1" "$(gh_calls)" "gh calls"
  assert_contains "$OUT" "release v0.0.1 exists" "message"
}

test_refuses_draft() {
  STUB_GH_LOOKUP=draft run_release 0.0.1
  assert_refused "draft"
  assert_no_create
}

test_creates_release_on_404() {
  run_release 0.0.1
  assert_eq 0 "$STATUS" "status ($ERR)"
  assert_eq "$(printf '%s\n' 'api repos/{owner}/{repo}/releases/tags/v0.0.1' 'release create v0.0.1 --verify-tag --notes-from-tag --title v0.0.1')" "$(gh_calls)" "gh calls"
  assert_contains "$OUT" "created release v0.0.1" "message"
}

test_fails_on_api_error() {
  STUB_GH_LOOKUP=error run_release 0.0.1
  assert_refused "HTTP 401"
  assert_no_create
}

run_tests "$@"

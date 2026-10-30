# shellcheck shell=bash
# Shared helpers for the test scripts. Each test script defines `setup`
# and `test_*` functions, then calls `run_tests "$@"`.

export REPO_ROOT
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Isolate the tests from the caller's git configuration (signing,
# autocrlf, hooks) and from the GitHub Actions environment.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# The default excludes file (~/.config/git/ignore) applies even without
# a global config; switch it off as well.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.excludesFile GIT_CONFIG_VALUE_0=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
unset GITHUB_OUTPUT GITHUB_STEP_SUMMARY

FAILED=0

fail() {
  echo "    FAIL: $*" >&2
  FAILED=1
}

assert_eq() {
  if [ "$1" != "$2" ]; then
    fail "$3: expected [$1], got [$2]"
  fi
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "$3: [$2] not found in [$1]" ;;
  esac
}

# run_tests [name...]: runs the named tests, or every test_* function,
# each in its own subshell after a fresh `setup`.
run_tests() {
  local tests t failures=0 total=0
  if [ $# -gt 0 ]; then
    tests="$*"
  else
    tests=$(declare -F | awk '{print $3}' | grep '^test_')
  fi
  for t in $tests; do
    total=$((total + 1))
    if (
      setup
      "$t"
      status=$FAILED
      rm -rf "$TMP"
      exit "$status"
    ); then
      echo "PASS $t"
    else
      echo "FAIL $t"
      failures=$((failures + 1))
    fi
  done
  echo "$((total - failures))/$total passed"
  [ "$failures" -eq 0 ]
}

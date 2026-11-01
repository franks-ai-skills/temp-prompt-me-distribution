#!/usr/bin/env bash
# Publishes a local prompt-me checkout into a clone of this marketplace,
# installs the plugin in Claude Code and in Codex, then publishes a
# changed skill as the next version and updates both installs with the
# README's update commands. Each CLI gets a throwaway config folder;
# the real config folders are never touched.
#
# Usage: tests/smoke_install.sh <prompt-me-checkout>
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: tests/smoke_install.sh <prompt-me-checkout>" >&2; exit 1; }
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src=$(cd "$1" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=smoke GIT_AUTHOR_EMAIL=smoke@example.com
export GIT_COMMITTER_NAME=smoke GIT_COMMITTER_EMAIL=smoke@example.com
git clone -q "$src" "$work/src"
git clone -q "$REPO_ROOT" "$work/dist"

publish() {
  (cd "$work/dist" && "$BASH" scripts/sync.sh ../src >&2)
  jq -r .version "$work/dist/plugins/prompt-me/plugin.json"
}

export CLAUDE_CONFIG_DIR=$work/claude CODEX_HOME=$work/codex
mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME"

step() {
  echo "== $*"
  "$@" < /dev/null
}

# check_installs <version>: each CLI's cache holds the skill at
# <version> and none of the repository's own files.
check_installs() {
  local tool dir
  for tool in claude codex; do
    dir=$work/$tool/plugins/cache/temp-prompt-me-distribution/prompt-me/$1
    if [ ! -f "$dir/skills/prompt-me/SKILL.md" ]; then
      echo "FAIL: no skills/prompt-me/SKILL.md in the $tool install of $1" >&2
      exit 1
    fi
    if [ -e "$dir/scripts" ] || [ -e "$dir/tests" ]; then
      echo "FAIL: the $tool install of $1 contains repository files" >&2
      exit 1
    fi
    echo "ok: $tool installed ${dir#"$work/"}"
  done
}

version=$(publish)
step claude plugin validate "$work/dist"
step claude plugin marketplace add "$work/dist"
step claude plugin install prompt-me@temp-prompt-me-distribution
step codex plugin marketplace add "$work/dist"
step codex plugin add prompt-me@temp-prompt-me-distribution
check_installs "$version"

echo "smoke" >> "$work/src/.agents/skills/prompt-me/SKILL.md"
git -C "$work/src" commit -q -am "test: smoke change"
version=$(publish)
step claude plugin marketplace update temp-prompt-me-distribution
step claude plugin update prompt-me@temp-prompt-me-distribution
# The README also runs `codex plugin marketplace upgrade` first. It
# refreshes Git marketplaces only and refuses this local one.
step codex plugin add prompt-me@temp-prompt-me-distribution
check_installs "$version"

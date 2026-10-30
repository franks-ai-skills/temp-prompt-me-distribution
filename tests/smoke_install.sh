#!/usr/bin/env bash
# Builds this marketplace at 0.0.1 from a local prompt-me checkout and
# installs the plugin in Claude Code and in Codex, each with a throwaway
# config folder. The real config folders are never touched.
#
# Usage: tests/smoke_install.sh <prompt-me-checkout>
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: tests/smoke_install.sh <prompt-me-checkout>" >&2; exit 1; }
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
src=$(cd "$1" && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git clone -q "$REPO_ROOT" "$work/dist"
(
  cd "$work/dist"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=smoke GIT_AUTHOR_EMAIL=smoke@example.com
  export GIT_COMMITTER_NAME=smoke GIT_COMMITTER_EMAIL=smoke@example.com
  "$BASH" scripts/sync.sh "$src"
)

export CLAUDE_CONFIG_DIR=$work/claude CODEX_HOME=$work/codex
mkdir -p "$CLAUDE_CONFIG_DIR" "$CODEX_HOME"

step() {
  echo "== $*"
  "$@" < /dev/null
}

step claude plugin validate "$work/dist"
step claude plugin marketplace add "$work/dist"
step claude plugin install prompt-me@temp-prompt-me-distribution
step claude plugin list
step codex plugin marketplace add "$work/dist"
step codex plugin add prompt-me@temp-prompt-me-distribution
step codex plugin list

for tool in claude codex; do
  found=$(find "$work/$tool" -path '*/skills/prompt-me/SKILL.md' | head -1)
  if [ -z "$found" ]; then
    echo "FAIL: no skills/prompt-me/SKILL.md in the $tool install" >&2
    exit 1
  fi
  echo "ok: $tool installed ${found#"$work/"}"
done

#!/usr/bin/env bash
# Publishes the prompt-me skill from a prompt-me checkout as the next
# 0.0.N of this marketplace: commit and annotated tag, never a push.
#
# Usage: scripts/sync.sh <prompt-me-checkout>
#
# Design: docs/superpowers/specs/2026-10-30-prompt-me-sync-pipeline-design.md
set -euo pipefail

SOURCE_REPO=https://github.com/franks-ai-skills/prompt-me
SOURCE_SKILL=.agents/skills/prompt-me
TARGET=skills/prompt-me
MANIFESTS=".claude-plugin/plugin.json plugin.json"

die() {
  echo "sync: $*" >&2
  exit 1
}

output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'changed=%s\nversion=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}

[ $# -eq 1 ] || die "usage: scripts/sync.sh <prompt-me-checkout>"
src=$(cd "$1" 2> /dev/null && pwd -P) || die "source $1 is not a directory"
cd "$(git rev-parse --show-toplevel)"

sha=$(git -C "$src" rev-parse --verify -q "HEAD^{commit}") || die "source $src has no commit"
subject=$(git -C "$src" log -1 --format=%s "$sha")
src_tree=$(git -C "$src" rev-parse "$sha:$SOURCE_SKILL")

current=$(jq -r .version .claude-plugin/plugin.json)
next=0.0.$((${current##*.} + 1))

if [ "$(git rev-parse -q --verify HEAD:$TARGET || true)" = "$src_tree" ]; then
  echo "no change: still v$current (prompt-me ${sha:0:7})"
  output false "$current"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

(umask 022 && git -C "$src" archive --format=tar "$sha" "$SOURCE_SKILL" | tar -x -f - -C "$tmp")
rm -rf "$TARGET"
mkdir -p "$(dirname "$TARGET")"
mv "$tmp/$SOURCE_SKILL" "$TARGET"
git add -A --force "$TARGET"
[ "$(git write-tree --prefix="$TARGET/")" = "$src_tree" ] || die "staged $TARGET does not match the source tree"

for f in $MANIFESTS; do
  jq --arg v "$next" '.version = $v' "$f" > "$tmp/manifest"
  mv "$tmp/manifest" "$f"
  git add "$f"
done

message="chore(release): v$next from prompt-me ${sha:0:7}

Source: $SOURCE_REPO
Commit: $sha
Subject: $subject"
printf '%s\n' "$message" | git commit -q -F -
printf '%s\n' "$message" | git tag -a "v$next" -F -

echo "published v$next (prompt-me ${sha:0:7})"
output true "$next"

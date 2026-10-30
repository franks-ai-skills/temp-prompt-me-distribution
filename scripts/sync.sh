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
VERSION_RE='^0\.0\.(0|[1-9][0-9]*)$'

die() {
  echo "sync: $*" >&2
  exit 1
}

output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'changed=%s\nversion=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  fi
}

# --- Checks: nothing below writes until the rollback is armed. ---

[ $# -eq 1 ] || die "usage: scripts/sync.sh <prompt-me-checkout>"
src=$(cd "$1" 2> /dev/null && pwd -P) || die "source $1 is not a directory"
top=$(git -C "$src" rev-parse --show-toplevel 2> /dev/null) || top=
if [ -z "$top" ] || [ "$(cd "$top" && pwd -P)" != "$src" ]; then
  die "source $1 is not the root of a git checkout"
fi
cd "$(git rev-parse --show-toplevel)"

# Resolve the source commit once; every later source read uses $sha.
sha=$(git -C "$src" rev-parse --verify -q "HEAD^{commit}") || die "source $1 has no commit"
git -C "$src" cat-file -e "$sha:$SOURCE_SKILL/SKILL.md" 2> /dev/null ||
  die "source has no $SOURCE_SKILL/SKILL.md at ${sha:0:7}"
special=$(git -C "$src" ls-tree -r "$sha" -- "$SOURCE_SKILL" | awk '$1 == "120000" || $1 == "160000" { print $4 }')
[ -z "$special" ] || die "source skill contains a symlink or submodule: $(echo "$special" | head -1)"
subject=$(git -C "$src" log -1 --format=%s "$sha")
src_tree=$(git -C "$src" rev-parse "$sha:$SOURCE_SKILL")

[ -z "$(git status --porcelain)" ] || die "working tree is not clean"
[ -z "$(git status --porcelain --ignored -- "$TARGET")" ] || die "$TARGET contains ignored files"

entries=$(jq '[.plugins[] | select(.name == "prompt-me")] | length' .claude-plugin/marketplace.json)
[ "$entries" = 1 ] || die "marketplace.json must list prompt-me exactly once, found $entries"

current=
for f in $MANIFESTS; do
  v=$(jq -r .version "$f")
  [ -z "$current" ] || [ "$v" = "$current" ] || die "version mismatch: $f has $v, expected $current"
  current=$v
done
[[ $current =~ $VERSION_RE ]] || die "version $current is not of the form 0.0.N"
next=0.0.$((${current##*.} + 1))
if git rev-parse -q --verify "refs/tags/v$next" > /dev/null; then
  die "tag v$next already exists"
fi

if [ "$(git rev-parse -q --verify "HEAD:$TARGET" || true)" = "$src_tree" ]; then
  echo "no change: still v$current (prompt-me ${sha:0:7})"
  output false "$current"
  exit 0
fi

# --- Publish, with rollback from the first write on. ---

orig=$(git rev-parse HEAD)
had_target=0
if git cat-file -e "$orig:$TARGET" 2> /dev/null; then had_target=1; fi
tmp=
new_commit=
tag_created=0
armed=1

# Undoes this run's own changes only: its tag, its commit, the target
# folder and the manifests. Unrelated paths are not touched.
rollback() {
  local status=$?
  set +e
  if [ "$armed" = 1 ]; then
    if [ "$tag_created" = 1 ] && [ "$(git rev-parse -q --verify "v$next^{commit}")" = "$new_commit" ]; then
      git tag -d "v$next" > /dev/null
    fi
    if [ -n "$new_commit" ] && [ "$(git rev-parse HEAD)" = "$new_commit" ]; then
      git reset -q --soft "$orig"
    fi
    rm -rf "$TARGET"
    if [ "$had_target" = 1 ]; then
      git restore -q --source="$orig" --staged --worktree -- "$TARGET"
    else
      git rm -r -q --cached --ignore-unmatch -- "$TARGET"
      rmdir "$(dirname "$TARGET")" 2> /dev/null
    fi
    # shellcheck disable=SC2086 # MANIFESTS is a fixed list without spaces
    git restore -q --source="$orig" --staged --worktree -- $MANIFESTS
    echo "sync: failed; rolled back to ${orig:0:7}" >&2
  fi
  [ -z "$tmp" ] || rm -rf "$tmp"
  exit "$status"
}
trap rollback EXIT

tmp=$(mktemp -d)
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
new_commit=$(git rev-parse HEAD)
printf '%s\n' "$message" | git tag -a "v$next" -F -
tag_created=1
armed=0

echo "published v$next (prompt-me ${sha:0:7})"
output true "$next"

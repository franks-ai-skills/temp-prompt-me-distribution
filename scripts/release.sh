#!/usr/bin/env bash
# Makes sure the GitHub Release v<version> exists and is published,
# creating it from the annotated tag's message when it is missing.
# Running it again for an existing release changes nothing.
#
# Usage: scripts/release.sh <version>   (needs GH_TOKEN for gh)
#
# Design: docs/superpowers/specs/2026-10-30-prompt-me-sync-pipeline-design.md
set -euo pipefail

VERSION_RE='^0\.0\.(0|[1-9][0-9]*)$'

die() {
  echo "release: $*" >&2
  exit 1
}

[ $# -eq 1 ] || die "usage: scripts/release.sh <version>"
version=$1
tag=v$version
[[ $version =~ $VERSION_RE ]] || die "version $version is not of the form 0.0.N"
if [ "$version" = 0.0.0 ]; then
  echo "nothing published yet; no release for 0.0.0"
  exit 0
fi

type=$(git cat-file -t "refs/tags/$tag" 2> /dev/null) || die "tag $tag does not exist"
[ "$type" = tag ] || die "tag $tag is not an annotated tag"
tagged=$(git show "$tag^{commit}:plugin.json" 2> /dev/null | jq -r .version) || tagged=
[ "$tagged" = "$version" ] || die "tag $tag points to a commit with version ${tagged:-none}, not $version"

err=$(mktemp)
trap 'rm -f "$err"' EXIT
if release=$(gh api "repos/{owner}/{repo}/releases/tags/$tag" 2> "$err"); then
  [ "$(jq -r .draft <<< "$release")" = false ] || die "release $tag is a draft"
  echo "release $tag exists"
elif grep -q 'HTTP 404' "$err"; then
  gh release create "$tag" --verify-tag --notes-from-tag --title "$tag"
  echo "created release $tag"
else
  die "could not look up release $tag: $(head -1 "$err")"
fi

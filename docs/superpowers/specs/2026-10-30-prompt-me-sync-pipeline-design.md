# Design: prompt-me sync pipeline

Date: 2026-10-30

## Goal

A manually triggered GitHub Actions workflow publishes the current
`main` of [prompt-me](https://github.com/franks-ai-skills/prompt-me) as a
plugin in this repository. This repository is a plugin marketplace for
Claude Code and Codex. It is temporary: it serves prompt-me until
prompt-me publishes its own releases.

## Decisions

- **Source:** the head of prompt-me's `main`. prompt-me has no tags or
  releases yet, so there is nothing else to take.
- **Versioning belongs to this repository.** Versions start at `0.0.1`,
  and each published change raises only the last number (`0.0.2`,
  `0.0.3`, ...). prompt-me's first own release will be `0.1.0`, so it
  sorts after every version published here.
- **No change, no version.** A run whose copied skill files are
  identical to the published ones makes no commit and no version.
- **Only the skill is shipped.** The pipeline copies
  `.agents/skills/prompt-me/` and nothing else. prompt-me's README,
  `.harness/` and `.harness-forge/` are not distributed.
- **Direct push to `main`.** The workflow commits to `main` and tags the
  commit `v0.0.N`, without a pull request. Triggering the run is the
  decision to publish, and the content was already reviewed in
  prompt-me.
- **The logic lives in a script, not in the workflow.** `scripts/sync.sh`
  does the work, so it runs and is tested locally. The workflow only
  checks out, calls the script and pushes.

Rejected alternatives:

- Taking the latest prompt-me release or tag: none exists.
- Raising the version on every run: users would get updates without
  any change.
- Opening a PR per run: needs a second workflow to tag after the merge,
  and two open PRs could claim the same version.
- Shipping `.harness/` or a full mirror: an installing user has no use
  for build records.
- A workflow in prompt-me that pushes here: needs a cross-repository
  token and puts temporary tooling into prompt-me.
- Deciding "no change" by comparing prompt-me commit SHAs: a commit that
  touches only prompt-me's README would produce a version with
  identical content.

## Repository layout

```
temp-prompt-me-distribution/
├── .claude-plugin/
│   ├── marketplace.json   # marketplace "temp-prompt-me-distribution", plugin "prompt-me", source "./"
│   └── plugin.json        # Claude Code plugin manifest
├── plugin.json            # Agent Plugins schema manifest, read by Codex
├── skills/prompt-me/      # written by the pipeline only
├── scripts/sync.sh
├── tests/sync_test.sh
├── .github/workflows/sync.yml
├── .github/workflows/test.yml
└── README.md, LICENSE, .gitignore, .gitattributes, .editorconfig
```

The layout follows the harness-forge repository, which serves both
Claude Code and Codex from `.claude-plugin/marketplace.json` and a root
`plugin.json`. Codex reads `.claude-plugin/marketplace.json` as a
legacy-compatible marketplace source.

The pipeline changes only `skills/prompt-me/` and the `version` field in
the three manifests. The three `version` fields always hold the same
value. Everything else is maintained by hand.

The manifests are committed once by hand with version `0.0.0` and no
`skills/` folder. `0.0.0` means nothing has been published yet; the
first run produces `0.0.1`.

Installation:

- Claude Code: `/plugin marketplace add franks-ai-skills/temp-prompt-me-distribution`,
  then `/plugin install prompt-me@temp-prompt-me-distribution`.
- Codex: `codex plugin marketplace add franks-ai-skills/temp-prompt-me-distribution`,
  then `codex plugin add prompt-me@temp-prompt-me-distribution`.

The plugin keeps the name `prompt-me`. The marketplace part of the
install ID keeps it apart from the future official plugin.

## `scripts/sync.sh`

Usage: `scripts/sync.sh <path-to-prompt-me-checkout>`, run from the root
of this repository. Requires `bash`, `git` and `jq`.

1. **Checks.** The script stops with a message and changes nothing if
   any of these fails:
   - `<source>/.agents/skills/prompt-me/SKILL.md` exists.
   - The source skill folder contains no symlinks. A symlink could pull
     in files from outside the skill.
   - The working tree of this repository is clean.
   - The three manifests hold the same version, in the form `0.0.N`.
   - The tag `v0.0.N+1` does not exist yet.
2. **Copy.** It deletes `skills/prompt-me/` and copies the source skill
   folder there, so files removed in prompt-me disappear here too.
3. **Detect changes.** It stages `skills/prompt-me/`. If nothing is
   staged, it prints `no change: still v0.0.N (prompt-me <sha7>)` and
   exits with status 0.
4. **Bump.** It sets the `version` field of all three manifests to
   `0.0.N+1` with `jq`.
5. **Commit and tag.** It commits with the subject
   `chore(release): v0.0.N+1 from prompt-me <sha7>`. The body names the
   source repository, the full source SHA and the source commit's
   subject. It then creates the annotated tag `v0.0.N+1` with the same
   source information.
6. **Report.** It never pushes. When `GITHUB_OUTPUT` is set, it writes
   `changed=true` or `changed=false` and `version=0.0.N` there.

## `.github/workflows/sync.yml`

- Trigger: `workflow_dispatch`, no inputs.
- Permissions: `contents: write`, nothing else.
- Concurrency: group `sync`, `cancel-in-progress: false`, so two runs
  never compute the same version.
- Steps:
  1. Check out this repository with full history and tags into `dist/`.
  2. Check out `franks-ai-skills/prompt-me` at `main` into `source/`,
     with `persist-credentials: false`. prompt-me is public, so no token
     is needed.
  3. Set the git identity to `github-actions[bot]`.
  4. Run `dist/scripts/sync.sh source`.
  5. If `changed=true`, run
     `git push --atomic origin HEAD:main refs/tags/v0.0.N`. The commit
     and the tag land together or not at all.
  6. Write the new version and source SHA, or "no change", to the job
     summary.
- Third-party actions are pinned to commit SHAs, with the version in a
  comment.

Commits from the workflow are authored by `github-actions[bot]` and
carry no `Assisted-by` trailer, because no model writes them.

## Failure behaviour

- A failed check in `sync.sh`: the run fails with the reason, nothing is
  pushed.
- `main` of this repository moved during the run: the atomic push is
  rejected and the run fails. Nothing is published; a re-run starts from
  the new state.
- Branch protection that requires PRs on `main` would reject the push.
  The README states this.

## Testing

`tests/sync_test.sh` is plain bash. It builds a throwaway source
repository and distribution repository in a temporary folder and covers:

- The first run produces `0.0.1` in all three manifests, a commit and
  the tag `v0.0.1`.
- A second run without source changes makes no commit and no tag.
- A changed source file produces `0.0.2`.
- A file deleted in the source disappears from `skills/prompt-me/`.
- A symlink in the source, a dirty working tree, mismatched manifest
  versions and an existing next tag each make the script fail without
  changing the repository.

`.github/workflows/test.yml` runs `tests/sync_test.sh` and `shellcheck`
on every push and pull request.

Manual end-to-end check after the merge:

1. Trigger the sync workflow once; expect `v0.0.1`.
2. Add the marketplace and install `prompt-me` in Claude Code and in
   Codex.
3. Trigger the workflow again; expect "no change".

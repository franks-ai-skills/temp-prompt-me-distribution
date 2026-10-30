# prompt-me Sync Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A manually triggered workflow publishes prompt-me's `main` as the `prompt-me` plugin in this marketplace, versioned `0.0.N`.

**Architecture:** `scripts/sync.sh` copies the skill, detects changes, bumps the version in three manifests, commits and tags locally. `.github/workflows/sync.yml` checks out both repositories, runs the script and pushes commit and tag atomically. `tests/sync_test.sh` exercises the script against throwaway git repositories.

**Tech Stack:** bash, git, jq, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-30-prompt-me-sync-pipeline-design.md`

## Global Constraints

- Branch: `feature/prompt-me-sync-pipeline`, created from `docs/prompt-me-sync-design`, so spec, plan and implementation go into one PR.
- Marketplace name `temp-prompt-me-distribution`; plugin name `prompt-me`.
- Source skill path `.agents/skills/prompt-me/`; target path `skills/prompt-me/`.
- Manifests: `.claude-plugin/marketplace.json` (version at `.plugins[] | select(.name == "prompt-me") | .version`), `.claude-plugin/plugin.json` and `plugin.json` (version at `.version`).
- Versions are `0.0.N`; committed baseline `0.0.0`; first run produces `0.0.1`; only N increases, numerically (`0.0.9` → `0.0.10`).
- Commit subject `chore(release): v0.0.N from prompt-me <sha7>`; annotated tag `v0.0.N`.
- `GITHUB_OUTPUT` keys: `changed` (`true`/`false`) and `version` (`0.0.N`, the current version when nothing changed).
- No-change message: `no change: still v0.0.N (prompt-me <sha7>)`, exit status 0.
- Runtime dependencies: `bash`, `git`, `jq` only. The script runs under macOS `/bin/bash` 3.2: no `mapfile`, no associative arrays, no `${var,,}`.
- Manifests are formatted as `jq` writes them (2-space indent, trailing newline), so a bump changes only `version` lines.
- Workflow permissions `contents: write` only; third-party actions pinned to a commit SHA with the version in a comment.
- Workflow commits carry no `Assisted-by` trailer; commits made while implementing this plan end with `Assisted-by: Claude Opus 5.5 (code generation)`.

## Review Focus

- A source skill with hidden files (for example `references/.gitkeep`) — expected: copied like any other file. Test in Task 2.
- Untracked files in the distribution repository — expected: they count as a dirty tree and the script refuses. Test in Task 3.
- A relative source path, and the script run from a subdirectory of the distribution repository — expected: works the same as from the root. Test in Task 2.
- A source path that is not a git checkout — expected: fails before any change, because the source SHA is unknown. Test in Task 3.
- Version `0.0.9` — expected: bumps to `0.0.10`, not `0.0.91` or a string error. Test in Task 2.

---

### Task 1: Manifests at 0.0.0 and README

**Files:**
- Create: `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`, `plugin.json`
- Modify: `README.md`

**Interfaces:**
- Produces: the three manifests at version `0.0.0`, which `tests/sync_test.sh` copies into its throwaway distribution repository.

- [ ] **Step 1: Create the branch**

Run: `git switch -c feature/prompt-me-sync-pipeline` (from `docs/prompt-me-sync-design`).

- [ ] **Step 2: Write `.claude-plugin/plugin.json`**

Shape of harness-forge's `.claude-plugin/plugin.json` with these values: `name` `prompt-me`; `version` `0.0.0`; `description` `Drafts a well-defined prompt from your request instead of carrying it out. Temporary builds from prompt-me's main branch.`; `license` `AGPL-3.0-only`; `repository` `https://github.com/franks-ai-skills/prompt-me`; `homepage` `https://github.com/franks-ai-skills/temp-prompt-me-distribution`; `author` `{ "name": "franks-ai-skills", "url": "https://github.com/franks-ai-skills" }`; `keywords` `["claude-code", "codex", "skills", "prompt"]`.

- [ ] **Step 3: Write `plugin.json`**

The same object with `"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"` as its first key.

- [ ] **Step 4: Write `.claude-plugin/marketplace.json`**

`name` `temp-prompt-me-distribution`; `description` `Temporary marketplace for prompt-me builds from its main branch`; `owner` as `author` above; one plugin entry: `name` `prompt-me`, `source` `./`, the description from Step 2, `version` `0.0.0`, `category` `development`, `policy` `{ "installation": "AVAILABLE", "authentication": "ON_INSTALL" }`.

- [ ] **Step 5: Normalize and check the manifests**

Run each file through `jq . f > f.tmp && mv f.tmp f`, then:
`jq -r '.version' plugin.json .claude-plugin/plugin.json; jq -r '.plugins[] | select(.name == "prompt-me") | .version' .claude-plugin/marketplace.json`
Expected: `0.0.0` three times.

- [ ] **Step 6: Extend `README.md`**

Add sections: "Install" (the Claude Code and Codex commands from the spec), "Versions" (`0.0.N` builds from prompt-me's `main`; prompt-me's own releases start at `0.1.0`), "Publishing" (run the "Sync prompt-me" workflow by hand; a run without skill changes publishes nothing; branch protection that requires PRs on `main` rejects the workflow's push). Keep the license section.

- [ ] **Step 7: Commit**

`git add .claude-plugin plugin.json README.md && git commit` with subject `feat: add marketplace and plugin manifests for prompt-me`.

### Task 2: `sync.sh` publishing path

**Files:**
- Create: `scripts/sync.sh` (executable), `tests/sync_test.sh` (executable)

**Interfaces:**
- Consumes: the manifests from Task 1.
- Produces: `scripts/sync.sh <source-checkout>`, run with the distribution repository as working directory (any subdirectory). Exit 0 on publish or no change, non-zero with a message on stderr on refusal. Writes `changed=` and `version=` to `$GITHUB_OUTPUT` when set.
- Produces: in `tests/sync_test.sh`, helpers that Task 3 reuses: `setup` (fresh temp dir with `$SRC` and `$DIST` repos, both committed and clean, `$DIST` holding copies of the three real manifests), `run_sync [args…]` (runs the real `scripts/sync.sh` with cwd `$DIST`, captures `$OUT`, `$ERR`, `$STATUS`), `assert_eq <expected> <actual> <label>`, `dist_versions` (prints the three manifest versions space-separated), `head_sha` / `tag_count` for `$DIST`. Test functions are named `test_*`; the runner calls each after a fresh `setup` and exits non-zero if any assertion failed. Git identity comes from `GIT_AUTHOR_*`/`GIT_COMMITTER_*` exported in the test script.

`$SRC` contains `.agents/skills/prompt-me/SKILL.md`, `.agents/skills/prompt-me/references/requirements.md`, `.agents/skills/prompt-me/references/.gitkeep` and a `README.md` outside the skill.

- [ ] **Step 1: Write the failing tests**

- `test_first_run_publishes_0_0_1`: `dist_versions` is `0.0.1 0.0.1 0.0.1`; `skills/prompt-me/SKILL.md` matches the source; `git -C $DIST tag -l` is `v0.0.1`; HEAD subject is `chore(release): v0.0.1 from prompt-me <sha7 of $SRC>`; HEAD body and `git cat-file -p v0.0.1` contain the full source SHA; `$STATUS` 0; `git status --porcelain` empty.
- `test_hidden_files_are_copied`: after the first run `skills/prompt-me/references/.gitkeep` exists.
- `test_rerun_without_change_publishes_nothing`: second run leaves `head_sha` and `tag_count` unchanged, `$STATUS` 0, `$OUT` contains `no change: still v0.0.1 (prompt-me <sha7>)`.
- `test_source_change_outside_skill_publishes_nothing`: commit a change to `$SRC/README.md` after the first run; second run publishes nothing.
- `test_changed_file_publishes_0_0_2`: edit and commit `SKILL.md` in `$SRC`; second run gives `0.0.2 0.0.2 0.0.2` and tag `v0.0.2`.
- `test_deleted_file_disappears`: `git rm` `references/requirements.md` in `$SRC`; after the second run the file is absent in `$DIST` and the version is `0.0.2`.
- `test_bump_is_numeric`: set all three manifests in `$DIST` to `0.0.9` and commit; run gives `0.0.10`.
- `test_github_output`: with `GITHUB_OUTPUT` pointing to a temp file, the first run writes `changed=true` and `version=0.0.1`; the rerun writes `changed=false` and `version=0.0.1`.
- `test_relative_source_and_subdirectory`: run from `$DIST/skills` (create it if missing) with the source given as a path relative to that directory; it publishes `0.0.1`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash tests/sync_test.sh`
Expected: every test FAILs because `scripts/sync.sh` does not exist; exit status non-zero.

- [ ] **Step 3: Implement `scripts/sync.sh`**

`#!/usr/bin/env bash`, `set -euo pipefail`. Resolve the source to an absolute path before `cd "$(git rev-parse --show-toplevel)"`. Read the source SHA with `git -C "$src" rev-parse HEAD` and its subject with `git log -1 --format=%s`. Replace the target with `rm -rf skills/prompt-me && mkdir -p skills/prompt-me && cp -R "$src/.agents/skills/prompt-me/." skills/prompt-me/`. Detect changes with `git add -A skills/prompt-me` and `git diff --cached --quiet`. Write each manifest through `jq` to a temp file, then `mv`. Commit with `git commit -q -F -`, tag with `git tag -a "v$next" -F -`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/sync_test.sh`
Expected: all tests PASS; exit status 0.

- [ ] **Step 5: Commit**

`git add scripts/sync.sh tests/sync_test.sh && git commit` with subject `feat: add sync script that publishes prompt-me as 0.0.N`.

### Task 3: `sync.sh` refusals

**Files:**
- Modify: `scripts/sync.sh`, `tests/sync_test.sh`

**Interfaces:**
- Consumes: the helpers from Task 2.
- Produces: refusals exit with status 1 and a one-line reason on stderr; the distribution repository's HEAD, tags, index and working tree stay as they were.

Every test below also asserts `head_sha`, `tag_count` and `git status --porcelain` are unchanged and `$STATUS` is non-zero.

- [ ] **Step 1: Write the failing tests**

- `test_refuses_missing_skill`: `git rm` `SKILL.md` in `$SRC`; `$ERR` mentions `SKILL.md`.
- `test_refuses_symlink_in_source`: add `references/link -> ../../../README.md` in `$SRC`; `$ERR` mentions `symlink`.
- `test_refuses_dirty_tree`: modify `README.md` in `$DIST` without committing; `$ERR` mentions `clean`.
- `test_refuses_untracked_file`: create an untracked `notes.txt` in `$DIST`; the porcelain check expects exactly `?? notes.txt`.
- `test_refuses_mismatched_versions`: set `plugin.json` to `0.0.3` and commit; `$ERR` mentions `version`.
- `test_refuses_non_0_0_n_version`: set all three to `0.1.0` and commit; `$ERR` mentions `0.0.N`.
- `test_refuses_existing_next_tag`: `git tag v0.0.1` in `$DIST`; `tag_count` before and after is 1.
- `test_refuses_source_not_a_git_checkout`: copy `$SRC` without `.git` to a new temp dir and use it as the source.
- `test_refuses_missing_argument`: no argument; `$ERR` contains `usage: scripts/sync.sh <prompt-me-checkout>`.

- [ ] **Step 2: Run the tests to verify the new ones fail**

Run: `bash tests/sync_test.sh`
Expected: the Task 2 tests PASS; the new tests FAIL.

- [ ] **Step 3: Add the checks to `scripts/sync.sh`**

All checks run before the first write, in the order of the spec's step 1. Dirty tree: `git status --porcelain` non-empty. Symlinks: `find "$skill" -type l` non-empty. Existing tag: `git rev-parse -q --verify "refs/tags/v$next"`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bash tests/sync_test.sh` — expected: all PASS.
Run: `/bin/bash tests/sync_test.sh` — expected: all PASS under macOS bash 3.2 (`run_sync` calls the script as `"$BASH" scripts/sync.sh`, so the script runs under the same bash as the tests).
Run: `shellcheck scripts/sync.sh tests/sync_test.sh` — expected: no output, exit 0.

- [ ] **Step 5: Commit**

Subject `feat: refuse to sync on invalid source or repository state`.

### Task 4: Test workflow

**Files:**
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: `tests/sync_test.sh`, `scripts/sync.sh`.

- [ ] **Step 1: Look up the pinned SHA of `actions/checkout`**

Run: `gh api repos/actions/checkout/releases/latest --jq .tag_name`, then `gh api repos/actions/checkout/commits/<tag> --jq .sha`. Task 5 uses the same pin.

- [ ] **Step 2: Write `.github/workflows/test.yml`**

Name `Test`; `on: [push, pull_request]`; `permissions: contents: read`; one job on `ubuntu-latest`: checkout (pinned), `shellcheck scripts/sync.sh tests/sync_test.sh`, `bash tests/sync_test.sh`.

- [ ] **Step 3: Lint**

Run: `actionlint .github/workflows/test.yml` if `actionlint` is installed, else `ruby -ryaml -e 'YAML.load_file(ARGV[0])' .github/workflows/test.yml`, and note which one ran.
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

Subject `ci: run sync tests and shellcheck on push and pull request`.

### Task 5: Sync workflow

**Files:**
- Create: `.github/workflows/sync.yml`

**Interfaces:**
- Consumes: `scripts/sync.sh` and its `GITHUB_OUTPUT` keys; the checkout pin from Task 4.

- [ ] **Step 1: Write `.github/workflows/sync.yml`**

Name `Sync prompt-me`; `on: workflow_dispatch`; `permissions: contents: write`; `concurrency: { group: sync, cancel-in-progress: false }`. One job on `ubuntu-latest`:
1. Checkout this repository, `ref: main`, `fetch-depth: 0`, `fetch-tags: true`, `path: dist`.
2. Checkout `franks-ai-skills/prompt-me`, `ref: main`, `path: source`, `persist-credentials: false`.
3. In `dist`: `git config user.name "github-actions[bot]"` and `git config user.email "41898283+github-actions[bot]@users.noreply.github.com"`.
4. Step `id: sync`, `working-directory: dist`: `scripts/sync.sh ../source`.
5. `if: steps.sync.outputs.changed == 'true'`, `working-directory: dist`: `git push --atomic origin HEAD:main "refs/tags/v${{ steps.sync.outputs.version }}"`.
6. `if: always()`: append to `$GITHUB_STEP_SUMMARY` — `Published v<version> from prompt-me <sha7>` when changed, `No change: still v<version>` otherwise. The source SHA comes from `git -C source rev-parse --short HEAD`.

- [ ] **Step 2: Lint**

As in Task 4, Step 3, for `.github/workflows/sync.yml`.

- [ ] **Step 3: Commit**

Subject `ci: add manual workflow that publishes prompt-me`.

### Task 6: Pull request and end-to-end check

- [ ] **Step 1: Push and open the PR**

Push `feature/prompt-me-sync-pipeline` and open a PR to `main` with title `feat: publish prompt-me builds through a manual sync workflow` and a description per git-flow (Summary, Changes, Decisions, Tests, trailers). Report the link.
Expected: the `Test` workflow runs on the PR and passes.

- [ ] **Step 2: Merge**

Only after the user approves the merge. Squash-merge.

- [ ] **Step 3: End-to-end check**

1. `gh workflow run sync.yml -R franks-ai-skills/temp-prompt-me-distribution`, wait for it; expect tag `v0.0.1` on `main` and the summary `Published v0.0.1 …`.
2. Ask the user to add the marketplace and install `prompt-me` in Claude Code and in Codex; expect the plugin at `0.0.1` with the `prompt-me` skill.
3. Run the workflow again; expect `No change: still v0.0.1`, and no new commit or tag.

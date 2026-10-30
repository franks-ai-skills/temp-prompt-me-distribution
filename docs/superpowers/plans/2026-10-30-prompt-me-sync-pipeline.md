# prompt-me Sync Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One manual workflow run publishes prompt-me's `main` as release `v0.0.N` of the `prompt-me` plugin in this marketplace.

**Architecture:** `scripts/sync.sh` publishes the committed source skill tree into `skills/prompt-me/`, bumps the version, commits and tags locally, with rollback on failure. `scripts/release.sh` makes sure the GitHub Release for a version exists. `.github/workflows/sync.yml` checks out both repositories, runs the tests, calls the scripts and pushes atomically. Tests run the scripts against throwaway git repositories; `release.sh` is tested against a stub `gh`.

**Tech Stack:** bash, git, jq, gh, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-30-prompt-me-sync-pipeline-design.md`

## Global Constraints

- Branch: `feature/prompt-me-sync-pipeline`, created from `docs/prompt-me-sync-design`, so spec, plan and implementation go into one PR.
- Marketplace name `temp-prompt-me-distribution`; plugin name `prompt-me`.
- Source skill path `.agents/skills/prompt-me/`; target path `skills/prompt-me/`.
- Version fields: `.version` in `.claude-plugin/plugin.json` and in `plugin.json`. The marketplace entry has no `version`.
- Versions are `0.0.N`; committed baseline `0.0.0`; first run produces `0.0.1`; only N increases, numerically (`0.0.9` → `0.0.10`).
- Commit subject `chore(release): v0.0.N from prompt-me <sha7>`; body and annotated tag message: source repository URL, full source SHA, source subject.
- `GITHUB_OUTPUT` keys: `changed` (`true`/`false`) and `version` (`0.0.N`, the current version when nothing changed).
- No-change message: `no change: still v0.0.N (prompt-me <sha7>)`, exit status 0.
- Refusals exit with status 1 and one line on stderr starting `sync: ` or `release: `.
- Scripts run under macOS `/bin/bash` 3.2: no `mapfile`, no associative arrays, no `${var,,}`. Tests run the scripts as `"$BASH" <script>`, so `/bin/bash tests/…` exercises 3.2.
- Manifests are formatted as `jq` writes them (2-space indent, trailing newline), so a bump changes only `version` lines.
- Workflow permissions `contents: write` only; third-party actions pinned to a commit SHA with the version in a comment; `${{ }}` values reach `run:` only through `env`.
- Workflow commits carry no `Assisted-by` trailer; commits made while implementing this plan end with `Assisted-by: Claude Opus 5.5 (code generation)`.

## Review Focus

- The source checkout moves between reads (new commit, branch switch) — expected: every source read uses the SHA resolved at the start. Pinned by asserting the commit body's SHA equals the tree that was published (Task 2).
- A user runs `sync.sh` locally with Finder's `.DS_Store` inside `skills/prompt-me/` — expected: refused as an ignored file, not published and not deleted. Test in Task 3.
- `gh` succeeds for the release lookup but returns a draft — expected: failure, not a silent "exists". Test in Task 4.
- The push succeeded and the release step failed; the next run finds no change — expected: that run creates the missing release. Test in Task 4 (`release.sh` on an existing tag with HTTP 404).
- The plugin layout loads in Claude Code but not in Codex, or the reverse — expected: caught before the merge. Task 6.

---

### Task 1: Manifests, attributes and README

**Files:**
- Create: `.claude-plugin/marketplace.json`, `.claude-plugin/plugin.json`, `plugin.json`
- Modify: `.gitattributes`, `README.md`

**Interfaces:**
- Produces: the manifests at `0.0.0` and `.gitattributes`, which the test fixtures copy into their throwaway distribution repository.

- [ ] **Step 1: Create the branch**

Run: `git switch -c feature/prompt-me-sync-pipeline` (from `docs/prompt-me-sync-design`).

- [ ] **Step 2: Write `.claude-plugin/plugin.json`**

`name` `prompt-me`; `version` `0.0.0`; `description` `Drafts a well-defined prompt from your request instead of carrying it out. Temporary builds from prompt-me's main branch.`; `license` `AGPL-3.0-only`; `repository` `https://github.com/franks-ai-skills/prompt-me`; `homepage` `https://github.com/franks-ai-skills/temp-prompt-me-distribution`; `author` `{ "name": "franks-ai-skills", "url": "https://github.com/franks-ai-skills" }`; `keywords` `["claude-code", "codex", "skills", "prompt"]`.

- [ ] **Step 3: Write `plugin.json`**

The same object with `"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"` as its first key.

- [ ] **Step 4: Write `.claude-plugin/marketplace.json`**

`name` `temp-prompt-me-distribution`; `description` `Temporary marketplace for prompt-me builds from its main branch`; `owner` as `author` above; one plugin entry without `version`: `name` `prompt-me`, `source` `./`, the description from Step 2, `category` `development`, `policy` `{ "installation": "AVAILABLE", "authentication": "ON_INSTALL" }`.

- [ ] **Step 5: Normalize and check**

Run each manifest through `jq . f > f.tmp && mv f.tmp f`, then:
`jq -r .version plugin.json .claude-plugin/plugin.json; jq '[.plugins[] | select(.name == "prompt-me")] | length, (.[0] | has("version"))' .claude-plugin/marketplace.json`
Expected: `0.0.0`, `0.0.0`, `1`, `false`. If `claude plugin validate .` is available, run it; expected: no errors.

- [ ] **Step 6: Add `skills/prompt-me/** -text` to `.gitattributes`**, after the existing line, with a comment that the published skill must stay byte-identical to the source.

- [ ] **Step 7: Extend `README.md`**

Sections: "Install" and "Update" (commands from the spec), "Versions" (`0.0.N` builds from prompt-me's `main`; prompt-me's own releases start at `0.1.0`), "Publishing" (run the "Sync prompt-me" workflow; a run without skill changes publishes nothing; branch or tag rulesets that require PRs, status checks or signed commits reject the workflow's push). Keep the license section.

- [ ] **Step 8: Commit** — subject `feat: add marketplace and plugin manifests for prompt-me`.

### Task 2: `sync.sh` publishing path

**Files:**
- Create: `scripts/sync.sh` (executable), `tests/lib.sh`, `tests/sync_test.sh` (executable)

**Interfaces:**
- Consumes: the Task 1 manifests and `.gitattributes`.
- Produces: `scripts/sync.sh <source-checkout>` as specified in the spec, section `scripts/sync.sh`.
- Produces in `tests/lib.sh` (sourced by all test scripts): `assert_eq <expected> <actual> <label>`, `assert_contains <haystack> <needle> <label>`, `run_tests` (calls every `test_*` function after a fresh `setup`, prints PASS/FAIL per test, exits non-zero on any failure), exported `GIT_AUTHOR_*`/`GIT_COMMITTER_*`, `REPO_ROOT`.
- Produces in `tests/sync_test.sh`: `setup` (fresh temp dir; `$SRC` repo with `.agents/skills/prompt-me/SKILL.md`, `references/requirements.md`, `references/.gitkeep` and a root `README.md`; `$DIST` repo with copies of the three manifests, `.gitattributes` and `.gitignore`; both committed and clean), `run_sync [args…]` (cwd `$DIST`, runs `"$BASH" "$REPO_ROOT/scripts/sync.sh"`, sets `$OUT`, `$ERR`, `$STATUS`), `dist_versions` (prints both versions space-separated), `head_sha`, `tag_count`, `state` (prints HEAD, tags and `git status --porcelain --ignored` of `$DIST`, for before/after comparison).

- [ ] **Step 1: Write the failing tests**

- `test_first_run_publishes_0_0_1`: `dist_versions` is `0.0.1 0.0.1`; `git -C $DIST rev-parse HEAD:skills/prompt-me` equals `git -C $SRC rev-parse HEAD:.agents/skills/prompt-me`; tag list is `v0.0.1` and `git cat-file -t v0.0.1` is `tag`; HEAD subject is `chore(release): v0.0.1 from prompt-me <sha7>`; HEAD body and tag message contain the full source SHA and the source subject `feat: distinctive source subject`; `git status --porcelain` empty.
- `test_rerun_without_change_writes_nothing`: second run: `state` unchanged, `$STATUS` 0, `$OUT` contains `no change: still v0.0.1 (prompt-me <sha7>)`.
- `test_source_change_outside_skill_writes_nothing`: change and commit `$SRC/README.md` after the first run; second run: `state` unchanged.
- `test_changed_file_publishes_0_0_2` and `test_deleted_file_disappears`: as named; versions `0.0.2 0.0.2`, tag `v0.0.2`.
- `test_special_files_published_unchanged`: the source skill also has an executable `scripts/run.sh`, a `debug.log` (matched by the destination `.gitignore`) and a CRLF `crlf.md`; after the first run the tree IDs match, `git ls-files -s skills/prompt-me/scripts/run.sh` shows `100755`; a rerun reports no change.
- `test_uncommitted_source_files_not_published`: modify `SKILL.md` and add `extra.md` in `$SRC` without committing; the published tree equals the committed source tree.
- `test_bump_is_numeric`: both manifests at `0.0.9` (committed); run gives `0.0.10`.
- `test_github_output`: first run writes `changed=true` and `version=0.0.1`; rerun writes `changed=false` and `version=0.0.1`.
- `test_relative_source_and_subdirectory`: run from `$DIST/.claude-plugin` with the source as a relative path; publishes `0.0.1`.

- [ ] **Step 2: Run to verify they fail** — `bash tests/sync_test.sh`; expected: all FAIL, exit non-zero.

- [ ] **Step 3: Implement `scripts/sync.sh`**

`#!/usr/bin/env bash`, `set -euo pipefail`. Resolve the source to an absolute path, then `cd "$(git rev-parse --show-toplevel)"`. Resolve `sha=$(git -C "$src" rev-parse HEAD)` once; use `$sha` for `rev-parse`, `ls-tree`, `archive` and `log -1 --format=%s`. Compare tree IDs for the no-change exit. Extract with `(umask 022; git -C "$src" archive --format=tar "$sha" .agents/skills/prompt-me | tar -x -f - -C "$tmp")`. Write manifests through `jq` to a temp file, then `mv`. Commit with `git commit -q -F -`, tag with `git tag -a "v$next" -F -`. Checks and rollback come in Task 3; only the argument and path handling needed here.

- [ ] **Step 4: Run to verify they pass** — `bash tests/sync_test.sh` and `/bin/bash tests/sync_test.sh`; expected: all PASS.

- [ ] **Step 5: Commit** — subject `feat: add sync script that publishes prompt-me as 0.0.N`.

### Task 3: `sync.sh` refusals and rollback

**Files:**
- Modify: `scripts/sync.sh`, `tests/sync_test.sh`

**Interfaces:**
- Consumes: the Task 2 helpers.

Each refusal test asserts `$STATUS` 1, `$ERR` starting with `sync: ` and containing the given word, and `state` unchanged.

- [ ] **Step 1: Write the failing tests**

- `test_refuses_missing_argument` (`usage: scripts/sync.sh <prompt-me-checkout>`).
- `test_refuses_source_not_checkout_root`: source `$SRC/.agents` (`root`); and a copy of `$SRC` without `.git` inside another git repo (`root`).
- `test_refuses_missing_skill`: `git rm SKILL.md` in `$SRC` (`SKILL.md`).
- `test_refuses_symlink_in_source`: committed `references/link -> ../../../../README.md` (`symlink`).
- `test_refuses_symlinked_ancestor`: `.agents/skills` committed as a symlink to a folder holding the skill (`SKILL.md`).
- `test_refuses_dirty_tree`: modified tracked file in `$DIST` (`clean`); `test_refuses_untracked_file`: untracked `notes.txt` (`clean`).
- `test_refuses_ignored_file_in_target`: after a first run, create `skills/prompt-me/.DS_Store` (`ignored`); the file still exists afterwards.
- `test_refuses_duplicate_marketplace_entry` (`marketplace`).
- `test_refuses_mismatched_versions`: `plugin.json` at `0.0.3` (`version`); `test_refuses_non_0_0_n_version`: both at `0.1.0` (`0.0.N`).
- `test_refuses_existing_next_tag`: `git tag v0.0.1` in `$DIST` (`v0.0.1`).
- `test_rollback_on_commit_failure`: source with `debug.log`; `$DIST/.git/hooks/pre-commit` exits 1; `$STATUS` non-zero; `state` unchanged, including no `skills/` folder and no ignored files left.
- `test_rollback_keeps_previous_release`: after a successful first run, change the source, add the failing hook, run again; `state` unchanged and `skills/prompt-me` still equals the `v0.0.1` tree.

- [ ] **Step 2: Run to verify the new tests fail** — `bash tests/sync_test.sh`; expected: Task 2 tests PASS, new tests FAIL.

- [ ] **Step 3: Add checks and rollback to `scripts/sync.sh`**

Checks run in the spec's order, before the first write. Checkout root: `git -C "$src" rev-parse --show-toplevel` equals the resolved path. Modes: `git -C "$src" ls-tree -r "$sha" -- .agents/skills/prompt-me` with mode `120000` or `160000`. Target cleanliness: `git status --porcelain` empty and `git status --porcelain --ignored -- skills/prompt-me` empty. Rollback: an `EXIT` trap armed just before the first write and disarmed after the tag; it implements the spec's "Rollback" paragraph and ends with `exit "$status"`.

- [ ] **Step 4: Verify** — `bash tests/sync_test.sh`, `/bin/bash tests/sync_test.sh`: all PASS. `shellcheck scripts/sync.sh tests/*.sh`: no output.

- [ ] **Step 5: Commit** — subject `feat: refuse invalid sync input and roll back failed syncs`.

### Task 4: `release.sh`

**Files:**
- Create: `scripts/release.sh` (executable), `tests/release_test.sh` (executable)

**Interfaces:**
- Consumes: `tests/lib.sh`; tags as created by `sync.sh`.
- Produces: `scripts/release.sh <version>` as in the spec, section `scripts/release.sh`. It calls only `gh api repos/{owner}/{repo}/releases/tags/v<version>` for the lookup and `gh release create "v<version>" --verify-tag --notes-from-tag --title "v<version>"` for creation, so the stub has two commands to fake.
- Test fixture: a repo with an annotated tag `v0.0.1` on a commit whose `plugin.json` has `0.0.1`; a stub `gh` first on `PATH` whose behaviour comes from `STUB_GH_LOOKUP` (`published` → prints `{"draft":false}`, `draft` → `{"draft":true}`, `404` → stderr `HTTP 404` and exit 1, `error` → stderr `HTTP 401` and exit 1) and which appends each call to `$STUB_GH_LOG`.

- [ ] **Step 1: Write the failing tests**

`test_zero_version_does_nothing` (no `gh` calls), `test_refuses_invalid_version` (`1.0`), `test_refuses_missing_tag`, `test_refuses_lightweight_tag`, `test_refuses_tag_with_other_version`, `test_accepts_published_release` (no `create` call), `test_refuses_draft`, `test_creates_release_on_404` (one `create` call with the arguments above), `test_fails_on_api_error` (no `create` call). Refusals assert status 1 and `$ERR` starting with `release: `.

- [ ] **Step 2: Run to verify they fail** — `bash tests/release_test.sh`.

- [ ] **Step 3: Implement `scripts/release.sh`.** Read the lookup's stderr to tell `HTTP 404` from other failures; read `.draft` with `jq`.

- [ ] **Step 4: Verify** — `bash tests/release_test.sh`, `/bin/bash tests/release_test.sh`: all PASS; `shellcheck scripts/release.sh tests/release_test.sh`: no output.

- [ ] **Step 5: Commit** — subject `feat: add release script that creates the GitHub Release for a tag`.

### Task 5: Workflows

**Files:**
- Create: `.github/workflows/test.yml`, `.github/workflows/sync.yml`

**Interfaces:**
- Consumes: both scripts, their `GITHUB_OUTPUT` keys, both test scripts.

- [ ] **Step 1: Look up the pinned SHA of `actions/checkout`**

`gh api repos/actions/checkout/releases/latest --jq .tag_name`, then `gh api repos/actions/checkout/commits/<tag> --jq .sha`.

- [ ] **Step 2: Write `test.yml`**

Name `Test`; `on: [push, pull_request]`; `permissions: contents: read`; one job on `ubuntu-latest`: checkout (pinned, `persist-credentials: false`), `shellcheck scripts/*.sh tests/*.sh`, `bash tests/sync_test.sh`, `bash tests/release_test.sh`.

- [ ] **Step 3: Write `sync.yml`**

Name `Sync prompt-me`; the trigger, permissions, concurrency and steps 1–8 of the spec, section `.github/workflows/sync.yml`. Step ids `sync`, `push`, `release`. Push and release steps get `VERSION: ${{ steps.sync.outputs.version }}` through `env` and check it against `^0\.0\.[0-9]+$` first. The release step has `GH_TOKEN: ${{ github.token }}` and `if: steps.sync.outcome == 'success' && (steps.sync.outputs.changed != 'true' || steps.push.outcome == 'success')`. The summary step has `if: always()` and reads the outcomes through `env`; it derives the source SHA from `git -C source rev-parse --short HEAD` only when the source checkout succeeded.

- [ ] **Step 4: Lint** — `actionlint .github/workflows/*.yml` if installed, else `ruby -ryaml -e 'ARGV.each { |f| YAML.load_file(f) }' .github/workflows/*.yml`; note which ran. Expected: no output.

- [ ] **Step 5: Commit** — subject `ci: add test workflow and manual sync workflow`.

### Task 6: Local install smoke test

**Files:**
- Create: `tests/smoke_install.sh` (executable)

- [ ] **Step 1: Write `tests/smoke_install.sh`**

Clones the current branch of this repository (`git clone -q "$REPO_ROOT"`) into a temp dir and runs `sync.sh` there against a local prompt-me checkout given as argument, so the clone is at `0.0.1`. Then with `CLAUDE_CONFIG_DIR` and `CODEX_HOME` set to fresh temp dirs: `claude plugin validate <copy>`, `claude plugin marketplace add <copy>`, `claude plugin install prompt-me@temp-prompt-me-distribution`; `codex plugin marketplace add <copy>`, `codex plugin add prompt-me@temp-prompt-me-distribution`. Then it checks that `find` finds `skills/prompt-me/SKILL.md` under each config dir. It never touches the real config dirs; it removes the temp dirs on exit.

- [ ] **Step 2: Run it** — `bash tests/smoke_install.sh ../prompt-me`. Expected: both installs succeed and both `SKILL.md` checks pass. If one fails: fix the layout (for example add `.agents/plugins/marketplace.json` or an object `source`), update the spec's layout section, rerun Tasks 1–3 tests, and record the fix in the PR's Decisions. If a CLI refuses because the throwaway config dir is not signed in, stop and report it instead of using the real config dir.

- [ ] **Step 3: Commit** — subject `test: add local install smoke test for Claude Code and Codex`.

### Task 7: Pull request and end-to-end check

- [ ] **Step 1: Push and open the PR** to `main`, title `feat: publish prompt-me releases through a manual sync workflow`, description per git-flow. Report the link. Expected: `Test` passes on the PR.
- [ ] **Step 2: Merge** — squash-merge once `Test` is green, as the user decided for this one-time PR (ask if no such decision was given).
- [ ] **Step 3: First release** — `gh workflow run sync.yml -R franks-ai-skills/temp-prompt-me-distribution`; wait; expect tag and GitHub Release `v0.0.1` and the summary `Published v0.0.1 …`.
- [ ] **Step 4: Ask the user** to add the marketplace and install `prompt-me` in Claude Code and Codex and confirm the skill appears in a new session.
- [ ] **Step 5: No-change run** — trigger again; expect `No change: still v0.0.1`, no new commit, tag or release.
- [ ] **Step 6: Record the open check** — the `0.0.1 → 0.0.2` update in both clients happens after the next skill change in prompt-me; note it in the PR or the final report.

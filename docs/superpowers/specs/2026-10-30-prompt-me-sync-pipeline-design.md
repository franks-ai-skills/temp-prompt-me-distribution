# Design: prompt-me sync pipeline

Date: 2026-10-30

## Goal

One manual run of a GitHub Actions workflow publishes the current
`main` of [prompt-me](https://github.com/franks-ai-skills/prompt-me) as a
new release of the `prompt-me` plugin in this repository. No pull
request and no second human step are part of a release. This
repository is a plugin marketplace for Claude Code and Codex. It is
temporary: it serves prompt-me until prompt-me publishes its own
releases.

## Decisions

- **Source:** the head of prompt-me's `main`. prompt-me has no tags or
  releases yet, so there is nothing else to take.
- **Versioning belongs to this repository.** Versions start at `0.0.1`,
  and each published change raises only the last number (`0.0.2`,
  `0.0.3`, ...). prompt-me's first own release will be `0.1.0`, so it
  sorts after every version published here.
- **No change, no version.** A run whose source skill tree equals the
  published one makes no commit, no tag and no release.
- **Only the skill is shipped.** The pipeline publishes
  `.agents/skills/prompt-me/` and nothing else. prompt-me's README,
  `.harness/` and `.harness-forge/` are not distributed.
- **Published content is the committed source tree, byte for byte.**
  The script reads the skill from the source commit, not from the
  working tree, and checks that the published folder has the same git
  tree ID as the source folder. Equal tree IDs mean equal file names,
  contents and modes.
- **Direct push to `main`, then a GitHub Release.** The workflow
  commits to `main`, tags the commit `v0.0.N` and creates the GitHub
  Release `v0.0.N`. Triggering the run is the decision to publish, and
  the content was already reviewed in prompt-me.
- **The version lives in the two plugin manifests only.** Claude Code
  takes the version from `.claude-plugin/plugin.json` over the
  marketplace entry, and the Codex marketplace format has no version
  field. The marketplace entry therefore carries no version.
- **The logic lives in scripts, not in the workflow.**
  `scripts/sync.sh` and `scripts/release.sh` do the work and are tested
  locally. The workflow only checks out, calls them and pushes.

Rejected alternatives:

- Taking the latest prompt-me release or tag: none exists.
- Raising the version on every run: users would get updates without
  any change.
- A pull request per run, merged automatically or by hand: adds a
  second workflow and a merge step without adding a check that the
  direct run lacks; two open PRs could claim the same version.
- Shipping `.harness/` or a full mirror: an installing user has no use
  for build records.
- A workflow in prompt-me that pushes here: needs a cross-repository
  token and puts temporary tooling into prompt-me.
- Deciding "no change" by comparing prompt-me commit SHAs: a commit that
  touches only prompt-me's README would produce a version with
  identical content.
- Copying the source working tree: uncommitted, untracked or ignored
  files would be published under a commit SHA that does not contain
  them.
- Trusting `git archive` output without the tree-ID check: the
  `export-ignore` and `export-subst` attributes can drop or rewrite
  files.
- A version in the marketplace entry as well: a third copy that Claude
  Code ignores when `plugin.json` has one.

## Repository layout

```
temp-prompt-me-distribution/
├── .claude-plugin/
│   ├── marketplace.json   # marketplace "temp-prompt-me-distribution", plugin "prompt-me", source "./"
│   └── plugin.json        # Claude Code plugin manifest
├── plugin.json            # Agent Plugins schema manifest, read by Codex
├── skills/prompt-me/      # written by the pipeline only
├── scripts/sync.sh
├── scripts/release.sh
├── tests/sync_test.sh
├── tests/release_test.sh
├── tests/smoke_install.sh
├── .github/workflows/sync.yml
├── .github/workflows/test.yml
└── README.md, LICENSE, .gitignore, .gitattributes, .editorconfig
```

The layout follows the harness-forge repository, which serves both
Claude Code and Codex from `.claude-plugin/marketplace.json` and a root
`plugin.json`. Codex reads `.claude-plugin/marketplace.json` as a
legacy-compatible marketplace source. `tests/smoke_install.sh` checks
that both CLIs install the plugin from this layout before the first
release; if one does not, the layout is fixed before the merge.

`.gitattributes` gets `skills/prompt-me/** -text` after its
`* text=auto eol=lf` line, so git applies no line-ending conversion to
the published skill.

The pipeline changes only `skills/prompt-me/` and the `version` field
of `.claude-plugin/plugin.json` and `plugin.json`. Both always hold the
same value. Everything else is maintained by hand.

The manifests are committed once by hand with version `0.0.0` and no
`skills/` folder. `0.0.0` means nothing has been published yet; the
first run produces `0.0.1`.

Installation:

- Claude Code: `/plugin marketplace add franks-ai-skills/temp-prompt-me-distribution`,
  then `/plugin install prompt-me@temp-prompt-me-distribution`.
- Codex: `codex plugin marketplace add franks-ai-skills/temp-prompt-me-distribution`,
  then `codex plugin add prompt-me@temp-prompt-me-distribution`.

Updating: `/plugin marketplace update temp-prompt-me-distribution` in
Claude Code; `codex plugin marketplace upgrade temp-prompt-me-distribution`
in Codex.

The plugin keeps the name `prompt-me`. The marketplace part of the
install ID keeps it apart from the future official plugin.

## `scripts/sync.sh`

Usage: `scripts/sync.sh <path-to-prompt-me-checkout>`, run anywhere
inside this repository. Requires `bash` 3.2 or later, `git`, `jq`,
`tar`, `mktemp` and `find`.

1. **Checks.** The script stops with a one-line reason and changes
   nothing if any of these fails:
   - The argument is given and is the root of a git checkout.
   - It resolves the source commit SHA once and uses that SHA for every
     later source read.
   - `<sha>:.agents/skills/prompt-me/SKILL.md` exists.
   - The source skill tree contains no symlink (mode `120000`) and no
     submodule (mode `160000`).
   - This repository's working tree is clean, and `skills/prompt-me/`
     contains no untracked or ignored file.
   - `marketplace.json` has exactly one `prompt-me` entry.
   - The two plugin manifests hold the same version, in the form
     `0.0.N`.
   - The tag `v0.0.N+1` does not exist yet.
2. **Detect changes.** If `HEAD:skills/prompt-me` has the same tree ID
   as the source skill folder, it prints
   `no change: still v0.0.N (prompt-me <sha7>)` and exits with
   status 0. Nothing has been written at this point.
3. **Copy.** It extracts the skill from the source commit with
   `git archive` into a temporary folder (umask `022`), replaces
   `skills/prompt-me/` with it and stages it with `git add -A --force`,
   so the destination `.gitignore` cannot drop a committed file.
4. **Verify.** The staged `skills/prompt-me/` must have the source
   tree ID; otherwise the script fails.
5. **Bump.** It sets `version` in both plugin manifests to `0.0.N+1`.
6. **Commit and tag.** It commits with the subject
   `chore(release): v0.0.N+1 from prompt-me <sha7>`. The body names the
   source repository, the full source SHA and the source commit's
   subject. It then creates the annotated tag `v0.0.N+1` with the same
   text as its message.
7. **Report.** It never pushes. When `GITHUB_OUTPUT` is set, it writes
   `changed=true` or `changed=false` and `version=0.0.N` there; on no
   change, `version` is the current version.

**Rollback.** From the first write on, a trap undoes the run if any
step fails. It deletes `v0.0.N+1` only if this run created it and it
still points to this run's commit. It moves `HEAD` back with
`git reset --soft` only if `HEAD` is still this run's commit. It
deletes `skills/prompt-me/` and restores it and both manifests from the
original commit, so partially copied files go too. The script then
exits with the original failure status. The trap is disarmed after
success. Local edits made by someone else during the run cannot be told
apart from the script's own and may be lost; a crash or `SIGKILL`
skips the trap.

## `scripts/release.sh`

Usage: `scripts/release.sh <version>`, with `GH_TOKEN` set. Requires
`gh` and `git`. It makes sure the GitHub Release `v<version>` exists
and is published:

1. It refuses a version not of the form `0.0.N`, and does nothing for
   `0.0.0`.
2. It refuses unless `v<version>` exists as an annotated tag whose
   commit has `<version>` in `plugin.json`.
3. It looks the release up through the GitHub API. Found and
   published: it exits 0. Found as a draft: it fails. Not found (HTTP
   404): it creates the release with the tag message as its notes. Any
   other error, for example authentication or network: it fails.

Every workflow run calls it for the version already on `main` before
syncing. A run that pushed but failed to create its release is
therefore repaired by the next run, whether or not that run publishes
a newer version.

## `.github/workflows/sync.yml`

- Trigger: `workflow_dispatch`, no inputs.
- Permissions: `contents: write`, nothing else.
- Concurrency: group `sync`, `cancel-in-progress: false`. Only one run
  is active at a time; a newer waiting run replaces an older waiting
  one. That is acceptable because each run publishes the source as it
  is when the run starts.
- Steps:
  1. Check out this repository at `main` with full history and tags
     into `dist/`, keeping the default credentials for the push.
  2. Check out `franks-ai-skills/prompt-me` at `main` into `source/`,
     with `persist-credentials: false`. prompt-me is public, so no
     token is needed.
  3. Run `tests/sync_test.sh` and `tests/release_test.sh`. Pushes made
     with `GITHUB_TOKEN` do not start other workflows, so the release
     commit gets no test run of its own.
  4. Run `scripts/release.sh` for the version in `plugin.json`, so a
     release that an earlier run failed to create is created now.
  5. Set the git identity to `github-actions[bot]` and run
     `scripts/sync.sh ../source` in `dist/`.
  6. If `changed=true`: pass the version through `env`, check it
     against `^0\.0\.[0-9]+$`, and run
     `git push --atomic origin HEAD:main "refs/tags/v$VERSION"`. The
     commit and the tag land together or not at all.
  7. If the push succeeded: run `scripts/release.sh "$VERSION"`.
  8. Always: write the outcome to the job summary. "Published v0.0.N
     from prompt-me <sha7>" only when push and release succeeded; "No
     change: still v0.0.N" only when every step succeeded and sync
     reported no change; otherwise "Failed at <step>", with "pushed,
     but its release was not created" as its own case. The summary
     names the failed step and does not guess its cause.
- Third-party actions are pinned to commit SHAs, with the version in a
  comment.

Commits from the workflow are authored by `github-actions[bot]` and
carry no `Assisted-by` trailer, because no model writes them.

## Failure behaviour

- A failed check in `sync.sh`: the run fails with the reason; nothing
  was written.
- A failure after the first write in `sync.sh`: the rollback restores
  the original state; nothing is pushed.
- `main` of this repository moved during the run: the atomic push is
  rejected and the run fails. Nothing is published; a re-run starts
  from the new state.
- The push succeeded but the release was not created: the summary says
  so; the next run creates it in its first release check, unless the
  cause persists (a draft release, missing permissions).
- Branch or tag rulesets that require PRs, status checks or signed
  commits would reject the bot push. None is configured; the README
  states this.

## Testing

`tests/sync_test.sh` and `tests/release_test.sh` are plain bash. They
build throwaway git repositories in a temporary folder. `release.sh` is
tested with a stub `gh` placed first on `PATH`.

`sync.sh` cases:

- The first run produces `0.0.1` in both plugin manifests, a commit
  whose body names the source SHA and subject, and the annotated tag
  `v0.0.1` with the same text.
- A second run without source changes writes nothing.
- A source change outside the skill writes nothing.
- A changed file produces `0.0.2`; a deleted file disappears.
- Hidden files, an executable file (mode `100755`), a file the
  destination `.gitignore` matches and a CRLF file are published
  unchanged; a rerun after them reports no change.
- Uncommitted and untracked source files are not published.
- `0.0.9` becomes `0.0.10`.
- A relative source path and a run from a subdirectory work.
- `GITHUB_OUTPUT` receives `changed` and `version`.
- Refusals that change nothing: missing argument, source not a checkout
  root, missing `SKILL.md`, a symlink in the source skill, a dirty or
  untracked destination tree, an ignored file under
  `skills/prompt-me/`, a second `prompt-me` marketplace entry,
  mismatched or non-`0.0.N` versions, an existing next tag.
- Rollback: a failing `pre-commit` hook, with an ignored file name in
  the source, leaves `HEAD`, tags and the working tree (ignored files
  included) as they were.

`release.sh` cases: `0.0.0` does nothing; an invalid version, a missing
tag, a lightweight tag and a tag whose commit has another version are
refused; an existing published release is accepted; a draft is
refused; HTTP 404 creates the release from the tag message; another API
error fails.

`.github/workflows/test.yml` runs both test scripts and `shellcheck` on
every push and pull request.

`tests/smoke_install.sh` runs locally before the merge. With throwaway
`CLAUDE_CONFIG_DIR` and `CODEX_HOME` folders, it uses a local copy of
this repository at `0.0.1` as the marketplace: `claude plugin validate`,
`claude plugin marketplace add`, `claude plugin install`; then
`codex plugin marketplace add`, `codex plugin add`. It checks that
`skills/prompt-me/SKILL.md` is in each installed copy. A local source
does not show how hosted updates behave.

Manual end-to-end check after the merge:

1. Trigger the sync workflow once; expect tag and release `v0.0.1`.
2. Add the marketplace and install `prompt-me` in Claude Code and in
   Codex; the skill is available in a new session.
3. Trigger the workflow again; expect "No change: still v0.0.1".
4. After the next skill change in prompt-me, trigger it again; expect
   `v0.0.2`, and check that both update commands pick it up.

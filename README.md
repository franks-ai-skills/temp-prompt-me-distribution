# temp-prompt-me-distribution

Temporary plugin marketplace for [prompt-me](https://github.com/franks-ai-skills/prompt-me), an agent skill for Claude Code and Codex. prompt-me turns a request into a well-defined prompt instead of carrying it out, saves that prompt for review and stops. This repository publishes builds of prompt-me's `main` branch until prompt-me publishes its own releases.

## Install

Claude Code:

```
/plugin marketplace add franks-ai-skills/temp-prompt-me-distribution
/plugin install prompt-me@temp-prompt-me-distribution
```

Codex:

```
codex plugin marketplace add franks-ai-skills/temp-prompt-me-distribution
codex plugin add prompt-me@temp-prompt-me-distribution
```

## Update

- Claude Code: `/plugin marketplace update temp-prompt-me-distribution`
- Codex: `codex plugin marketplace upgrade temp-prompt-me-distribution`

## Versions

Versions here are `0.0.N`. Each one is a build of prompt-me's `main` at the commit named in its release notes. prompt-me's own releases start at `0.1.0`, so they sort after every version published here.

## Publishing

Run the "Sync prompt-me" workflow from the Actions tab. It publishes the skill from prompt-me's current `main` as the next `0.0.N`: a commit on `main`, a tag and a GitHub Release. A run without changes to the skill publishes nothing.

The workflow pushes to `main` directly. Branch or tag rulesets that require pull requests, status checks or signed commits would reject that push.

The design is in [docs/superpowers/specs/2026-10-30-prompt-me-sync-pipeline-design.md](docs/superpowers/specs/2026-10-30-prompt-me-sync-pipeline-design.md).

## License

[AGPL-3.0](LICENSE), the same license as prompt-me.

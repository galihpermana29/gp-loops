# Domain Docs

How the engineering skills should consume domain documentation in this workspace.

This workspace is **one business domain implemented across many repos**.
The glossary and the architecture decision records therefore live once, at the workspace root, not once per repo.

Paths below are relative to **this workspace's own root** — the directory holding `.beads/`,
which `bd where` prints. Never read them from another workspace on this machine:
a different workspace describes a different business, and its glossary will quietly
lead you to the wrong vocabulary.

## Before exploring, read these

- **`<workspace-root>/CONTEXT.md`** - the workspace glossary, shared by every repo.
- **`<workspace-root>/docs/adr/`** - architecture decision records, including cross-repo decisions such as how a contract propagates from a backend to its clients.
- **`<workspace-root>/CLAUDE.md`** - the repo map.
  Read this to work out which repo a change belongs in before touching anything.
- The current repo's own **`AGENTS.md`** (symlinked to `CLAUDE.md` in most repos) for that repo's technical conventions.

If any of these files don't exist, **proceed silently**.
Don't flag their absence and don't suggest creating them upfront.
The `/domain-modeling` skill, reached via `/grill-with-docs` and `/improve-codebase-architecture`, creates them lazily when terms or decisions actually get resolved.

## Why workspace-level rather than per-repo

A domain concept means the same thing in whichever repo of this workspace you meet it: the frontend, the backend, and any internal tool all speak about the same lifecycle, the same states, the same cutoffs.
A glossary per repo would define each term several times and let the definitions drift, which is the opposite of what a ubiquitous language is for.

What genuinely varies per repo is *technical* convention, and each repo's own `AGENTS.md` already carries that.

## File structure

```
<workspace-root>/
├── CONTEXT.md          ← the shared glossary
├── CLAUDE.md           ← repo map, local-only
├── docs/adr/
│   ├── 0001-....md
│   └── 0002-....md
├── .beads/             ← the shared queue, at the root so every repo resolves to it
├── .workspace/         ← tooling: loop scripts and these config files
├── <repo>/
├── <repo>/
└── ...
```

These files are **local-only**.
The workspace is not a git repository and is never committed, so nothing here reaches a team repo or CI.

If the domain ever splits into genuinely separate contexts, for example core ordering versus billing, the upgrade path is a `CONTEXT-MAP.md` at the workspace root pointing at one `CONTEXT.md` per context.
Don't reach for that until the single glossary actually becomes unwieldy.

## Use the glossary's vocabulary

When your output names a domain concept, in an issue title, a refactor proposal, a hypothesis, or a test name, use the term as defined in `CONTEXT.md`.
Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal.
Either you're inventing language the project doesn't use, and should reconsider, or there's a real gap to note for `/domain-modeling`.

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders), but worth reopening because..._

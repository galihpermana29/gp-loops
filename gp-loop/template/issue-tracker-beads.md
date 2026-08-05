# Issue tracker: beads (workspace-level)

Issues and tickets for this repo live in the shared **beads** database at the workspace root,
in `.beads/` there.
They do not live in this repo, and they are not GitHub Issues.

Every repo in the workspace shares this one database, which is what lets a ticket in one repo block a ticket in another.
Every other workspace on this machine has its own separate database, and they must never be crossed:
a ticket written into the wrong queue is invisible to the work it belongs to.
Run `bd where` to print the workspace root you are actually resolving to, and use that path.
Never assume the path of a workspace you read about in a document — including this one.

This is personal local tooling.
Nothing described in this file is committed to this repo, and teammates are unaffected by it.

## Reaching the database

`bd` discovers its database by walking up from the current directory, but **it stops at a git repository boundary**.
Since every repo here is its own git repo, plain `bd` inside one will not find the workspace database.

Interactive use is handled automatically.
A `chpwd` hook in `~/.zshrc` sets `BEADS_DIR` to the nearest beads workspace above the current directory, ignoring git boundaries, so `bd ready` just works from any repo.

Scripts and agent loops must not rely on that, since they may run under a non-interactive shell.
Always pass the workspace root explicitly, taking it from `bd where` or from the root
named in the loop's prompt:

```bash
bd where                       # prints <workspace-root>/.beads
bd -C <workspace-root> <command>
```

Run `bd prime` once at the start of a session for the full command reference and project memories.

## Conventions

- Every issue carries a `repo:<name>` label naming the repo it targets, for example `repo:web`.
  The database is shared across all repos in the workspace, so this label is what scopes work back to a codebase.
- A **spec is a document, not an issue**.
  Specs live at `.scratch/<feature-slug>/spec.md` inside the target repo, kept out of commits via `.git/info/exclude`.
  The owning issue records the spec path in its `--design` field.
- A **seed issue is an epic**.
  Tickets produced from a spec are created with `--parent=<epic-id>` so the epic closes when its children do.
- Triage state is a label, using the five canonical roles:
  `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`.
- Acceptance criteria go in `--acceptance`, never buried in the description.
  The autonomous loop reads that field to decide whether it is finished.

## When a skill says "publish to the issue tracker"

Create an issue:

```bash
bd create --title="..." --description="..." --type=task --priority=2 \
  --acceptance="..." --parent=<epic-id>
bd tag <id> repo:<name>
```

Priority is `0`-`4`, where `0` is critical and `4` is backlog.
The words high, medium, and low are not valid.

Use `--validate` to confirm the description carries the required sections before publishing.

## When a skill says "fetch the relevant ticket"

```bash
bd show <id>
```

This returns the issue with its dependencies and audit trail.
`bd search <query>` finds an issue when only the subject is known.

## Blocking and structure

```bash
bd dep add <issue> <depends-on>   # issue is blocked until depends-on closes
bd blocked                        # everything currently blocked
bd show <id>                      # what blocks this, and what it blocks
```

Cross-repo edges are ordinary edges.
A `repo:web` ticket may depend on a `repo:api` ticket, and this is the main reason the database is shared rather than per-repo.

## Wayfinding operations

Used by `/wayfinder` and by the autonomous loop.

- **Frontier**: `bd ready` lists open issues with no active blockers.
  The autonomous loop takes the frontier filtered to the `ready-for-agent` label, so a human has blessed every item it picks up.
- **Claim**: `bd update <id> --claim` before any work.
  This is atomic, so two loops cannot take the same issue.
- **Resolve**: `bd close <id> --reason="..."`, only after the verify command for that issue exits zero.
- **Notes**: `bd note <id> "..."` records an attempt that failed, so the next fresh-context iteration does not repeat it.
- **Memory**: `bd remember "insight"` stores knowledge that outlives any single issue.
  Do not create `MEMORY.md` or `progress.txt` files, as beads already holds this.

## Rules for autonomous loops

- Never close an issue on self-assessment.
  Run the repo's verify command and close only on a zero exit.
- Record the resulting commit sha on the issue rather than putting issue ids in commit messages.
  Commit messages are read by teammates who cannot see this database.
- After three failed attempts on one issue, stop.
  Set the `ready-for-human` label, write what was tried into `bd note`, and move on.
- Never push. Landing is a human action.

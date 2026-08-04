---
name: gp-loop
description: An autonomous coding loop driven by a beads queue. Day-to-day runbook, plus bootstrap for a new machine or a new workspace.
disable-model-invocation: true
---

Work is tracked in **beads**, one database per workspace, shared by every repo inside it.
Work is executed by a **loop**: a fresh `claude --print` per ticket, so every iteration starts with a
clean context window and disk is the only memory.

> **The loop runs Claude with `--dangerously-skip-permissions`.** It has to — an unattended loop
> cannot answer permission prompts. Every iteration can read, write and execute anything your user
> account can. The guards protect the repository, not the machine. See the README before first use.

Two branches through this skill:

- **Setting up a machine or a new workspace** → [BOOTSTRAP.md](BOOTSTRAP.md).
- **Doing the work** → the runbook below.

## The runbook

### 1. Prepare the branch

The loop commits to whatever branch is checked out, and it requires a branch that is neither the
default nor dirty.

```bash
git -C <workspace>/<repo> checkout -b <your-prefix>/<task-slug>
```

**One branch per task, not per ticket.**
Every ticket under the same epic stacks onto it, so the task lands as one reviewable diff.

Done when: the target repo is on a task branch with a clean tree.

### 2. Grill, spec, tickets — one session

Create a seed ticket first, holding whatever context you have. A rough one is fine; the grill
sharpens it.

```bash
cd <workspace> && claude
```

Then, in a single session:

```
/grill-with-docs      then: grill <ticket-id>
/to-spec
/to-tickets
```

`/to-spec` synthesizes from conversation context rather than re-interviewing, so these three cannot
be split across sessions.
The grill writes terms into the workspace `CONTEXT.md` and decisions into `docs/adr/`.
`/to-spec` writes `.scratch/<slug>/spec.md` in the target repo.
`/to-tickets` creates child tickets with blocking edges.

Done when: `bd children <epic>` shows the tickets, and `bd blocked` shows the edges you expect.

### 3. Open the gate

The loop claims only tickets labelled `ready-for-agent`.
That label is the **gate**, and it is the review checkpoint that matters most.

```bash
bd ready                          # what to-tickets produced
bd tag <id> repo:<repo-name>      # the loop needs this to know where to work
bd tag <id> ready-for-agent       # open the gate
```

Keep three kinds of ticket behind the gate, labelled `ready-for-human` instead:

- anything that mutates production data
- anything whose completion cannot be checked mechanically, so sign-off is a person's judgement
- an epic, which has no single implementable unit

A ticket whose output feeds others deserves a sign-off ticket between them, blocking every consumer.
That way a wrong result stops at one ticket rather than propagating.

Done when: `bd ready --label ready-for-agent` lists exactly the tickets you intend the loop to touch.

### 4. Dry run, then run

```bash
cd <workspace>
./.workspace/ralph.sh --dry-run 5     # reports its picks, mutates nothing
./.workspace/ralph.sh 5
```

**Dry run every time.**
It costs two seconds and names the tickets, repos and branches it would use.

The loop stops on its own when the gate closes, so a human-gated ticket is a natural stopping point
rather than an interruption.

A failed attempt spends an iteration, so give it a little more headroom than you have tickets.
Network failures are retried without spending a strike; genuine failures get three before the ticket
is handed to a human.

Done when: the dry run names the tickets you expect, on the branch you prepared.

### 5. Verify, then land

Treat a closed ticket as a claim, not a fact.
The completion promise is self-reported, and the loop is told not to lie, which is exactly why it
needs checking.

```bash
git -C <repo> log --oneline <default-branch>..HEAD
bd list --status=closed
```

Read the iteration transcript in `.workspace/logs/` even on success.
Then run the repo's own verify command yourself.

The loop never pushes.
Review and landing stay yours.

## Reference

**Guards.** The loop refuses a ticket with no `repo:` label, a repo on its default branch, and a
dirty tree. It refuses to start at all if the `code-review` skill is missing, because the prompt
tells every iteration to review its own work and a missing skill makes that a silent no-op. After
three failed attempts it labels the ticket `ready-for-human` and moves on.

**Where things live.** The queue is `<workspace>/.beads`. Tooling and prompts are in
`<workspace>/.workspace`. The glossary is `<workspace>/CONTEXT.md`, decisions are
`<workspace>/docs/adr/`.

**Reaching the queue.** `bd` stops discovery at a git repo boundary, so plain `bd` inside a repo
cannot see a workspace-level database. A shell hook resolves it by walking up to the nearest
`.beads/config.yaml`. Scripts pass `bd -C <workspace>` rather than relying on that.

**Two workspaces, two queues.** Each workspace root holds its own `.beads`, so `bd ready` in one
never shows the other's work. Never point one workspace's tooling at another's glossary or queue:
a different workspace describes a different business.

**GUI.** `bdui start` from the workspace root serves a read-write board at `127.0.0.1:3000`.
`bv` is a read-only TUI with a dependency graph.

**Recovering a run.** A ticket left `in_progress` after a crash returns to the queue with
`bd update <id> --status open`.

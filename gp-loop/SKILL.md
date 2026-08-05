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

## First, find out where you are

Do not ask the user which branch they want, and do not paste setup commands for them to run. Work it
out and offer to act. Start here, every time:

```bash
<skill-dir>/bootstrap.sh --check <the directory the user is working in>
```

`--check` changes nothing and reports the whole state in one pass: binaries, queue, tooling, shell
hook, repo wiring, `AGENTS.md`, skills.

Read it, then take one of two branches:

- **Anything reports `todo`** → this is setup. Follow [BOOTSTRAP.md](BOOTSTRAP.md), which is written
  for you rather than for the user. Tell them what you are about to run and why, then run it. They
  still approve each command through the normal permission prompt, so nothing happens silently.
- **Everything reports `ok`** → the workspace is ready. Go to the runbook below.

If the directory is not obviously the workspace root, ask which directory it is. That, and the ticket
prefix, are the only two things the user has to decide.

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

Start the board. It is where tickets get written, where the dependency graph is legible, and where
you open the gate later, so it is the first thing up rather than an optional extra:

```bash
bdui start                        # read-write board at 127.0.0.1:3000
```

Create a seed ticket on it, holding whatever context you have. A rough one is fine; the grill
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

#### Write fewer, fatter tickets than feels natural

This is the one thing to override `/to-tickets` on. Its instinct is to split wherever work is
mechanically separable, and that instinct is wrong here, because every ticket is worked by a fresh
process with an empty context window.

Each one therefore pays a full cold start before it writes a line: re-reading the glossary and the
ADRs, searching the codebase, running the suite, reviewing the diff, and the bookkeeping. Measured
across one feature's worth of tickets, that fixed cost came to roughly **10 minutes per ticket**,
against about **1.4 minutes per 100 changed lines** of actual work. Two-thirds of a typical
iteration is the cost of starting, not the cost of the work.

The evidence, from tickets in the same run: one changed 206 lines in 9 minutes; another changed 998
lines, nearly five times as much, in 20 minutes. Three of them re-run as a single fat ticket took
**10 minutes against the original 40**, with no defect traceable to the merge.

So:

- **Size a ticket near 800-1000 changed lines.** That lands cleanly in one context window, including
  a shared component. Two hundred is far too small.
- **Merge anything that was split only because it could be**, rather than because a blocker sits
  between the halves. Real blocking edges still deserve separate tickets.
- **The ceiling is the context window, not a line count.** If a ticket genuinely will not fit,
  splitting is still right, and the prompt tells the loop to split rather than half-build.

Do not claw the time back by dropping the per-ticket `/code-review`. The same experiment tried it,
and two functional defects reached the branch: a modal stranded on a confirmation it could not
dismiss, and a date function that threw on one input and silently returned a wrong result on
another. Fat tickets are free; skipping review is paid for later.

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

**GUI.** `bdui start` from the workspace root serves the read-write board at `127.0.0.1:3000`, which is where step 2 begins.
`bv` is a read-only TUI with a dependency graph.

**Recovering a run.** A ticket left `in_progress` after a crash returns to the queue with
`bd update <id> --status open`.

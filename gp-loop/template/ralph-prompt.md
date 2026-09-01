# Ralph build prompt

You are one iteration of an autonomous loop.
You have a fresh context window and no memory of previous iterations.
Everything you need is on disk or in beads.

Your working directory is already the correct repo.
Do not change repos.

## 0. Orient

The workspace guide and this repo's conventions are loaded for you already:
`CLAUDE.md` files in this repo and in its parent directories are read automatically.
Do not spend a tool call re-reading them.

Read these two before doing anything else, since they are not loaded automatically:

- `<workspace-root>/CONTEXT.md` - the shared domain glossary, if it exists.
- `<workspace-root>/docs/adr/` - architecture decisions touching your area, if any exist.

`<workspace-root>` is the path given at the end of this prompt. Never guess it, and never read
these files from another workspace on this machine: a different workspace describes a different
business, and its glossary will lead you to the wrong vocabulary.

Throughout this prompt, `bd` means `bd -C <workspace-root>`, using the workspace root given at the end.
The beads database lives at the workspace root, not in this repo.
`bd` on its own stops looking at the repo boundary and will not find it, so always pass `-C`.

You need four beads commands and no others. Do not run `bd prime`:

```
bd show <id>                        # only if you need a bead other than your own
bd update <id> --append-notes "..."
bd close <id> --reason="..."
bd create --title="..." --priority=4
```

## 1. Your bead

Your bead and its spec are inlined at the end of this prompt.
Do not run `bd show` for your own bead and do not re-read the spec file - you already have both.

Read the description, the `acceptance` criteria and the spec in full before writing anything.
The spec is the authority on what "done" means, not your own judgement.

## 2. Check what exists before you build

Building a second copy of something that already exists is the single most common way an
unattended loop wastes an iteration. So this step is not optional - only its cost is.

An **Orientation** section is inlined at the end of this prompt. When it has content, it names
where the modules for this epic live and what already exists, and it names the commit it was
accurate at. Somebody established that with a human present, so do not re-establish it:

- If it names what your bead needs, go straight to those paths and read them.
- If it is silent on something your bead needs, search for that one thing. One `Explore`
  subagent, one specific question, e.g. "is there an existing X anywhere in this repo?"
- If a path it names no longer exists, it is stale. Note that on your bead
  (`bd update <id> --append-notes "orientation stale: ..."`) and then search normally.

When the Orientation section says none was written, search from scratch instead: at most two
`Explore` subagents, and think hard about naming variations before concluding something is
missing. Delegate it rather than reading the repo yourself, so your own context stays free for
the work.

## 3. Implement

Do exactly one bead's worth of work.
Do not fix unrelated things you notice, do not refactor adjacent code, and do not start the next bead.
If you spot something genuinely worth doing, file it: `bd create --title="..." --priority=4`, then carry on.

Use `/tdd` where the seams are already agreed in the spec.
Follow the conventions in this repo's `AGENTS.md`.
Use the vocabulary from `CONTEXT.md` in names, tests, and messages.

Keep the loop tight:

- typecheck often
- run single test files as you go
- run the full suite once at the end

## 4. Verify

Run this repo's verify command, the one named in the bead's acceptance criteria.
If the bead names no verify command, use the one named in `AGENTS.md`.
If neither names one, use the repo's typecheck plus its full test suite.

Some repos have no test suite at all. Do not treat that as verification passing.
Run the strongest check that does exist - a typecheck, a lint, a build - and carry on, but say so
plainly rather than letting a weaker check stand in silently for a stronger one.

Do not run `/code-review`. Review happens once per branch, at land time, driven by a human -
not once per bead. Your verification is the check above, and nothing more.

## 5. Record

Only if verification passed with a zero exit:

1. Commit to the current branch. Write the message in this repo's own convention.
2. Capture the sha: `git rev-parse HEAD`.
3. `bd update <id> --append-notes "implemented in <sha>; verified with <the exact command you ran>; not reviewed"`
   Name the command, not the outcome. `COMPLETE` means different things in a repo with a full suite
   and a repo with only a typecheck, and the person reading this later cannot tell which they got
   unless you write it down. If there was no test suite, say that here too.
   End with `not reviewed`, because you did not review and the branch review has not happened yet.
   A closed bead that looks reviewed and is not is the one thing this note exists to prevent.
4. `bd close <id> --reason="<one line on what landed>"`
5. Output `<promise>COMPLETE</promise>` as the last line of your response.

If verification did not pass, do none of the above.
Instead run `bd update <id> --append-notes "..."` describing precisely what you tried and how it failed, so the next iteration does not repeat it.
Then stop without emitting the promise.
The loop will retry, and hand the bead to a human after three failures.

Use `bd remember "insight"` for anything you learned that outlives this bead.

## 999. Never push

Commit, never push.
Landing is a human action, always.
Do not open a pull request, do not force anything, and do not touch a remote.

## 9999. Never claim a completion you did not verify

Emit `<promise>COMPLETE</promise>` only when the verify command actually exited zero in this iteration.
Not because the work looks right, not because the tests "should" pass, and not to end the loop.
An unverified promise is worse than a failed iteration, because it closes a bead that isn't done and nobody finds out until much later.

If you are stuck, say so in the bead notes and stop.
Stopping honestly is a good outcome.

## 99999. Do not implement placeholders

No stubs, no `TODO: implement`, no simplified versions that satisfy the test but not the spec.
Full implementations only.
If the bead is too large to complete properly in one iteration, do not half-build it.
Split it: `bd create --parent=<id>` for the pieces, note why on the parent, and stop.

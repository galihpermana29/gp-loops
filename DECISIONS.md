# Decisions

Why gp-loop is shaped the way it is. Each entry is a trade that had a real alternative.

## The loop runs with permissions bypassed

An unattended loop cannot answer permission prompts, so `--dangerously-skip-permissions` is
load-bearing rather than incidental. There is no version of this that both runs unattended and asks
before acting.

What follows from that is a disclosure obligation rather than a mitigation: the README says what the
flag reaches, up front, and the guards are described honestly as protecting the repository and not
the machine. A container would be the real answer, and one is not shipped — an untested container
is its own hazard, and pretending otherwise would be worse than saying so.

## The queue is the loop's memory

Every iteration is a fresh `claude --print` with an empty context window. Nothing carries between
tickets except what is written to disk: the ticket, the spec, the commit, the log.

The alternative is one long-lived session that accumulates context. That degrades — later work is
done with a context full of earlier work, and the failure mode is subtle rather than loud. A fresh
context per ticket costs a cold start each time and buys a predictable starting state.

The consequence is that ticket quality *is* output quality. A vague ticket cannot be rescued by
context the agent no longer has.

## Review happens once per branch, not once per ticket

The loop used to run `/code-review` in every iteration, and refused to start without the skill.
It now runs it in none, and the human runs it once on the branch before landing.

The arithmetic is the reason. `/code-review` spawns two sub-agents, each reading the standards
documents and the diff; measured on one real review that came to roughly 173k tokens. The loop
commits **per ticket**, so a sixteen-ticket epic paid that sixteen times — for a diff that lands
once, because the loop puts every ticket of an epic on one branch. Sixteen reviews of fragments,
where one review of the whole thing is what actually gates the merge.

This is not the same as dropping review, which was tried and failed: two functional defects reached
the branch — a modal stranded on an undismissable confirmation, and a date module that threw on one
input and silently returned a wrong period for another. Both are diff-visible, so a branch-level
review catches both. That experiment removed review; it never moved it.

What it costs is **feedback latency**, and that is a real cost paid in the expensive currency. A
defect introduced in ticket 2 now surfaces after ticket 16, with fourteen tickets built on top of
it, and the rework is measured in iterations. Per-ticket review failed fast. This does not.

Two things keep it honest. Every ticket note now ends `not reviewed`, so a closed ticket never looks
reviewed when it is not — the note the prompt already wrote gained a clause rather than the loop
gaining a second note nobody would read. And `SKILL.md` step 5 makes the branch review an explicit
step rather than an assumption.

`tdd` stays in the loop. It spawns no sub-agents, so it was never part of the cost, and its
pre-agreed-seams rule is satisfied by `/to-spec`, which confirms seams with a human and records them.
Its absence is still only a warning, because it shapes how work is approached rather than gating it.

## The loop measures what it costs

Every claim in this file was measured in minutes. None was measured in tokens, which is how a month
of runs can end at a session limit with nothing to point at.

Iterations now use `--output-format json` and append a row to `costs.tsv`: cost, tokens, cache,
sub-agents spawned, turns, duration, and the models that actually ran. Two columns exist for
specific suspicions. `subagents`, because the prompt told every iteration to delegate its codebase
search and nothing ever counted how wide that went. `models`, because an unset `RALPH_MODEL`
inherits the user's Claude Code default, so a loop can run entirely on Opus without ever saying so.

`RALPH_MODEL` is deliberately **unset** by default. Pinning something cheaper would change the
quality of every existing loop on sync, silently, on the strength of a guess. The file is the
evidence; the pin is what you do after reading it.

The cost is one real hazard: the completion promise moved from a grep over the raw output to a `jq`
extraction of `.result`. Get that wrong and the loop stops recognising success and re-queues work
that passed — a failure that looks fine in a dry run, because a dry run never invokes the agent.

## The loop is told where things are, not left to find out

Every iteration used to search the codebase from scratch to check its work did not already exist.
That instruction is sound — building a second copy of something is the most common way an
unattended iteration is wasted — but it has no stopping condition, so a rational agent fans out into
several full-repo sweeps, and sixteen tickets re-derive one layout sixteen times.

An epic can now write `.scratch/<slug>/orientation.md` beside its spec, naming where its modules
live and what already exists. `ralph.sh` inlines it exactly as it already inlines the ticket and the
spec, and the prompt tells iterations to confirm against it and search only for genuine gaps.

The exhaustive pass still happens; it happens once per epic instead of once per ticket, in the
session where a human is already reading the code.

The spec cannot carry this, deliberately: `/to-spec`'s template says *"Do NOT include specific file
paths or code snippets. They may end up being outdated very quickly."* That is correct for a
document read months later and wrong for one consumed by sixteen iterations the same afternoon —
hence a separate file, with the commit it was accurate at written on it.

A stale orientation is worse than none, because it points confidently at a module that has moved.
So the prompt instructs an iteration that finds a bad path to record staleness on its ticket and
fall back to searching, and an epic with no orientation file gets the old unbounded search — now
capped at two `Explore` agents.

## Network failures do not spend a strike

A ticket is handed to a human after three failed attempts. A dropped connection used to count as
one, so flaky wifi could park a ticket that was never broken.

The iteration is still spent — the loop did take a turn — but the strike is not. The retry budget
exists for tickets that genuinely cannot be done, and diluting it with transient failures makes it
mean nothing.

## Configuration is workspace-relative, never absolute

An earlier version hardcoded one workspace's paths into the prompt and the config documents. Copying
that tooling into a second workspace carried the paths with it, so the second workspace's agents read
the first workspace's glossary — a different business, described in the wrong vocabulary, silently.

`ralph.sh` derives every path from its own location and appends the resolved workspace root to each
prompt. The documents say "the workspace root" and tell the reader to get it from `bd where`. The
rule for anyone editing them: no absolute path survives a copy, so do not write one.

## Starters are generated, and excluded from git

The prompt tells the agent to follow the repo's `AGENTS.md` and use `CONTEXT.md`'s vocabulary. In a
fresh repo neither exists, and the instruction becomes noise the agent has to decide how to ignore.

Generating them keeps the prompt unconditional. The alternatives were conditional wording in the
prompt, which makes it fuzzier, or requiring them as a precondition, which makes the first run fail.

They are written to `.git/info/exclude` rather than committed. Writing a file into somebody's project
during install is a surprising thing for a tool to do; the adopter commits them once they have read
them.

## The skill is the front door, and carries the template

The tooling used to live inside a workspace, with the skill symlinked out of it. That works for one
person and cannot be installed by anyone else — the install instruction was "clone my private repo".

Now the skill is what you install, and `bootstrap.sh` creates a workspace *from* the template it
carries. That inversion is what makes the first step a single command.

## One canonical `ralph.sh` per machine, config copied per workspace

In the original setup, a second workspace symlinked `ralph.sh` and the prompt to the first, and
copied the config documents. The script never drifted; the documents did — which is precisely the
absolute-path bug above.

gp-loop copies everything from the template per workspace, so each is independent and can be edited
without affecting the others. The cost is that a fix to the template does not reach existing
workspaces. That is the right trade for tooling somebody else owns: surprising them with a changed
loop is worse than them running a slightly old one.

## Attribution

The Ralph technique is Geoffrey Huntley's. beads is Steve Yegge's. The skills the loop and its
pipeline hand off to are Matt Pocock's. What is here is the integration and the guards, and the
README says so — the alternative reads as appropriation to anyone who recognises the parts.

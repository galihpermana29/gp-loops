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

## `code-review` is required, `tdd` is not

The loop refuses to start if `code-review` is absent.

The prompt tells every iteration to review its own work before promising completion. If the skill is
missing that instruction is a silent no-op: the loop ships unreviewed code and reports success. The
failure is invisible, which is what makes it worth a hard stop rather than a warning.

This is not a guess. On one real feature, dropping the per-ticket review let two functional defects
reach the branch — a modal stranded on an undismissable confirmation, and a date module that threw
on one input and silently returned a wrong period for another. Both were caught by review and by
nothing else.

`tdd` shapes how work is approached rather than gating it, so its absence is a warning.

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

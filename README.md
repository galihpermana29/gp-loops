# gp-loop

An autonomous coding loop for Claude Code, driven by a [beads](https://github.com/gastownhall/beads) queue.

You write tickets. The loop picks up each one in a fresh `claude --print` process, implements it,
verifies it, commits, and moves to the next. Every iteration starts with an empty context window,
so nothing carries over except what is written to disk.

<img width="1583" height="758" alt="image" src="https://github.com/user-attachments/assets/8d1b7add-4642-475b-8581-3b504dd99c8d" />


---

## ⚠️ Read this before installing

**The loop runs Claude with `--dangerously-skip-permissions`.**

That flag exists because an unattended loop cannot answer permission prompts. It means every
iteration can read, write, and execute anything your user account can, without asking you first.
There is no way to run this loop and also have those prompts.

What that buys you, and what it costs:

- The agent can edit any file your account can reach, not only the repo it was pointed at.
- It runs your build, your tests, and anything else your project's tooling invokes.
- It commits automatically. It never pushes.
- A badly-worded ticket is executed literally, at machine speed, with no confirmation step.

The loop does guard the repository. It refuses to run on a default branch, refuses a dirty tree,
stashes partial work when an iteration dies, and gives up on a ticket after three failed attempts.
**Those guards protect the repo, not the machine.**

If that trade is not one you want to make on your everyday machine, run it in a container or a
throwaway VM. This project does not ship one yet.

**It also spends money.** Each iteration is a full Claude Code session that reads the codebase, works,
runs your suite and reviews its own diff, so it consumes tokens on the scale of a substantial
session rather than a single question — and `ralph.sh 5` does that five times unattended. Start with
`ralph.sh 1` and look at your usage before letting it run in double digits.

By using this you accept the risk. See [LICENSE](LICENSE) — it is provided as is, with no warranty.

---

## What you need

| | |
|---|---|
| [Claude Code](https://claude.com/claude-code) | the agent the loop drives |
| [beads](https://github.com/gastownhall/beads) (`bd`) | the ticket queue |
| `git`, `jq` | |
| zsh or bash | fish works, with one manual step |
| [`code-review`](https://github.com/mattpocock/skills) | **required** — the loop refuses to start without it |
| `grill-with-docs`, `to-spec`, `to-tickets`, `triage`, `tdd` | the authoring pipeline, same source |
| [`bdui`](https://www.npmjs.com/package/beads-ui) | the board you write and triage tickets on |

The bootstrap checks for all of these and offers to install the skills, so you do not have to chase
them individually.

**One prerequisite that is easy to miss: the loop needs a command it can run to know it succeeded.**
It gates its completion promise on that command exiting zero, so the loop's confidence is exactly
your verify command's coverage. If your project has no tests, the loop still works — it just
verifies less, and it will say so in the ticket notes rather than quietly implying otherwise.

## Install

```bash
npx skills add galihpermana29/gp-loops --skill=gp-loop -g
```

**Keep the `-g`.** Without it the skill installs into whichever project you are standing in, which
loads it there only and leaves `.agents/` and `skills-lock.json` untracked in that repo — and the
loop refuses to run against a dirty tree.

Then check it actually arrived, because the installer reports `Done!` either way:

```bash
ls ~/.claude/skills/gp-loop        # expect SKILL.md, BOOTSTRAP.md, bootstrap.sh, template
```

If that is empty while `~/.agents/skills/gp-loop` exists, the files landed but your agent was never
linked to them. Name it explicitly:

```bash
npx skills add galihpermana29/gp-loops --skill=gp-loop -g -a claude-code
```

`skills add` targets around 75 agents and picks them up by detection, which does not always include
the one you are sitting in. Restart Claude Code afterwards — a newly installed skill is not always
picked up by a running session. The skill is `gp-loop`, singular; `gp-loops` is the repository.

Then, in Claude Code:

```
/gp-loop
```

With no workspace set up it sets one up: it works out what is missing, asks you for a ticket prefix,
creates the queue, wires the repo, and offers to write an `AGENTS.md` by reading your code. Every
command surfaces as a permission prompt, so nothing happens without you seeing it. It is idempotent —
run it as often as you like.

## How it fits together

```
<workspace-root>/
├── .beads/          the queue
├── .workspace/      the loop: script, prompt, config docs
├── CONTEXT.md       shared glossary (optional, generated as a starter)
├── docs/adr/        architecture decisions (optional)
└── <repo>/ ...      the code — either repos beside these, or this root itself
```

## Which shape am I?

A workspace is wherever `.beads/` sits. That is the whole definition, and it means you choose how
much one queue covers. Two shapes, both first-class:

**One repo, self-contained.** `.beads/` goes inside the repo. The repo *is* the workspace.

```
my-app/
├── .beads/          the queue
├── .workspace/      the loop
└── src/
```

Calling a lone repo a "workspace" does sound odd, and it is worth saying so rather than pretending
otherwise: the word is about where the queue lives, not about having several projects. This is the
common case. Start here.

**Several repos whose work interlocks.** A folder above them holds `.beads/`, and they share one
queue.

```
my-company/
├── .beads/          ONE queue, shared by all of them
├── web/
├── api/
└── admin/
```

**The deciding question is not how many repos you have — it is whether a ticket in one needs to block
a ticket in another.** That is the only thing a shared queue buys you, and it is worth a lot when you
need it: an API change and the frontend that consumes it land in the right order, tracked as one
dependency rather than two lists and a memory.

If nothing blocks across repos, keep the queues separate. Separate is simpler, and you can move up
later — splitting a shared queue afterwards is the harder direction.

Either way the `repo:<name>` label on every ticket is what tells the loop which codebase to work in.

The daily shape:

```bash
bdui start                                 # the board, at 127.0.0.1:3000
```

Write a rough seed ticket on the board, then sharpen it into real ones in a single Claude session:

```
/grill-with-docs      then: grill <ticket-id>
/to-spec
/to-tickets
```

Then label, gate, and run:

```bash
bd tag <id> repo:<name> ready-for-agent    # label it, open the gate
git checkout -b <branch>                   # the loop needs a non-default branch
./.workspace/ralph.sh --dry-run 3          # see what it would pick
./.workspace/ralph.sh 3                    # let it work
```

The `ready-for-agent` label is the gate. The loop only touches tickets carrying it, so nothing runs
without you having blessed it first.

**The grilling step is not optional ceremony.** A fresh agent executes a ticket literally, at machine
speed, with nobody to ask. Everything that makes the output good is decided before the loop starts,
which is why the pipeline exists and why the board is where the day begins. You can skip it and hand-write
tickets with `bd create --title="..."` — the loop does not care — but the ticket is the whole
specification, and a vague one is the most expensive thing you can hand it.

Write **fewer, fatter tickets** than feels natural: every ticket pays a full cold start, so a
200-line ticket is mostly overhead. See the skill for the numbers.

## Verify before you trust it

A closed ticket is a claim, not a fact. The loop is told not to claim a completion it did not
verify, which is exactly why it needs checking. After a run:

```bash
git log --oneline <default-branch>..HEAD   # what actually landed
cat .workspace/logs/<latest>.log           # what it did, and why
```

Then run your project's own verify command yourself.

## Credit

This is an integration of other people's work, and the interesting parts are theirs:

- The **Ralph** technique — an agent loop with a fresh context per iteration — is
  [Geoffrey Huntley's](https://ghuntley.com/ralph/).
- **beads** is [Steve Yegge's](https://github.com/gastownhall/beads).
- The authoring pipeline it hands off to — `grill-with-docs`, `to-spec`, `to-tickets`, `triage`,
  `tdd`, `code-review` — is [Matt Pocock's](https://github.com/mattpocock/skills).

What is mine is the wiring: the queue as the loop's memory, the guards, and the runbook.

Why things are the way they are is in [DECISIONS.md](DECISIONS.md).

## License

MIT

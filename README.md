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

By using this you accept the risk. See [LICENSE](LICENSE) — it is provided as is, with no warranty.

---

## What you need

| | |
|---|---|
| [Claude Code](https://claude.com/claude-code) | the agent the loop drives |
| [beads](https://github.com/gastownhall/beads) (`bd`) | the ticket queue |
| `git`, `jq` | |
| zsh or bash | fish works, with one manual step |

## Install

```bash
npx skills add galihpermana29/gp-loops --skill=gp-loop
```

Then, in Claude Code:

```
/gp-loop
```

With no workspace set up it routes you to the bootstrap, which checks what is missing, tells you how
to install it, and wires up the rest. It is idempotent — run it as often as you like.

## How it fits together

```
<workspace-root>/
├── .beads/          the queue
├── .workspace/      the loop: script, prompt, config docs
├── CONTEXT.md       shared glossary (optional, generated as a starter)
├── docs/adr/        architecture decisions (optional)
└── <repo>/ ...      one or more git repos
```

A workspace is either a folder holding several repos as siblings, or a single repo. Both work.

The daily shape:

```bash
bd create --title="..."                    # write a ticket
bd tag <id> repo:<name> ready-for-agent    # label it, open the gate
git checkout -b <branch>                   # the loop needs a non-default branch
./.workspace/ralph.sh --dry-run 3          # see what it would pick
./.workspace/ralph.sh 3                    # let it work
```

The `ready-for-agent` label is the gate. The loop only touches tickets carrying it, so nothing runs
without you having blessed it first.

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

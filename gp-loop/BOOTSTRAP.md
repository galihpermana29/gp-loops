# Bootstrap

Setting up a workspace, on a fresh machine or alongside one you already have.

Run [`bootstrap.sh`](bootstrap.sh) for the mechanical parts. It is idempotent, verifies each step,
and reports what it changed. The judgement calls below are what it deliberately leaves to you.

```bash
~/.claude/skills/gp-loop/bootstrap.sh <workspace-root>
~/.claude/skills/gp-loop/bootstrap.sh --check <workspace-root>   # report only
~/.claude/skills/gp-loop/bootstrap.sh --yes <workspace-root>     # don't prompt before installing skills
```

## 1. Binaries

```bash
brew install beads          # bd, the queue — github.com/gastownhall/beads
brew install beads_viewer   # bv, read-only TUI (optional)
npm i -g beads-ui           # bdui, the board you write and triage tickets on
```

`bootstrap.sh` checks for these and prints the install line for anything missing. It will not
install them for you: running someone else's package manager unannounced is not a thing a setup
script should do.

Verify: `bd version` prints a version.

## 2. Choose the workspace shape

A workspace is either **a folder holding several repos as siblings**, or **a single repo**. Both
work, and `ralph.sh` handles each.

```
<workspace-root>/
├── .beads/          the queue, discovered by every repo below it
├── .workspace/      tooling: ralph.sh, the prompt, config docs
├── CONTEXT.md       shared glossary
├── docs/adr/        decisions
└── <repo>/ ...      one or more git repos
```

**Put `.beads` at the workspace root, not inside `.workspace`.** `bd` walks up from the current
directory to find its database, and `.workspace` is a sibling of the repos rather than an ancestor
of them.

For a single-repo workspace, `.beads` and `.workspace` live *inside* that repo. The tooling is then
sitting in a repo somebody else pulls, which is why `bootstrap.sh` excludes it — without that, the
loop's clean-tree guard sees permanently untracked tooling and never runs.

## 3. Create the queue

```bash
cd <workspace-root>
bd init -p <prefix> --non-interactive --stealth --skip-agents
```

`--stealth` writes `.git/info/exclude` entries so beads files stay invisible to collaborators.
`--skip-agents` leaves any existing `CLAUDE.md` or `AGENTS.md` alone.

Pick a short prefix, and a different one per workspace. It is what tells you at a glance that a
ticket is in the queue you meant.

> If `bd init` reports "this workspace is already initialized" and names a path you did not expect,
> `BEADS_DIR` is set in your shell from another workspace. `env -u BEADS_DIR bd init ...` or open a
> fresh shell.

Verify: `bd where` from the workspace root prints `<workspace-root>/.beads`.

## 4. Run the bootstrap

```bash
~/.claude/skills/gp-loop/bootstrap.sh <workspace-root>
```

What it does, so you can undo one part without unpicking the rest:

- **Tooling.** Creates `.workspace/` from the template shipped with this skill: `ralph.sh`, the
  prompt, and the two config documents. Skipped if one already exists.
- **Shell resolution.** Adds a hook to `~/.zshrc` or `~/.bashrc` exporting `BEADS_DIR` from the
  nearest ancestor holding `.beads/config.yaml`, stopping before `$HOME`. This is what makes
  `bd ready` work from inside a repo, since `bd`'s own discovery stops at a git repo boundary. On
  fish, add the equivalent by hand.
- **Per-repo config.** Symlinks `docs/agents/issue-tracker.md` and `docs/agents/domain.md` to the
  canonical copies in `.workspace`, and adds `docs/agents/`, `.scratch/` and `AGENTS.md` to that
  repo's `.git/info/exclude`. One canonical file, no drift, nothing committed.
- **Starters.** Writes an `AGENTS.md` into each repo and a `CONTEXT.md` at the workspace root, if
  they are absent. Both are excluded from git, so they reach nobody until you decide otherwise.
  Commit them yourself once you have read them — most projects eventually want `AGENTS.md` shared.
- **`AGENTS.md`.** Offers to fill it in by reading the repo, for any repo whose copy is missing or
  still the empty skeleton. See below.
- **Skills.** Checks the six the workflow uses and offers to install the missing ones.

Verify: `bd ready` works from inside a repo, and `git status` in that repo is unchanged.

### Generating `AGENTS.md`

The starter is a skeleton of empty sections, and an empty one is close to useless: the loop's prompt
tells every iteration to *"follow the conventions in this repo's `AGENTS.md`"*, so a blank file makes
that a silent no-op and the agent invents conventions for a codebase it has never seen.

So the bootstrap offers to write a real one, by reading the repo. It takes a minute or two per repo,
and it is skipped entirely under `--check`.

Two things about how it runs:

- **The generator cannot write anything.** It runs with `--allowed-tools "Read,Glob,Grep"` and prints
  to stdout; the bootstrap writes the file. Setup stays well clear of the permissions trade the loop
  itself asks you to make.
- **It is forbidden from inventing a verify command.** It may only name commands it actually found in
  `package.json`, a `Makefile` or the equivalent, and must say plainly when the project has no test
  suite rather than dressing a typecheck up as one. A fabricated verify command would be the worst
  possible outcome, because the loop gates its completion promise on that command exiting zero.

**Read what it produces before relying on it.** It is a well-informed first draft, not a specification
of your house style, and the conventions section is where it is most likely to overreach. It lands
git-excluded like the starter, so nothing reaches your collaborators until you commit it.

## 5. The skills

The loop itself needs two:

```bash
npx skills add mattpocock/skills --skill=code-review   # required — the loop refuses to start without it
npx skills add mattpocock/skills --skill=tdd           # optional — shapes how work is approached
```

`code-review` is not negotiable. The prompt tells every iteration to review its own work before
promising it is done; without the skill that instruction is a silent no-op and the loop ships
unreviewed code while reporting success.

The authoring pipeline needs four more. You can skip these and write tickets by hand:

```bash
npx skills add mattpocock/skills --skill=grill-with-docs
npx skills add mattpocock/skills --skill=to-spec
npx skills add mattpocock/skills --skill=to-tickets
npx skills add mattpocock/skills --skill=triage
```

They install user-scoped, so they load in every repo on the machine with no per-repo step.

Verify: `/gp-loop` appears in the skill list.

## 6. Workspace orientation

Write a `CLAUDE.md` at the workspace root covering:

- a repo map, so an agent can decide which repo a change belongs in
- how the repos interconnect, especially which one owns each API contract
- an `## Agent skills` section naming the queue, the `repo:` label convention, the triage labels,
  and where the glossary lives

An agent starting a fresh context reads this first. It is the difference between the loop knowing
where to work and guessing.

## 7. Prove it end to end

Before trusting the loop, run one small ticket through it.

1. Create a ticket with a mechanically checkable outcome.
2. Label it `repo:<name>` and `ready-for-agent`.
3. Prepare a throwaway branch in that repo.
4. `./.workspace/ralph.sh --dry-run 1`, confirm it names the right ticket, repo and branch.
5. `./.workspace/ralph.sh 1`.
6. Run the repo's verify command yourself, read `.workspace/logs/`, and confirm the ticket closed
   with a commit.
7. Delete the branch.

Done when every step passed on a ticket you were willing to throw away.

## Adding a second workspace

The binaries and the skills are machine-wide, so a second workspace needs only its own queue and its
own tooling:

```bash
cd <new-workspace-root>
bd init -p <different-prefix> --non-interactive --stealth --skip-agents
~/.claude/skills/gp-loop/bootstrap.sh .
./.workspace/ralph.sh --dry-run 1     # expect: queue drained
```

Each workspace gets its own copy of the tooling from the template rather than a copy of another
workspace's. That matters: config documents copied between workspaces carry absolute paths, and a
workspace pointed at another workspace's glossary will quietly use the wrong vocabulary.

## Keeping it recoverable

The queue is Dolt-backed and versioned locally. For cross-machine durability, give it a Dolt remote
and `bd dolt push`.

If you change `ralph.sh` or the prompt for your own use, keep those changes somewhere you can
recover them — a private remote is enough. The template in this skill is the starting point, not a
backup of your edits.

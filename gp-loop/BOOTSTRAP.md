# Bootstrap

Setting up a workspace, on a fresh machine or alongside one you already have.

**This page is addressed to the agent.** If you are reading it because the user asked for `/gp-loop`,
you are the one who runs these steps. Do not print them for the user to copy: say what you are about
to do, then do it. Every command still surfaces as a permission prompt they approve, so showing your
work and doing the work are not in tension.

There are exactly two things only the user can decide: **which directory is the workspace**, and
**the ticket prefix**. Ask those. Everything else you can determine.

The whole flow is one command, run twice:

```bash
<skill-dir>/bootstrap.sh --check <workspace-root>   # find out what is missing, change nothing
<skill-dir>/bootstrap.sh <workspace-root>           # do it, prompting where a decision is needed
```

It is idempotent, verifies each step, and reports what it changed. Re-run it freely. `--yes` skips
the prompts and takes the defaults, which is useful in a scripted setup and wrong for a first run,
because the prefix deserves a moment's thought.

The sections below explain what each step does and why, so you can tell the user what they are
approving, and undo one part without unpicking the rest.

## 1. Binaries

```bash
brew install beads          # bd, the queue — github.com/gastownhall/beads
brew install beads_viewer   # bv, read-only TUI (optional)
npm i -g beads-ui           # bdui, an optional board for writing and triaging tickets
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

## 3. The queue

`bootstrap.sh` creates this. It asks for a prefix, suggesting one from the directory name, and runs:

```bash
(cd <workspace-root> && env -u BEADS_DIR bd init -p <prefix> --non-interactive --stealth --skip-agents)
```

`--stealth` writes `.git/info/exclude` entries so beads files stay invisible to collaborators.
`--skip-agents` leaves any existing `CLAUDE.md` or `AGENTS.md` alone. `env -u BEADS_DIR` matters
because the shell hook exports it from whichever workspace you last stood in, and `bd` would
otherwise report that this one is "already initialized" while naming a path you did not expect.

The prefix is worth a moment. It is what tells you at a glance that a ticket belongs to the queue you
meant, so use a different one per workspace. The suggestion is initials for a hyphenated directory
name and the first few letters otherwise — fine to accept, better to choose.

Verify: `bd where` from the workspace root prints `<workspace-root>/.beads`.

## 4. What the bootstrap does

Beyond the queue above, in the order it reports them — so you can tell the user what they are
approving, and undo one part without unpicking the rest:

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
npx skills add mattpocock/skills --skill=code-review -g   # required — the loop refuses to start without it
npx skills add mattpocock/skills --skill=tdd -g           # optional — shapes how work is approached
```

`code-review` is not negotiable. The prompt tells every iteration to review its own work before
promising it is done; without the skill that instruction is a silent no-op and the loop ships
unreviewed code while reporting success.

The authoring pipeline needs four more. You can skip these and write tickets by hand:

```bash
npx skills add mattpocock/skills --skill=grill-with-docs -g
npx skills add mattpocock/skills --skill=to-spec -g
npx skills add mattpocock/skills --skill=to-tickets -g
npx skills add mattpocock/skills --skill=triage -g
```

**`-g` is doing real work in every one of those lines.** Without it `skills add` installs into the
*current project*, dropping `.agents/` and `skills-lock.json` into whatever repo you happened to be
standing in. Two consequences, both bad: the skill loads in that project only, and the repo is left
permanently untracked-dirty, which the loop refuses to run against. With `-g` they land in
`~/.agents/skills/`, symlinked into `~/.claude/skills/`, and load in every repo on the machine with
no per-repo step.

The installer targets around 75 different agents and symlinks into each one it finds. Expect it to
report a failure or two for agents that do not support global installation — harmless, as long as the
line for your own agent says installed.

Verify: `ls ~/.claude/skills/gp-loop` lists `SKILL.md`, and `/gp-loop` appears in the skill list.
If that directory is empty while `~/.agents/skills/gp-loop` exists, the files installed but the agent
was never linked to them — re-run naming it, `-a claude-code`. The installer prints `Done!` either
way, so this is worth actually checking rather than assuming.
Claude Code may need restarting before it notices a newly installed skill.

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
own tooling — which is the same one command, and it will ask for a prefix again:

```bash
<skill-dir>/bootstrap.sh <new-workspace-root>
cd <new-workspace-root> && ./.workspace/ralph.sh --dry-run 1   # expect: queue drained
```

Give it a **different** prefix from the first. That is the whole point of the prefix: to tell you at
a glance which queue a ticket came from.

Each workspace gets its own copy of the tooling from the template rather than a copy of another
workspace's. That matters: config documents copied between workspaces carry absolute paths, and a
workspace pointed at another workspace's glossary will quietly use the wrong vocabulary.

## Keeping it up to date

Two things go stale, in two different ways, and updating one does not update the other.

### The skill

The install is a snapshot. Nothing links it to the repository, so merges upstream reach you only when
you ask:

```bash
npx skills update gp-loop -g          # alias: upgrade
```

### The workspace

This is the one that surprises people. `bootstrap.sh` **copies** the template into `.workspace/` and
then skips any workspace that already has one — which is what makes re-running it safe, and also what
makes the copy permanent. A workspace set up months ago is still running the `ralph.sh` it was born
with, no matter how many times you update the skill.

The four files are not the same kind of thing, so they do not get the same treatment:

| file | what it is | on update |
|---|---|---|
| `ralph.sh` | the loop itself | **replace** — this is the tool |
| `ralph-prompt.md` | what each iteration is told | **replace** — this is the tool |
| `issue-tracker-beads.md` | your queue's conventions | **keep** — you customised this |
| `domain-workspace.md` | your glossary and repo map | **keep** — you customised this |

So a sync is: take the machinery, leave the configuration.

```bash
T=~/.claude/skills/gp-loop/template
W=<workspace>/.workspace

cp -r "$W" "$W.backup"                       # the config docs are not recoverable elsewhere
cp "$T/ralph.sh" "$W/ralph.sh" && chmod +x "$W/ralph.sh"
cp "$T/ralph-prompt.md" "$W/ralph-prompt.md"

cd <workspace> && ./.workspace/ralph.sh --dry-run 1
```

Diff the two config documents against the template occasionally as well — not to overwrite them, but
because a structural change upstream is worth folding in by hand.

**Your queue is never involved.** `.beads/` and `.workspace/` are separate directories: one holds
tickets, the other holds tooling. Nothing in an update, a sync, or even removing the skill entirely
reads or writes the queue.

Worth doing after any upstream change that touches `ralph.sh`, because that is where the guards live.
`require_skills()` — the hard stop when `code-review` is missing — reached the template long after
the first workspaces were created, and none of them had it until they were synced.

## Keeping it recoverable

The queue is Dolt-backed and versioned locally. For cross-machine durability, give it a Dolt remote
and `bd dolt push`.

If you change `ralph.sh` or the prompt for your own use, keep those changes somewhere you can
recover them — a private remote is enough. The template in this skill is the starting point, not a
backup of your edits.

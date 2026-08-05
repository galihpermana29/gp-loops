#!/usr/bin/env bash
#
# bootstrap.sh - set up a workspace for the gp-loop workflow.
#
# Runs from the installed skill and creates the workspace, rather than the other
# way round: the skill is what you install, and a workspace is what it makes.
#
# Idempotent. Safe to re-run after adding a repo, changing machines, or updating
# the skill. It reports what it found, what it changed, and what is left for you.
#
# Usage:
#   ./bootstrap.sh [workspace-root]          # defaults to the current directory
#   ./bootstrap.sh --check [workspace-root]  # report only, change nothing
#   ./bootstrap.sh --sync [workspace-root]   # refresh tooling from the skill, keep config
#   ./bootstrap.sh --yes [workspace-root]    # do not prompt before installing skills
#
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SKILL_DIR/template"

CHECK_ONLY=false
ASSUME_YES=false
SYNC=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --check) CHECK_ONLY=true ;;
    --sync) SYNC=true ;;
    --yes|-y) ASSUME_YES=true ;;
    *) printf 'unknown flag: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done
ROOT="$(cd "${1:-$PWD}" && pwd)"
WS="$ROOT/.workspace"

pass() { printf '  \033[32mok\033[0m    %s\n' "$*"; }
did()  { printf '  \033[34mdid\033[0m   %s\n' "$*"; }
todo() { printf '  \033[33mtodo\033[0m  %s\n' "$*"; }
fail() { printf '  \033[31mfail\033[0m  %s\n' "$*"; }

echo "workspace: $ROOT"
$CHECK_ONLY && echo "(check only, nothing will be changed)"

# --- 1. binaries ------------------------------------------------------------
echo
echo "binaries"
# bd is installed rather than auto-installed: running someone else's package
# manager unannounced is not a thing a setup script should do.
command -v bd   >/dev/null && pass "bd $(bd version 2>/dev/null | head -1)" || todo "bd missing:    brew install beads   (see github.com/gastownhall/beads)"
command -v git  >/dev/null && pass "git"  || fail "git missing"
command -v jq   >/dev/null && pass "jq"   || todo "jq missing:    brew install jq"
command -v bv   >/dev/null && pass "bv (optional, read-only TUI)"   || todo "bv missing:    brew install beads_viewer"
command -v bdui >/dev/null && pass "bdui (the board you write tickets on)"  || todo "bdui missing:  npm i -g beads-ui"

# --- 2. the queue -----------------------------------------------------------
# Created here rather than left as an instruction to paste. The prefix is the
# one real decision - it is what tells you at a glance which workspace a ticket
# belongs to - so it is asked for rather than assumed, and everything else about
# the command is knowable from where we are standing.
#
# `bd init` itself is not a package manager, so this does not contradict the
# rule about installing binaries unannounced: it creates a database inside a
# directory the user just pointed us at.

# A short, memorable default: initials for a hyphenated name, otherwise the
# first few letters. Only ever a suggestion.
suggest_prefix() {
  local base="$1" out
  if [[ "$base" == *-* ]]; then
    out=$(awk -F- '{for(i=1;i<=NF;i++) printf "%s", substr($i,1,1)}' <<<"$base")
  else
    out=${base:0:3}
  fi
  out=$(tr -cd '[:alnum:]' <<<"$out" | tr '[:upper:]' '[:lower:]')
  printf '%s' "${out:-ws}"
}

echo
echo "queue"
if [[ -f "$ROOT/.beads/config.yaml" ]]; then
  pass ".beads at the workspace root"
elif $CHECK_ONLY; then
  todo "no queue yet; would create one (you will be asked for a prefix)"
elif ! command -v bd >/dev/null; then
  todo "no queue, and bd is not installed yet - install it, then re-run this"
else
  DEFAULT_PREFIX=$(suggest_prefix "$(basename "$ROOT")")
  PREFIX="$DEFAULT_PREFIX"
  if ! $ASSUME_YES; then
    printf '  Ticket prefix for this workspace, so its IDs read %s-1, %s-2 [%s]: ' \
      "$DEFAULT_PREFIX" "$DEFAULT_PREFIX" "$DEFAULT_PREFIX"
    read -r reply </dev/tty || reply=""
    [[ -n "$reply" ]] && PREFIX=$(tr -cd '[:alnum:]' <<<"$reply" | tr '[:upper:]' '[:lower:]')
  fi
  # BEADS_DIR is unset for this call only. The shell hook exports it from
  # whichever workspace you last stood in, and bd would otherwise report that
  # this one is "already initialized" while naming a path you did not expect.
  if (cd "$ROOT" && env -u BEADS_DIR bd init -p "$PREFIX" \
        --non-interactive --stealth --skip-agents >/dev/null 2>&1); then
    did "created the queue, prefix $PREFIX (tickets will be ${PREFIX}-1, ${PREFIX}-2, ...)"
  else
    fail "bd init failed; run it yourself to see why:"
    printf '        (cd %s && env -u BEADS_DIR bd init -p %s --non-interactive --stealth --skip-agents)\n' \
      "$ROOT" "$PREFIX"
  fi
fi

# --- 3. the tooling ---------------------------------------------------------
# The template ships with the skill, so a workspace is created from it rather
# than copied out of somebody else's machine.
#
# The four files are not the same kind of thing, and that is the whole reason a
# plain re-copy is wrong. MACHINERY is the tool: replacing it is how a workspace
# receives a fix, and nobody is expected to have edited it. CONFIG carries the
# workspace's own paths, repo names and glossary - overwriting that destroys the
# customisation the design asks for. So drift is reported for both and only
# MACHINERY is ever written.
MACHINERY=(ralph.sh ralph-prompt.md)
CONFIG=(issue-tracker-beads.md domain-workspace.md)

# Lines differing between the shipped template and the workspace's copy.
drift_lines() {
  local f="$1"
  [[ -f "$WS/$f" ]] || { printf 'missing'; return; }
  diff "$TEMPLATE/$f" "$WS/$f" 2>/dev/null | grep -c '^[<>]' || true
}

echo
echo "tooling"
if [[ ! -f "$WS/ralph.sh" ]]; then
  if $CHECK_ONLY; then
    todo ".workspace missing; would be created from the skill's template"
  else
    mkdir -p "$WS"
    cp "$TEMPLATE"/ralph.sh "$TEMPLATE"/ralph-prompt.md \
       "$TEMPLATE"/issue-tracker-beads.md "$TEMPLATE"/domain-workspace.md "$WS/"
    chmod +x "$WS/ralph.sh"
    did "created .workspace from the skill's template"
  fi
else
  # A workspace created before a skill update keeps the tooling it was born
  # with - `bd`'s guards included - unless something says so. This is that.
  stale=()
  for f in "${MACHINERY[@]}"; do
    [[ "$(drift_lines "$f")" != "0" ]] && stale+=("$f")
  done

  if ((${#stale[@]} == 0)); then
    pass ".workspace present, tooling matches the skill"
  elif $SYNC && ! $CHECK_ONLY; then
    backup="$WS.backup-$(date +%Y%m%d-%H%M%S)"
    cp -r "$WS" "$backup"
    did "backed up .workspace to $(basename "$backup")"
    for f in "${stale[@]}"; do
      cp "$TEMPLATE/$f" "$WS/$f"
      did "refreshed $f from the skill"
    done
    chmod +x "$WS/ralph.sh"
  else
    for f in "${stale[@]}"; do
      todo "$f is $(drift_lines "$f") lines out of step with the skill"
    done
    todo "run with --sync to refresh the tooling (your config docs are left alone)"
  fi

  # Never rewritten, only reported: a structural change upstream is worth
  # folding in by hand, and the differences are usually the point of the file.
  for f in "${CONFIG[@]}"; do
    d=$(drift_lines "$f")
    [[ "$d" == "0" || "$d" == "missing" ]] && continue
    pass "$f differs from the template by $d lines - yours, left alone"
  done
fi

# --- 4. shell resolution ----------------------------------------------------
# bd stops discovery at a git repo boundary, so a workspace-level queue is
# invisible from inside a repo. Resolve it by walking the filesystem instead.
echo
echo "shell"
MARKER="_beads_workspace()"
case "$(basename "${SHELL:-}")" in
  zsh)  RC="$HOME/.zshrc" ;;
  bash) RC="$HOME/.bashrc" ;;
  *)    RC="" ;;
esac

if [[ -z "$RC" ]]; then
  todo "unrecognised shell (${SHELL:-unset}); add a hook exporting BEADS_DIR from the nearest ancestor holding .beads/config.yaml"
elif grep -qF "$MARKER" "$RC" 2>/dev/null; then
  pass "hook already in $(basename "$RC")"
elif $CHECK_ONLY; then
  todo "hook missing from $(basename "$RC")"
elif [[ "$RC" == *".zshrc" ]]; then
  cat >>"$RC" <<'HOOK'

# beads: resolve the queue from the nearest beads workspace above $PWD,
# ignoring git repo boundaries (bd's own discovery stops at a repo root).
# config.yaml is the marker: ~/.beads holds only bd telemetry and must not match.
_beads_workspace() {
  local d="$PWD"
  while [[ -n "$d" && "$d" != "/" && "$d" != "$HOME" ]]; do
    if [[ -f "$d/.beads/config.yaml" ]]; then export BEADS_DIR="$d/.beads"; return; fi
    d="${d:h}"
  done
  unset BEADS_DIR
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _beads_workspace
_beads_workspace
HOOK
  did "added hook to ~/.zshrc (open a new shell to pick it up)"
else
  cat >>"$RC" <<'HOOK'

# beads: resolve the queue from the nearest beads workspace above $PWD,
# ignoring git repo boundaries (bd's own discovery stops at a repo root).
_beads_workspace() {
  local d="$PWD"
  while [[ -n "$d" && "$d" != "/" && "$d" != "$HOME" ]]; do
    if [[ -f "$d/.beads/config.yaml" ]]; then export BEADS_DIR="$d/.beads"; return; fi
    d="$(dirname "$d")"
  done
  unset BEADS_DIR
}
PROMPT_COMMAND="_beads_workspace${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
_beads_workspace
HOOK
  did "added hook to ~/.bashrc (open a new shell to pick it up)"
fi

# --- 5. per-repo config and starters ----------------------------------------
# Starters are written excluded from git rather than committed: putting a file
# into somebody's project on install is a surprising thing for a tool to do.
# Commit them yourself once you have read them.
echo
echo "repos"
wire_repo() {
  local d="$1" up="$2"
  mkdir -p "$d/docs/agents"
  ln -sfn "$up/.workspace/issue-tracker-beads.md" "$d/docs/agents/issue-tracker.md"
  ln -sfn "$up/.workspace/domain-workspace.md"    "$d/docs/agents/domain.md"
  [[ -e "$d/AGENTS.md" ]] || { cp "$TEMPLATE/starters/AGENTS.md" "$d/AGENTS.md"; did "$(basename "$d"): wrote a starter AGENTS.md"; }
  for pat in 'docs/agents/' '.scratch/' 'AGENTS.md'; do
    grep -qxF "$pat" "$d/.git/info/exclude" 2>/dev/null || echo "$pat" >>"$d/.git/info/exclude"
  done
}

wired=0 skipped=0
REPOS=()
for d in "$ROOT"/*/; do
  repo="$(basename "$d")"
  [[ "$repo" == ".workspace" ]] && continue
  [[ -d "$d/.git" ]] || continue
  REPOS+=("${d%/}")
  if $CHECK_ONLY; then
    [[ -r "$d/docs/agents/issue-tracker.md" ]] && wired=$((wired+1)) || skipped=$((skipped+1))
    continue
  fi
  wire_repo "$d" "../../.."
  [[ -r "$d/docs/agents/issue-tracker.md" ]] && wired=$((wired+1)) || fail "$repo symlink is broken"
done

# A single-repo workspace is its own repo: the tooling lives inside it and must
# be excluded, or the loop's clean-tree guard never passes.
#
# --check counts this case separately rather than falling through to the loop
# above, which only walks subdirectories. Without it a single-repo workspace
# previewed as "0 repo(s) wired" in green, which reads as "this tool does not
# handle your project" for a shape it handles fine.
[[ -d "$ROOT/.git" ]] && REPOS+=("$ROOT")
if [[ -d "$ROOT/.git" ]] && $CHECK_ONLY; then
  if [[ -r "$ROOT/docs/agents/issue-tracker.md" ]]; then wired=$((wired+1)); else skipped=$((skipped+1)); fi
elif [[ -d "$ROOT/.git" ]]; then
  wire_repo "$ROOT" "../.."
  # CONTEXT.md belongs here as much as .workspace/ does. In a multi-repo
  # workspace it sits above every repo and no git tree sees it; in a single-repo
  # one it lands *inside* the repo, and an untracked starter is enough to trip
  # ralph.sh's clean-tree guard - so the loop would never run at all.
  for pat in '.workspace/' 'CONTEXT.md'; do
    grep -qxF "$pat" "$ROOT/.git/info/exclude" 2>/dev/null || echo "$pat" >>"$ROOT/.git/info/exclude"
  done
  did "excluded the tooling from the workspace root's own repo"
  wired=$((wired+1))
elif ! $CHECK_ONLY; then
  mkdir -p "$ROOT/docs/agents"
  ln -sfn ../../.workspace/issue-tracker-beads.md "$ROOT/docs/agents/issue-tracker.md"
  ln -sfn ../../.workspace/domain-workspace.md    "$ROOT/docs/agents/domain.md"
fi
# `skipped` only ever increments under --check, so it means "would be wired",
# never "failed to wire". Report it as work outstanding rather than as a pass.
if ((skipped > 0)); then
  todo "$wired repo(s) wired, $skipped would be"
else
  pass "$wired repo(s) wired"
fi

if [[ -e "$ROOT/CONTEXT.md" ]]; then
  pass "CONTEXT.md present"
elif $CHECK_ONLY; then
  todo "no CONTEXT.md; would write a starter"
else
  cp "$TEMPLATE/starters/CONTEXT.md" "$ROOT/CONTEXT.md"
  did "wrote a starter CONTEXT.md at the workspace root"
fi

# --- 6. AGENTS.md -----------------------------------------------------------
# The starter is a skeleton of empty sections, and the loop's prompt tells every
# iteration to "follow the conventions in this repo's AGENTS.md". An unfilled
# one makes that a silent no-op: the agent invents conventions for a codebase it
# has never seen. The verify command matters most of all, because the prompt
# gates its completion promise on that command exiting zero.
#
# So offer to fill it in by reading the repo. Claude runs with a read-only tool
# set and prints to stdout; this script writes the file. The generator is never
# given permission to touch the filesystem, which keeps setup well clear of the
# permissions trade the loop itself asks you to make.

# True when AGENTS.md is absent, or is still the untouched skeleton. Strips HTML
# comment blocks, then headings, fences and blank lines - what the starter is
# made of - and asks whether any prose or command survived.
#
# Two things this deliberately avoids, both of which shipped as bugs first:
# `${body//...}` to strip whitespace, which is quadratic in bash 3.2 and hangs
# outright on a thorough AGENTS.md; and piping into `grep -q`, whose early exit
# SIGPIPEs the upstream sed and, under `set -o pipefail`, reports every filled
# file as empty. sed has already dropped blank lines, so -z settles it.
agents_unfilled() {
  local f="$1" body
  [[ -r "$f" ]] || return 0
  body=$(awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$f" \
    | sed -E '/^[[:space:]]*$/d; /^[[:space:]]*#/d; /^[[:space:]]*```/d')
  [[ -z "$body" ]]
}

AGENTS_PROMPT='Read this repository and write its AGENTS.md: the file a coding agent reads to learn how the project is built and what "done" means here.

Use exactly these sections: ## Commands, ## Stack, ## Conventions, ## Testing, ## Domain.

Rules:
- Only name commands that actually exist. Read package.json scripts, Makefile, justfile, or the equivalent, and quote them verbatim. Never guess a command, and never include one because it is conventional.
- Under ## Commands, mark the verify command explicitly - the single command that proves a change is good. If the project has no test suite, say so in one plain sentence and name the strongest check that does exist (a typecheck, a lint, a build). Do not present a weaker check as if it were a test suite.
- Under ## Conventions, describe only patterns you can see repeated in the code: how errors are handled, how modules are laid out, naming, anything counterintuitive. Do not invent house style.
- Under ## Testing, describe the framework and where tests live. If there are none, say that plainly.
- Keep ## Domain short, and point at the workspace CONTEXT.md rather than repeating it.

Be concise and concrete. Prefer omitting a section to padding it.

You have no write access and must not try to create or edit any file - the caller writes it for you.
Your entire response is the file. No preamble, no closing commentary, and no code fence wrapping the
whole thing (fenced blocks *inside* the file, such as the command list, are fine).'

# Claude tends to preface the file with a sentence, and sometimes wraps the whole
# thing in a ```markdown fence - most often when it wanted to write the file
# itself and had no permission to. Both were observed in testing even with the
# prompt asking for neither, so strip them here rather than trusting it.
#
# Fenced: take the block, keyed on the opening language tag and the *last* bare
# fence, so the ```bash block inside ## Commands survives. Unfenced: start at the
# first heading, since the file always opens with one and prose never precedes it.
# Every line reads from a here-string rather than a pipe. `grep ... | head -1`
# looks natural here and is the same SIGPIPE-under-pipefail trap as above: head
# exits on the first match, grep dies writing to a closed pipe, and the whole
# substitution fails under `set -e`. awk on a here-string has no such edge.
unwrap_markdown() {
  local raw="$1" open close total first
  open=$(awk '/^```markdown[[:space:]]*$/{print NR; exit}' <<<"$raw")
  if [[ -n "$open" ]]; then
    total=$(awk 'END{print NR}' <<<"$raw")
    close=$(awk '/^```[[:space:]]*$/{n=NR} END{if(n) print n}' <<<"$raw")
    [[ -n "$close" && "$close" -gt "$open" ]] || close=$((total + 1))
    awk -v s="$((open + 1))" -v e="$((close - 1))" 'NR>=s && NR<=e' <<<"$raw"
    return
  fi
  first=$(awk '/^#/{print NR; exit}' <<<"$raw")
  if [[ -n "$first" && "$first" -gt 1 ]]; then
    awk -v s="$first" 'NR>=s' <<<"$raw"
  else
    printf '%s\n' "$raw"
  fi
}

# Which repos would benefit. Collected first so the prompt is asked once.
NEEDS_AGENTS=()
for d in ${REPOS+"${REPOS[@]}"}; do
  agents_unfilled "$d/AGENTS.md" && NEEDS_AGENTS+=("$d")
done

echo
echo "AGENTS.md"
if ((${#NEEDS_AGENTS[@]} == 0)); then
  pass "every repo has a filled-in AGENTS.md"
elif $CHECK_ONLY; then
  for d in "${NEEDS_AGENTS[@]}"; do
    if [[ -e "$d/AGENTS.md" ]]; then
      todo "$(basename "$d"): AGENTS.md is still the empty starter"
    else
      todo "$(basename "$d"): no AGENTS.md"
    fi
  done
elif ! command -v claude >/dev/null; then
  todo "claude not on PATH; fill in AGENTS.md by hand in: ${NEEDS_AGENTS[*]##*/}"
else
  reply=n
  if $ASSUME_YES; then
    reply=y
  else
    printf '  Generate AGENTS.md for %d repo(s) by reading them with Claude? [y/N] ' "${#NEEDS_AGENTS[@]}"
    read -r reply </dev/tty || reply=n
  fi
  if [[ "$reply" == [yY]* ]]; then
    for d in "${NEEDS_AGENTS[@]}"; do
      name="$(basename "$d")"
      printf '  ...reading %s (a minute or two)\n' "$name"
      # The prompt goes in on stdin, not as an argument: `--allowed-tools` is
      # variadic, so a trailing argument is swallowed as another tool name and
      # claude exits complaining it was given no input.
      generated=$(cd "$d" && printf '%s' "$AGENTS_PROMPT" \
        | claude --print --allowed-tools "Read,Glob,Grep" 2>/dev/null || true)
      # A short answer means it errored, refused, or found nothing. The starter
      # is a better outcome than a truncated file that looks authoritative.
      if [[ ${#generated} -lt 200 ]]; then
        fail "$name: generation produced nothing usable, leaving the starter in place"
        continue
      fi
      unwrap_markdown "$generated" >"$d/AGENTS.md"
      did "$name: wrote AGENTS.md from the repo ($(wc -l <"$d/AGENTS.md" | tr -d ' ') lines) - read it before trusting it"
    done
  else
    todo "skipped; the loop will run against empty conventions until you fill these in"
  fi
fi

# --- 7. skills --------------------------------------------------------------
# code-review is not optional: the loop refuses to start without it, because the
# prompt tells every iteration to review its own work and a missing skill makes
# that instruction a silent no-op.
echo
echo "skills"
REQUIRED=(code-review tdd)
PIPELINE=(grill-with-docs to-spec to-tickets triage)
missing=()
for s in "${REQUIRED[@]}" "${PIPELINE[@]}"; do
  if [[ -e "$HOME/.claude/skills/$s" ]]; then pass "$s"; else missing+=("$s"); fi
done

if ((${#missing[@]})); then
  for s in "${missing[@]}"; do todo "$s missing"; done
  if $CHECK_ONLY; then
    :
  else
    install=false
    if $ASSUME_YES; then
      install=true
    else
      printf '\n  Install %d missing skill(s) from mattpocock/skills? [y/N] ' "${#missing[@]}"
      read -r reply </dev/tty || reply=""
      [[ "$reply" == [yY]* ]] && install=true
    fi
    if $install; then
      # -g installs user-level. Without it `skills add` defaults to the current
      # project, dropping .agents/ and skills-lock.json into the repo - which
      # leaves it permanently untracked, and the loop refuses a dirty tree. The
      # skills are machine-wide tooling anyway, not a dependency of one project.
      for s in "${missing[@]}"; do
        npx --yes skills add mattpocock/skills --skill="$s" -g && did "installed $s" || fail "could not install $s"
      done
    else
      todo "install them with:  npx skills add mattpocock/skills --skill=<name> -g"
    fi
  fi
fi

# --- 7. verify --------------------------------------------------------------
echo
echo "verify"
if [[ -x "$WS/ralph.sh" ]]; then
  if (cd "$ROOT" && ./.workspace/ralph.sh --dry-run 1 >/dev/null 2>&1); then
    pass "the loop runs"
  else
    todo "the loop does not run yet; try:  (cd $ROOT && ./.workspace/ralph.sh --dry-run 1)"
  fi
else
  todo "no ralph.sh yet"
fi

echo
echo "Next: write a ticket, label it repo:<name> and ready-for-agent, put the target"
echo "repo on a non-default branch, then ./.workspace/ralph.sh --dry-run 1"

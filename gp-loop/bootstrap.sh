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
#   ./bootstrap.sh --yes [workspace-root]    # do not prompt before installing skills
#
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SKILL_DIR/template"

CHECK_ONLY=false
ASSUME_YES=false
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --check) CHECK_ONLY=true ;;
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
command -v bdui >/dev/null && pass "bdui (optional, web board)"     || todo "bdui missing:  npm i -g beads-ui"

# --- 2. the queue -----------------------------------------------------------
echo
echo "queue"
if [[ -f "$ROOT/.beads/config.yaml" ]]; then
  pass ".beads at the workspace root"
else
  todo "no queue yet:  (cd $ROOT && bd init -p <prefix> --non-interactive --stealth --skip-agents)"
fi

# --- 3. the tooling ---------------------------------------------------------
# The template ships with the skill, so a workspace is created from it rather
# than copied out of somebody else's machine.
echo
echo "tooling"
if [[ -f "$WS/ralph.sh" ]]; then
  pass ".workspace already present"
elif $CHECK_ONLY; then
  todo ".workspace missing; would be created from the skill's template"
else
  mkdir -p "$WS"
  cp "$TEMPLATE"/ralph.sh "$TEMPLATE"/ralph-prompt.md \
     "$TEMPLATE"/issue-tracker-beads.md "$TEMPLATE"/domain-workspace.md "$WS/"
  chmod +x "$WS/ralph.sh"
  did "created .workspace from the skill's template"
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
for d in "$ROOT"/*/; do
  repo="$(basename "$d")"
  [[ "$repo" == ".workspace" ]] && continue
  [[ -d "$d/.git" ]] || continue
  if $CHECK_ONLY; then
    [[ -r "$d/docs/agents/issue-tracker.md" ]] && wired=$((wired+1)) || skipped=$((skipped+1))
    continue
  fi
  wire_repo "$d" "../../.."
  [[ -r "$d/docs/agents/issue-tracker.md" ]] && wired=$((wired+1)) || fail "$repo symlink is broken"
done

# A single-repo workspace is its own repo: the tooling lives inside it and must
# be excluded, or the loop's clean-tree guard never passes.
if [[ -d "$ROOT/.git" ]] && ! $CHECK_ONLY; then
  wire_repo "$ROOT" "../.."
  grep -qxF '.workspace/' "$ROOT/.git/info/exclude" 2>/dev/null || echo '.workspace/' >>"$ROOT/.git/info/exclude"
  did "excluded the tooling from the workspace root's own repo"
  wired=$((wired+1))
elif ! $CHECK_ONLY; then
  mkdir -p "$ROOT/docs/agents"
  ln -sfn ../../.workspace/issue-tracker-beads.md "$ROOT/docs/agents/issue-tracker.md"
  ln -sfn ../../.workspace/domain-workspace.md    "$ROOT/docs/agents/domain.md"
fi
if ((skipped > 0)); then pass "$wired repo(s) wired, $skipped unwired"; else pass "$wired repo(s) wired"; fi

if [[ -e "$ROOT/CONTEXT.md" ]]; then
  pass "CONTEXT.md present"
elif $CHECK_ONLY; then
  todo "no CONTEXT.md; would write a starter"
else
  cp "$TEMPLATE/starters/CONTEXT.md" "$ROOT/CONTEXT.md"
  did "wrote a starter CONTEXT.md at the workspace root"
fi

# --- 6. skills --------------------------------------------------------------
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
      for s in "${missing[@]}"; do
        npx --yes skills add mattpocock/skills --skill="$s" && did "installed $s" || fail "could not install $s"
      done
    else
      todo "install them with:  npx skills add mattpocock/skills --skill=<name>"
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

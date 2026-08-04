#!/usr/bin/env bash
#
# ralph.sh - canonical Ralph loop over the beads queue.
#
# Each iteration is a fresh `claude --print` process, so the context window is
# reset every time. All memory lives in beads and on disk. One bead per
# iteration.
#
# Usage:
#   ./ralph.sh [max_iterations]        # default 10
#   ./ralph.sh --dry-run [max]         # pick and report work, never invoke claude
#
set -euo pipefail

# Paths derive from this script's own location, so copying .workspace/ into
# another workspace needs no edits. The beads database lives at the workspace
# root, not in here: bd stops discovery at a git repo boundary, so a database
# inside .workspace would be invisible from the sibling repos.
WS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$WS")"
# Overridable so a variant prompt can be trialled against the same loop without
# forking the script. Unset, it is the production prompt.
PROMPT_FILE="${RALPH_PROMPT:-$WS/ralph-prompt.md}"
ATTEMPTS_FILE="$WS/.attempts"
LOG_DIR="$WS/logs"
QUEUE_LABEL="ready-for-agent"
MAX_ATTEMPTS=3

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi
MAX_ITERATIONS="${1:-10}"

mkdir -p "$LOG_DIR"
touch "$ATTEMPTS_FILE"

# The prompt tells every iteration to review its own work before promising it is
# done. If that skill is not installed the instruction is silently a no-op, and
# the loop ships unreviewed code while reporting success. Measured on one real
# feature, dropping the per-bead review let two functional defects reach the
# branch. So this is a hard stop rather than a warning: a missing skill is
# cheap to fix now and expensive to discover later.
#
# `tdd` only shapes how work is approached, so its absence is worth saying out
# loud but is not worth refusing over.
require_skills() {
  local missing=() s
  for s in code-review; do
    [[ -e "$HOME/.claude/skills/$s" ]] || missing+=("$s")
  done
  if ((${#missing[@]})); then
    printf 'gp-loop: required skill(s) not installed: %s\n' "${missing[*]}" >&2
    printf 'Install with:\n' >&2
    for s in "${missing[@]}"; do
      printf '  npx skills add mattpocock/skills --skill=%s\n' "$s" >&2
    done
    exit 1
  fi
  for s in tdd; do
    [[ -e "$HOME/.claude/skills/$s" ]] \
      || printf 'gp-loop: warning - %s is not installed; the loop will skip it\n' "$s" >&2
  done
}
require_skills

bdw() { bd -C "$ROOT" "$@"; }

# Without this the first `bd` call fails under `set -e` and the loop exits 1
# having printed nothing at all — which is what somebody sees when they run it
# before creating a queue, i.e. the most likely first run there is.
if [[ ! -f "$ROOT/.beads/config.yaml" ]]; then
  printf 'gp-loop: no beads queue at %s\n' "$ROOT" >&2
  printf 'Create one with:\n  (cd %s && bd init -p <prefix> --non-interactive --stealth --skip-agents)\n' "$ROOT" >&2
  exit 1
fi

log() { printf '%s | %s\n' "$(date '+%H:%M:%S')" "$*"; }

# Pull the repo:<name> label off a bead. Tries JSON first, falls back to the
# human-readable output, because the JSON summary shape omits labels.
bead_repo() {
  local id="$1" repo=""
  repo=$(bdw show "$id" --json 2>/dev/null \
    | jq -r '(if type=="array" then .[0] else . end) | (.labels // [])[]?' 2>/dev/null \
    | grep '^repo:' | head -1 | sed 's/^repo://' || true)
  if [[ -z "$repo" ]]; then
    repo=$(bdw show "$id" 2>/dev/null | grep -o 'repo:[A-Za-z0-9._-]*' | head -1 | sed 's/^repo://' || true)
  fi
  printf '%s' "$repo"
}

# An iteration that dies part-way — a dropped API connection, a crash — leaves
# its half-written edits in the tree. The dirty-tree guard then fires on the
# retry and hands the bead to a human, so a transient blip becomes a permanent
# demotion and the remaining attempts are spent doing nothing. Clear the debris
# so the retry starts from the same clean tree the first attempt did.
#
# Stashed rather than discarded: the guard guarantees the tree was clean before
# the iteration began, so everything here was written by the iteration and is
# unverified by definition — but "unverified" is not "worthless", and a stash
# entry costs nothing and stays recoverable.
stash_debris() {
  local id="$1" path="$2"
  [[ -z "$(git -C "$path" status --porcelain)" ]] && return 0
  local stamp
  stamp=$(date '+%Y-%m-%d %H:%M:%S')
  if git -C "$path" stash push -u -m "ralph debris: $id failed $stamp" >/dev/null 2>&1; then
    log "stashed partial work from $id (git -C $path stash list)"
  else
    log "WARNING: could not stash $id's partial work; the retry will hit the dirty-tree guard"
  fi
}

record_failure() {
  local id="$1" reason="$2"
  echo "$id" >>"$ATTEMPTS_FILE"
  bdw update "$id" --status open >/dev/null
  bdw update "$id" --append-notes "ralph: attempt failed - $reason" >/dev/null
}

hand_to_human() {
  local id="$1" reason="$2"
  if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN: would hand off $id -> ready-for-human ($reason)"
    return
  fi
  bdw update "$id" --add-label ready-for-human --remove-label "$QUEUE_LABEL" >/dev/null
  bdw update "$id" --status open >/dev/null
  bdw update "$id" --append-notes "ralph: handing to human - $reason" >/dev/null
  log "HANDOFF $id -> ready-for-human ($reason)"
}

for ((i = 1; i <= MAX_ITERATIONS; i++)); do
  id=$(bdw ready --label "$QUEUE_LABEL" --limit 1 --json 2>/dev/null | jq -r '.[0].id // empty')

  if [[ -z "$id" ]]; then
    log "queue drained: no beads labelled $QUEUE_LABEL are ready"
    exit 0
  fi

  attempts=$(grep -cxF "$id" "$ATTEMPTS_FILE" || true)
  if ((attempts >= MAX_ATTEMPTS)); then
    hand_to_human "$id" "$MAX_ATTEMPTS failed attempts"
    continue
  fi

  title=$(bdw show "$id" --json 2>/dev/null \
    | jq -r '(if type=="array" then .[0] else . end) | .title // ""')
  repo=$(bead_repo "$id")

  log "iteration $i/$MAX_ITERATIONS | $id | attempt $((attempts + 1))/$MAX_ATTEMPTS | $title"

  # --- guards -------------------------------------------------------------
  if [[ -z "$repo" ]]; then
    hand_to_human "$id" "no repo:<name> label, cannot decide where to work"
    continue
  fi
  # Two workspace shapes. A multi-repo workspace holds repos as siblings, so
  # work lives at $ROOT/$repo. A single-repo workspace IS the repo, so a bead
  # labelled with the root's own name works in $ROOT itself.
  if [[ -d "$ROOT/$repo/.git" ]]; then
    repo_path="$ROOT/$repo"
  elif [[ "$repo" == "$(basename "$ROOT")" && -d "$ROOT/.git" ]]; then
    repo_path="$ROOT"
  else
    hand_to_human "$id" "repo:$repo is not a git repo in this workspace"
    continue
  fi

  branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)
  # A repo with no origin has no origin/HEAD, and symbolic-ref exits 1 there,
  # which set -e would treat as fatal. Fall back to main.
  default_branch=$(git -C "$repo_path" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || true)
  default_branch="${default_branch:-main}"
  if [[ "$branch" == "$default_branch" || "$branch" == "main" || "$branch" == "master" ]]; then
    hand_to_human "$id" "$repo is on $branch; refusing to let an unattended loop commit to the default branch"
    continue
  fi
  if [[ -n "$(git -C "$repo_path" status --porcelain)" ]]; then
    hand_to_human "$id" "$repo has uncommitted changes; a loop commit would sweep them up"
    continue
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN: would work $id in $repo on branch $branch"
    continue
  fi

  # --- run ----------------------------------------------------------------
  bdw update "$id" --claim >/dev/null
  log "claimed $id, working in $repo ($branch)"

  stamp=$(date '+%Y%m%d-%H%M%S')
  logfile="$LOG_DIR/${stamp}-${id}.log"

  # The bead and its spec are inlined rather than left for the agent to fetch.
  # Every iteration starts with an empty context, so `bd show` plus a design-field
  # parse plus a spec read is a fixed tax paid before any work begins — and a
  # misparsed design pointer silently costs the whole iteration.
  bead_detail=$(bdw show "$id" 2>/dev/null || true)

  # The design field carries a spec path relative to the workspace root, among
  # other `·`-separated pointers. Pull the first .scratch/**/*.md out of it.
  spec_rel=$(printf '%s' "$bead_detail" \
    | grep -o '[A-Za-z0-9._/-]*\.scratch/[A-Za-z0-9._/-]*\.md' | head -1 || true)
  spec_body=""
  if [[ -n "$spec_rel" ]]; then
    for candidate in "$ROOT/$spec_rel" "$repo_path/$spec_rel"; do
      if [[ -f "$candidate" ]]; then
        spec_body=$(cat "$candidate")
        log "inlined spec $candidate ($(wc -l <"$candidate" | tr -d ' ') lines)"
        break
      fi
    done
    [[ -z "$spec_body" ]] && log "WARNING: design names $spec_rel but no such file; agent will work without it"
  fi

  prompt=$(
    cat "$PROMPT_FILE"
    printf '\n\n---\n\nThe bead you are working on this iteration is **%s** in repo **%s**.\nThe workspace root is `%s`, so `bd` means `bd -C %s`.\n' \
      "$id" "$repo" "$ROOT" "$ROOT"
    printf '\n## Your bead\n\n```\n%s\n```\n' "$bead_detail"
    if [[ -n "$spec_body" ]]; then
      printf '\n## Spec (%s)\n\n%s\n' "$spec_rel" "$spec_body"
    fi
  )

  set +e
  output=$(cd "$repo_path" && printf '%s' "$prompt" \
    | claude --dangerously-skip-permissions --print 2>&1)
  claude_exit=$?
  set -e

  printf '%s\n' "$output" >"$logfile"

  if ((claude_exit != 0)); then
    stash_debris "$id" "$repo_path"
    # A dropped connection is not the bead's fault. Counting it would let a
    # flaky network spend the retry budget meant for genuine failures and park
    # a ticket that was never broken. The iteration is still spent; the strike
    # is not.
    if grep -qE 'API Error.*(ConnectionRefused|ETIMEDOUT|ECONNRESET|ENOTFOUND|fetch failed)' "$logfile"; then
      bdw update "$id" --status open >/dev/null
      log "TRANSIENT $id: network error, attempt not counted"
      continue
    fi
    record_failure "$id" "claude exited $claude_exit (see $logfile)"
    log "FAILED $id: claude exited $claude_exit"
    continue
  fi

  if grep -q '<promise>COMPLETE</promise>' <<<"$output"; then
    log "DONE $id (log: $logfile)"
    # A promise is only honest if the iteration also committed. Anything left
    # behind means it verified, promised, and then failed to record — so the
    # tree must still be cleared, or the next bead inherits work it did not do.
    stash_debris "$id" "$repo_path"
  else
    stash_debris "$id" "$repo_path"
    record_failure "$id" "no completion promise emitted (see $logfile)"
    log "INCOMPLETE $id: no promise, returned to queue"
  fi

  sleep 2
done

log "reached max iterations ($MAX_ITERATIONS); stopping"

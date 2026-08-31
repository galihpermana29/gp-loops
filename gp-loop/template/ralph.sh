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
# Environment:
#   RALPH_PROMPT   override the prompt file
#   RALPH_MODEL    model for every iteration; unset inherits your Claude Code
#                  default, which is worth checking - see costs.tsv
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
# One row per iteration. The loop's own cost was the one thing it never measured,
# which is how a month of runs can end in a session limit with nothing to point
# at. Every claim about what the loop costs should be checkable from this file.
COSTS_FILE="$WS/costs.tsv"
QUEUE_LABEL="ready-for-agent"
MAX_ATTEMPTS=3

# Unset by default rather than pinned. Pinning a cheaper model here would change
# the quality of everybody's loop on upgrade, silently and without evidence;
# costs.tsv is the evidence, and `RALPH_MODEL=sonnet` is the fix once you have
# looked at it. Note that unset means the loop inherits whatever your Claude Code
# default is - if that is opus, every iteration is an opus iteration.
MODEL="${RALPH_MODEL:-}"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  shift
fi
MAX_ITERATIONS="${1:-10}"

mkdir -p "$LOG_DIR"
touch "$ATTEMPTS_FILE"

# The loop no longer runs `/code-review`, so it no longer refuses to start
# without it. Review moved to land time, once per branch, because the loop
# commits per bead and reviewing per bead paid for the same two agents on every
# one - sixteen times on a sixteen-bead epic, for a diff that lands as one.
# `bootstrap.sh --check` still reports the skill, since the workflow needs it,
# just later and driven by a human.
#
# `tdd` shapes how work is approached and spawns no subagents, so it is free and
# stays. Its absence is worth saying out loud but not worth refusing over.
require_skills() {
  local s
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

# One tab-separated row per iteration, appended.
#
# `subagents` is the column worth watching. The loop's own prompt tells each
# iteration to delegate its codebase search, and nothing ever counted how wide
# that went - so a single bead could quietly fan out into several full-repo
# sweeps, each paying its own cold start. `models` is here because an unset
# RALPH_MODEL inherits your Claude Code default, and finding out from this file
# that every iteration ran on opus is the whole point.
#
# Costs nothing when the envelope is unparseable (a crash before JSON): the row
# is written with empty fields rather than skipped, so the iteration still shows
# up and the gap is visible.
record_cost() {
  local id="$1" envelope="$2"

  if [[ ! -s "$COSTS_FILE" ]]; then
    printf 'when\tbead\tattempt\tcost_usd\tin\tout\tcache_read\tcache_write\tsubagents\tturns\tapi_ms\tmodels\n' \
      >"$COSTS_FILE"
  fi

  jq -r --arg when "$(date '+%Y-%m-%d %H:%M:%S')" --arg bead "$id" --arg attempt "$((attempts + 1))" '
    [ $when, $bead, $attempt,
      (.total_cost_usd // "" | tostring),
      (.usage.input_tokens // "" | tostring),
      (.usage.output_tokens // "" | tostring),
      (.usage.cache_read_input_tokens // "" | tostring),
      (.usage.cache_creation_input_tokens // "" | tostring),
      (.subagent_stats.spawned // "" | tostring),
      (.num_turns // "" | tostring),
      (.duration_api_ms // "" | tostring),
      ((.modelUsage // {}) | keys | join(","))
    ] | @tsv' <<<"$envelope" 2>/dev/null >>"$COSTS_FILE" \
    || printf '%s\t%s\t%s\t\t\t\t\t\t\t\t\t\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$id" "$((attempts + 1))" >>"$COSTS_FILE"

  local cost subagents models
  cost=$(jq -r '.total_cost_usd // "?"' <<<"$envelope" 2>/dev/null || echo '?')
  subagents=$(jq -r '.subagent_stats.spawned // "?"' <<<"$envelope" 2>/dev/null || echo '?')
  models=$(jq -r '(.modelUsage // {}) | keys | join(",")' <<<"$envelope" 2>/dev/null || echo '?')
  log "cost \$$cost | subagents $subagents | models ${models:-?}"
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

  # Sits beside the spec so it travels with the epic it describes. Absent is
  # fine: the prompt falls back to searching the repo from scratch, which is what
  # every iteration used to do.
  orientation_body=""
  if [[ -n "$spec_rel" ]]; then
    for candidate in "$ROOT/$(dirname "$spec_rel")/orientation.md" \
      "$repo_path/$(dirname "$spec_rel")/orientation.md"; do
      if [[ -f "$candidate" ]]; then
        orientation_body=$(cat "$candidate")
        log "inlined orientation $candidate ($(wc -l <"$candidate" | tr -d ' ') lines)"
        break
      fi
    done
  fi

  prompt=$(
    cat "$PROMPT_FILE"
    printf '\n\n---\n\nThe bead you are working on this iteration is **%s** in repo **%s**.\nThe workspace root is `%s`, so `bd` means `bd -C %s`.\n' \
      "$id" "$repo" "$ROOT" "$ROOT"
    printf '\n## Your bead\n\n```\n%s\n```\n' "$bead_detail"
    if [[ -n "$spec_body" ]]; then
      printf '\n## Spec (%s)\n\n%s\n' "$spec_rel" "$spec_body"
    fi
    if [[ -n "$orientation_body" ]]; then
      printf '\n## Orientation\n\n%s\n' "$orientation_body"
    else
      printf '\n## Orientation\n\nNone written for this epic. Search the codebase from scratch, as section 2 describes.\n'
    fi
  )

  set +e
  # JSON rather than text so the iteration reports what it cost. The completion
  # promise now lives in `.result`, so it is extracted rather than grepped out of
  # the whole envelope - grepping the raw JSON would also match the promise if the
  # agent merely quoted it while explaining itself.
  output=$(cd "$repo_path" && printf '%s' "$prompt" \
    | claude --dangerously-skip-permissions --print --output-format json \
      ${MODEL:+--model "$MODEL"} 2>&1)
  claude_exit=$?
  set -e

  printf '%s\n' "$output" >"$logfile"

  # Absent on a crash, and on any path where claude died before emitting JSON.
  result_text=$(jq -r '.result // empty' <<<"$output" 2>/dev/null || true)
  record_cost "$id" "$output"

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

  if grep -q '<promise>COMPLETE</promise>' <<<"$result_text"; then
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

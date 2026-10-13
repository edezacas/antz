#!/usr/bin/env bash
#
# eval/run.sh — measures antz's repair loop.
#
# The loop lives in prompts/antz.md, not in code: it is model judgement applied
# to state on disk. So it is not exercised by unit asserts but by provoking a
# verification failure and reading which agent the repair is routed to. It is
# the part of the flow a normal run almost never touches, because almost nothing
# ever fails.
#
# This is not a test, it is an eval: the verdict depends on model judgement, so
# the result is a rate over N runs, not a boolean. It costs money and minutes,
# and one green run proves nothing.
#
#   ./run.sh                # the four scenarios, once each
#   ./run.sh A B            # only those
#   RUNS=5 ./run.sh         # five repetitions of each
#
# A/B/C/D seed .antz/ with the plan already complete, so /antz enters at step 5
# (verification) instead of recon: about 3 dispatches per run.
#
#   A  test faithful to the criteria, implementation that violates them  -> implementation at fault
#   B  implementation faithful, test that contradicts the criteria      -> test at fault
#   C  A, plus a watcher that re-injects the fault every 2 s             -> the 3-attempt cap
#   D  green tests, correct behaviour, and a needless abstraction        -> shape at fault
#   N  two packages with different runners, a fixed plan with rich criteria
#   H  N, with a recon that already names the exact commands
#   S  one task whose criteria cannot both hold, so nothing can converge -> the stopped task
#
# The dispatch totals in usage.tsv hide the agent: a `chains` call of eight is one
# row. agents.tsv keeps one row per agent run, from the same session by a second
# path, so a change that moves one role and not another is visible — and it is
# checked against the dispatch totals, which must agree.
#
# M measures something else: it seeds recon, spec and a fixed plan, so /antz
# enters at step 4 with the same tasks every run (tests -> verify), and it gives
# the sandbox a realistic AGENTS.md so the shared context a caching change
# targets is a measurable share of the tokens. It records what the subagents
# spent in out/usage.tsv; TAG=before|after labels the phase, so the same scenario
# is run either side of a change. Its four tasks are independent, so step 4 must
# dispatch them together: M also asserts that shape, which is the parallel-chains
# contract.
#
# It measures what is INSTALLED (~/.pi/agent), not the working tree, and checks
# that the two agree: a prompts/ edit without ./adapters/pi/install.sh would grade
# the old antz.
#
# The run and the verdict are separate. This file produces the trace; `judge.mjs`
# decides what it means, from the session and a compact snapshot of the end state kept
# in out/<scenario>-<run>.state/. So the same decision can be re-made without paying for
# the run again (`rejudge.sh`) and pinned by `judge.test.mjs`.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="$HERE/out"
# The sandbox sits outside the repo. Inside `eval/`, one directory up is the harness that
# seeds the fault and the comments that name it: an agent read exactly that in one run, so
# the run was no longer blind. Sessions, logs and the tsv stay in `out/`.
SANDBOX="${ANTZ_EVAL_SANDBOX:-${TMPDIR:-/tmp}/antz-eval}"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
RUNS="${RUNS:-1}"
TIMEOUT="${TIMEOUT:-1800}"

# The verdict is `judge.mjs`, so node is not optional here. dispatch.sh needs it too.
command -v node >/dev/null 2>&1 || {
  echo "node is required: the verdict for every run is computed by judge.mjs" >&2
  exit 1
}

PROMPT='paginate() must respect the spec limit: asking for limit 1000 has to return 100 elements, not 1000'
PROMPT_M='add range, chunk, unique and sum helpers under src/, each with its own test file'
# N and H seed their own spec, so the prompt has to name that feature: /antz refuses to
# resume a plan that belongs to another one, which is the guard working as intended.
PROMPT_N='the store has to report its capacity and round-trip through JSON, and the browser needs a duration formatter and a grid span helper, each with its own test file'

usage() { sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
for arg in "$@"; do [ "$arg" = "-h" ] || [ "$arg" = "--help" ] && usage; done

# Everything antz copies into an agent. If the two sides differ, the eval would
# grade the previous antz. The `model:` line is ignored on purpose: the installer
# preserves a local pin, so it is not drift.
freshness() {
  local drift="" name
  cmp -s "$REPO/prompts/antz.md" "$AGENT_DIR/prompts/antz.md" || drift+="  prompts/antz.md\n"
  cmp -s "$REPO/extensions/antz-subagent.ts" "$AGENT_DIR/extensions/antz-subagent.ts" || drift+="  extensions/antz-subagent.ts\n"
  for file in "$REPO"/agents/antz-*.md; do
    name="$(basename "$file")"
    diff -q <(grep -v '^model:' "$file") <(grep -v '^model:' "$AGENT_DIR/agents/$name" 2>/dev/null) >/dev/null 2>&1 \
      || drift+="  agents/$name\n"
  done
  for dir in "$REPO"/skills/antz-*/; do
    name="$(basename "$dir")"
    diff -rq "$dir" "$AGENT_DIR/skills/$name" >/dev/null 2>&1 || drift+="  skills/$name\n"
  done
  printf '%b' "$drift"
}

if [ "${SKIP_FRESHNESS:-0}" != "1" ]; then
  drift="$(freshness)"
  if [ -n "$drift" ]; then
    printf 'the working tree and the install in %s disagree:\n%s\nrun ./adapters/pi/install.sh (and /reload if pi is open), or SKIP_FRESHNESS=1 to grade the install knowingly.\n' \
      "$AGENT_DIR" "$drift" >&2
    exit 1
  fi
fi

# The trace, the payloads, the concurrency shape and the verdict live in `judge.mjs`,
# as a pure function of the session and the end state. Nothing that reads a session
# stays here: the same decision is re-made for free by `rejudge.sh`, and `judge.test.mjs`
# pins it against the counters this file used to get wrong.

# What the subagents spent in one session: token counts only. `calls` is every
# dispatch and `withUsage` is how many reported any, so a provider that reports
# nothing shows up as calls > 0 with all-zero token columns.
usage_of() {
  jq -rs '
    [.[] | select(.type == "message") | .message] as $m
    | [$m[] | select(.role == "toolResult" and .toolName == "antz_subagent")] as $calls
    | [$calls[].usage | select(.)] as $t
    | [($calls | length),
       ($t | length),
       ([$t[].input] | add // 0),
       ([$t[].cacheRead] | add // 0),
       ([$t[].cacheWrite] | add // 0),
       ([$t[].output] | add // 0)]
    | @tsv' "$1" 2>/dev/null
}

# One scenario, one run. Leaves the verdict in VERDICT/REASON/SEQUENCE/SECONDS_TAKEN.
run_once() {
  local scenario="$1" run="$2" seed="$1"
  local sandbox="$SANDBOX/$scenario-$run" broken="$OUT/$scenario-$run.broken.js"
  # The session file stays outside the sandbox: inside it, an agent poking at the
  # repo would find the orchestrator's own transcript and the harness's intent.
  local session="$OUT/$scenario-$run.session.jsonl" watcher="" start seconds
  SESSION_FILE="$session"
  [ "$scenario" = "C" ] && seed="A"   # C is A with the fault re-injected

  # --session appends to an existing file, so a leftover trace from an earlier
  # run would be read as part of this one.
  rm -f "$session" "$broken"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/.antz" "$sandbox/src"
  # The tree the run starts from. N and H bring their own: two packages, two runners and
  # no package at the root, so finding out how to run a suite costs turns — the thing the
  # one-module fixture cannot charge for.
  local base="$HERE/fixture"
  case "$scenario" in N|H) base="$HERE/scenarios/mono/tree" ;; esac
  cp -R "$base/." "$sandbox/"
  if [ "$scenario" = "M" ]; then
    # Fixed recon, spec and plan: /antz enters at step 4 with the same tasks every
    # run, and a bigger AGENTS.md than the fixture so the shared prefix is real.
    cp "$HERE/scenarios/M/seed/"*.md "$sandbox/.antz/"
    cp "$HERE/scenarios/M/AGENTS.md" "$sandbox/AGENTS.md"
  elif [ "$scenario" = "N" ] || [ "$scenario" = "H" ]; then
    # One fixed plan both times. H differs in one file: its recon names the commands,
    # which is the control for what a recon that did its job is worth.
    cp "$HERE/scenarios/mono/seed/"*.md "$sandbox/.antz/"
    [ "$scenario" = "H" ] && cp "$HERE/scenarios/mono/seed-hint/00-recon.md" "$sandbox/.antz/00-recon.md"
  elif [ "$scenario" = "S" ]; then
    # One unchecked task whose two criteria contradict each other, so the tester's test
    # can be red but never green. That is the point: nothing can converge, and the
    # question is what the orchestrator does with an agent that stops on it.
    cp "$HERE/scenarios/stop/seed/"*.md "$sandbox/.antz/"
  else
    cp "$HERE/scenarios/spec/"*.md "$sandbox/.antz/"
  fi
  # Named `antz.gitignore` here so it cannot ignore this directory: as a real
  # `.gitignore` holding `*` it would hide the seed from the repo itself.
  cp "$HERE/scenarios/spec/antz.gitignore" "$sandbox/.antz/.gitignore"
  [ -d "$HERE/scenarios/$seed/src" ] && cp -R "$HERE/scenarios/$seed/src/." "$sandbox/src/"
  ( cd "$sandbox" && git init -q && git add -A \
    && git -c user.email=eval@antz -c user.name=eval commit -qm baseline ) >/dev/null 2>&1

  if [ "$scenario" = "C" ]; then
    # A fault no repair can fix: however well the fix is written, the file is
    # back to broken before the verifier reads it. Without this, reaching the cap
    # depends on the model failing three times on its own.
    cp "$sandbox/src/pagination.js" "$broken"
    ( while true; do cp "$broken" "$sandbox/src/pagination.js"; sleep 2; done ) &
    watcher=$!
  fi

  local prompt="$PROMPT"
  [ "$scenario" = "M" ] && prompt="$PROMPT_M"
  case "$scenario" in N|H) prompt="$PROMPT_N" ;; esac
  start="$(date +%s)"
  # From inside the sandbox: `/antz` routes on what is in the cwd, so launching
  # it anywhere else would measure another repo — or none.
  ( cd "$sandbox" && timeout "$TIMEOUT" pi -a -p --session "$session" "/antz $prompt" ) \
    >"$OUT/$scenario-$run.log" 2>&1
  [ -n "$watcher" ] && kill "$watcher" 2>/dev/null
  seconds=$(( $(date +%s) - start ))

  # The compact end state, kept beside the trace so the verdict can be re-made without
  # paying for the run again: `.antz/` (present only when the run did not close) and the
  # decision document, which together are everything the verdict reads off disk.
  local state="$OUT/$scenario-$run.state"
  rm -rf "$state"; mkdir -p "$state"
  [ -d "$sandbox/.antz" ] && cp -R "$sandbox/.antz" "$state/.antz"
  [ -d "$sandbox/docs" ] && cp -R "$sandbox/docs" "$state/docs"
  git -C "$sandbox" status --porcelain >"$state/tree.txt" 2>/dev/null

  # The verdict — from the session and the end state, by the one implementation both
  # this and `rejudge.sh` use. VERDICT/REASON/SEQUENCE are what the rest of this file
  # reports; `skipped` stays zero while the end state is present.
  if [ ! -f "$session" ]; then
    VERDICT=FAIL; REASON="the run produced no session: pi never started or died before writing one"
    SEQUENCE="(no dispatches)"
  else
    IFS=$'\t' read -r VERDICT REASON SEQUENCE _ < <(
      node "$HERE/judge.mjs" --scenario "$scenario" --session "$session" --state "$state" \
        --sandbox "$sandbox" --seconds "$seconds" --timeout "$TIMEOUT" --run "$run" \
        --record "$state/run.json" 2>/dev/null
    )
    [ -n "${VERDICT:-}" ] || { VERDICT=FAIL; REASON="judge.mjs produced no verdict"; }
    [ -n "$SEQUENCE" ] || SEQUENCE="(no dispatches)"
  fi
  SECONDS_TAKEN="$seconds"
}

SCENARIOS=("$@")
[ "${#SCENARIOS[@]}" -eq 0 ] && SCENARIOS=(A B C D)
mkdir -p "$OUT" "$SANDBOX"
RESULTS="$OUT/results.tsv"
[ -f "$RESULTS" ] || printf 'scenario\trun\tverdict\tsequence\tdetail\tseconds\n' >"$RESULTS"
# Usage lives in its own file so results.tsv keeps its fixed columns and rows
# from before this measurement stay aligned.
USAGE="$OUT/usage.tsv"
[ -f "$USAGE" ] || printf 'tag\tscenario\trun\tcalls\twithUsage\tinput\tcacheRead\tcacheWrite\toutput\n' >"$USAGE"
# One row per agent run, written by agents.sh, which is also the standalone
# auditor for any session — a real one included, since every run in
# `details.runs[]` carries its own usage and its own steps.
AGENTS="$OUT/agents.tsv"
[ -f "$AGENTS" ] || printf 'tag\tscenario\trun\tagent\tstatus\tturns\treads\tantzReads\tinput\tcacheRead\tcacheWrite\toutput\tseconds\tskills\ttools\n' >"$AGENTS"

failures=0
for scenario in "${SCENARIOS[@]}"; do
  for run in $(seq 1 "$RUNS"); do
    printf '== %s (run %s) ==\n' "$scenario" "$run"
    run_once "$scenario" "$run"
    printf '%s  %s/%s  [%s]  %ss\n    %s\n' "$VERDICT" "$scenario" "$run" "$SEQUENCE" "$SECONDS_TAKEN" "$REASON"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scenario" "$run" "$VERDICT" "$SEQUENCE" "$REASON" "$SECONDS_TAKEN" >>"$RESULTS"
    if [ -n "${SESSION_FILE:-}" ] && [ -f "$SESSION_FILE" ]; then
      printf '%s\t%s\t%s\t%s\n' "${TAG:-}" "$scenario" "$run" "$(usage_of "$SESSION_FILE")" >>"$USAGE"
      "$HERE/agents.sh" "$SESSION_FILE" \
        | awk -F'\t' -v OFS='\t' -v tag="${TAG:-}" -v sc="$scenario" -v rn="$run" '{ print tag, sc, rn, $0 }' >>"$AGENTS"
    fi
    [ "$VERDICT" = PASS ] || failures=$((failures + 1))
  done
done

printf '\n== summary ==\n'
awk -F'\t' 'NR>1 { total[$1]++; pass[$1]+=($3=="PASS") }
  END { for (s in total) printf "  %s: %d/%d\n", s, pass[s], total[s] }' "$RESULTS" | sort
printf '  traces in %s (results.tsv and usage.tsv accumulate every run)\n' "$OUT"
if [ -f "$USAGE" ]; then
  printf '\n== usage (mean per tag/scenario) ==\n'
  awk -F'\t' 'NR>1 { k=($1=="" ? "-" : $1)"/"$2; n[k]++
      calls[k]+=$4; wu[k]+=$5; inp[k]+=$6; cr[k]+=$7; cw[k]+=$8; outp[k]+=$9 }
    END { for (k in n) printf "  %s: %d run(s), %.1f calls (%.1f reported usage), input %.0f, cacheRead %.0f, cacheWrite %.0f, output %.0f\n",
      k, n[k], calls[k]/n[k], wu[k]/n[k], inp[k]/n[k], cr[k]/n[k], cw[k]/n[k], outp[k]/n[k] }' "$USAGE" | sort
fi
if [ -f "$AGENTS" ]; then
  printf '\n== agents (mean per tag/scenario/agent) ==\n'
  awk -F'\t' 'NR>1 { k=($1=="" ? "-" : $1)"/"$2"/"$4; n[k]++
      turns[k]+=$6; reads[k]+=$7; ar[k]+=$8; inp[k]+=$9; cr[k]+=$10; outp[k]+=$12; sec[k]+=$13 }
    END { for (k in n) printf "  %s: %d run(s), %.1f turns, %.1f reads (%.1f under .antz), input %.0f, cacheRead %.0f, output %.0f, %.0fs\n",
      k, n[k], turns[k]/n[k], reads[k]/n[k], ar[k]/n[k], inp[k]/n[k], cr[k]/n[k], outp[k]/n[k], sec[k]/n[k] }' "$AGENTS" | sort
  # The two files read the same sessions by different paths — the dispatch totals
  # pi reports against the per-agent rows — so they have to agree for every run that
  # has rows on both sides. A dispatch that errored has no agent rows, and so has any
  # row written before this file existed, which is what the count at the end is for.
  printf '\n== reconcile (dispatch totals vs agent rows) ==\n'
  awk -F'\t' '
    FNR == NR { if (FNR > 1) d[$1"/"$2] += $6 + $7 + $8 + $9; next }
    FNR > 1 { a[$1"/"$2] += $9 + $10 + $11 + $12; has[$1"/"$2] = 1 }
    END {
      for (k in d) {
        if (has[k]) printf "  %s: dispatch %.0f, agents %.0f%s\n", k, d[k], a[k], (a[k] == d[k] ? "" : "  <- mismatch")
        else n++
      }
      if (n) printf "  (%d dispatch row(s) without agent rows: a failed dispatch, or a row older than agents.tsv)\n", n
    }
  ' "$USAGE" "$AGENTS" | sort
fi
[ "$failures" -eq 0 ] || printf '\n%d run(s) outside the contract\n' "$failures"
exit "$([ "$failures" -eq 0 ] && echo 0 || echo 1)"

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
# that the two agree: a prompts/ edit without ./install.sh would grade the old
# antz.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
OUT="$HERE/out"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
RUNS="${RUNS:-1}"
TIMEOUT="${TIMEOUT:-1800}"

PROMPT='paginate() must respect the spec limit: asking for limit 1000 has to return 100 elements, not 1000'
PROMPT_M='add range, chunk, unique and sum helpers under src/, each with its own test file'

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
    printf 'the working tree and the install in %s disagree:\n%s\nrun ./install.sh (and /reload if pi is open), or SKIP_FRESHNESS=1 to grade the install knowingly.\n' \
      "$AGENT_DIR" "$drift" >&2
    exit 1
  fi
fi

# The trace of the loop: every antz_subagent dispatch, in order. The sequence of
# agents IS the routing, and the routing is what the eval measures. A `chains`
# call carries one chain per task, so it flattens like `chain` and `tasks` do.
sequence() {
  jq -r '
    select(.message.content? | type == "array")
    | .message.content[]
    | select(.type == "toolCall" and .name == "antz_subagent")
    | .arguments as $a
    | (($a.chain // []) + (($a.chains // []) | (add // [])) + ($a.tasks // [])) as $many
    | (if ($many | length) > 0 then $many else [{ agent: $a.agent }] end)
    | .[] | .agent
  ' "$1" 2>/dev/null | paste -sd' ' -
}

count_of() { printf '%s\n' "$1" | tr ' ' '\n' | grep -cx "$2"; }

# How many dispatches carried more than one unit of concurrent work. A unit is an
# agent that can run alongside another: every element of `tasks`, every chain of
# `chains`, and one for the shapes that are sequential by definition. Sibling
# calls in one message count together, because pi runs those concurrently.
parallel_dispatches() {
  jq -r '
    select(.message.content? | type == "array")
    | [.message.content[]
       | select(.type == "toolCall" and .name == "antz_subagent")
       | ([((.arguments.chains // []) | length), ((.arguments.tasks // []) | length), 1] | max)]
    | (add // 0)
    | select(. > 1)
  ' "$1" 2>/dev/null | wc -l | tr -d ' '
}

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
  local sandbox="$OUT/$scenario-$run" broken="$OUT/$scenario-$run.broken.js"
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
  cp -R "$HERE/fixture/." "$sandbox/"
  if [ "$scenario" = "M" ]; then
    # Fixed recon, spec and plan: /antz enters at step 4 with the same tasks every
    # run, and a bigger AGENTS.md than the fixture so the shared prefix is real.
    cp "$HERE/scenarios/M/seed/"*.md "$sandbox/.antz/"
    cp "$HERE/scenarios/M/AGENTS.md" "$sandbox/AGENTS.md"
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
  start="$(date +%s)"
  # From inside the sandbox: `/antz` routes on what is in the cwd, so launching
  # it anywhere else would measure another repo — or none.
  ( cd "$sandbox" && timeout "$TIMEOUT" pi -a -p --session "$session" "/antz $prompt" ) \
    >"$OUT/$scenario-$run.log" 2>&1
  [ -n "$watcher" ] && kill "$watcher" 2>/dev/null
  seconds=$(( $(date +%s) - start ))

  SEQUENCE="$(sequence "$session")"
  local parallel; parallel="$(parallel_dispatches "$session")"
  local cwd; cwd="$(jq -r 'select(.type == "session") | .cwd' "$session" 2>/dev/null | head -1)"
  if [ "$cwd" != "$sandbox" ]; then
    VERDICT=FAIL
    REASON="pi ran in '$cwd' instead of the sandbox: the run measures nothing"
    SECONDS_TAKEN="$seconds"
    return
  fi
  [ -n "$SEQUENCE" ] || SEQUENCE="(no dispatches)"

  local gone=1; [ -d "$sandbox/.antz" ] || gone=0
  local doc_name="pagination.md"
  [ "$scenario" = "M" ] && doc_name="collection-helpers.md"
  local doc=0; [ -f "$sandbox/docs/decisions/$doc_name" ] && doc=1
  local repairs; repairs=$(( $(count_of "$SEQUENCE" antz-implementer) + $(count_of "$SEQUENCE" antz-tester) ))

  VERDICT=PASS
  case "$scenario" in
    A|B|D)
      local blame=antz-implementer expected extra reruns
      [ "$scenario" = "B" ] && blame=antz-tester
      expected="antz-verifier $blame antz-verifier"
      # A trailing verifier round is tolerated: a verifier can return PASS
      # without doing the PASS work (writing the decision, deleting .antz/),
      # and the orchestrator sends it back to finish. That is recovery, not a
      # routing fault, so it is reported and not counted as a failure.
      case "$SEQUENCE" in
        "$expected"*) extra="${SEQUENCE#"$expected"}"; extra="${extra# }" ;;
        *) extra="__nomatch__" ;;
      esac
      reruns="$(printf '%s' "$extra" | tr ' ' '\n' | grep -cx 'antz-verifier')"
      if [ "$SEQUENCE" = "antz-verifier" ] && [ "$doc" -eq 1 ] && [ "$gone" -eq 0 ]; then
        # The verifier wrote the fix itself and closed the run. The end state looks
        # right and the loop was bypassed: no blame was reported, so nothing was
        # routed, and the tester's red-before-green never ran.
        if [ "$scenario" = "D" ]; then
          VERDICT=FAIL; REASON="the verifier read the green suite and passed: it never judged the shape"
        else
          VERDICT=FAIL; REASON="the verifier repaired and closed the run itself: the repair loop never ran"
        fi
      elif [ "$extra" = "__nomatch__" ]; then
        if [ "$scenario" = "D" ]; then
          VERDICT=FAIL; REASON="the verifier did not reject the shape: expected routing starting with '$expected', got '$SEQUENCE'"
        else
          VERDICT=FAIL; REASON="expected routing starting with '$expected', got '$SEQUENCE'"
        fi
      elif [ -n "$extra" ] && printf '%s' "$extra" | tr ' ' '\n' | grep -qvx 'antz-verifier'; then
        VERDICT=FAIL; REASON="after the repair only verifier rounds are tolerated, got '$extra'"
      elif [ "$repairs" -ne 1 ]; then
        VERDICT=FAIL; REASON="expected a single repair agent, got $repairs"
      elif [ "$gone" -eq 1 ]; then
        VERDICT=FAIL; REASON="the verifier should have deleted .antz/ after PASS"
      elif [ "$doc" -eq 0 ]; then
        VERDICT=FAIL; REASON="docs/decisions/$doc_name is missing, and only PASS writes it"
      else
        if [ "$scenario" = "D" ]; then
          REASON="the verifier failed the green change on shape, routed it to $blame, PASS on round 2: .antz/ deleted and the decision written"
        else
          REASON="blame routed to $blame, PASS on round 2, .antz/ deleted and the decision written"
        fi
        [ "$reruns" -gt 0 ] && REASON="$REASON; the verifier needed $reruns extra round(s) to finish the PASS work"
      fi
      ;;
    C)
      # The cap is on attempts, not on verifier rounds: the orchestrator may
      # re-verify between them (it usually does) or not.
      if [ "$doc" -eq 1 ] || [ "$gone" -eq 0 ]; then
        VERDICT=FAIL; REASON="it converged: with the fault re-injected there can be no PASS"
      elif [ "$repairs" -gt 3 ]; then
        VERDICT=FAIL; REASON="it went past the cap: $repairs repairs"
      elif [ "$repairs" -lt 3 ]; then
        VERDICT=FAIL; REASON="it gave up after $repairs attempts, so the cap was never exercised"
      elif [ "${SEQUENCE%% *}" != "antz-verifier" ]; then
        VERDICT=FAIL; REASON="the run did not enter at step 5: '${SEQUENCE%% *}' ran first"
      else
        REASON="3 attempts, then it stopped: .antz/ untouched and no decision written"
      fi
      ;;
    M)
      # Not a routing contract: the measurement is the usage row. This only says
      # the run reached the end as the parallel shape, so a broken run is visible
      # instead of a zero row.
      if [ "$gone" -eq 1 ]; then
        VERDICT=FAIL; REASON="the run did not finish: .antz/ is still there"
      elif [ "$doc" -eq 0 ]; then
        VERDICT=FAIL; REASON="docs/decisions/$doc_name is missing"
      elif [ "$(count_of "$SEQUENCE" antz-tester)" -lt 4 ] || [ "$(count_of "$SEQUENCE" antz-implementer)" -lt 4 ]; then
        VERDICT=FAIL; REASON="the four planned tasks did not all reach the tester and the implementer: '$SEQUENCE'"
      elif [ "$parallel" -lt 1 ]; then
        VERDICT=FAIL; REASON="the independent tasks were not dispatched together: no dispatch carried more than one unit of work: '$SEQUENCE'"
      else
        REASON="four independent chains dispatched in parallel ($parallel dispatch(es) carried more than one), verified: decision written and .antz/ deleted"
      fi
      ;;
    *) VERDICT=FAIL; REASON="unknown scenario" ;;
  esac
  SECONDS_TAKEN="$seconds"
}

SCENARIOS=("$@")
[ "${#SCENARIOS[@]}" -eq 0 ] && SCENARIOS=(A B C D)
mkdir -p "$OUT"
RESULTS="$OUT/results.tsv"
[ -f "$RESULTS" ] || printf 'scenario\trun\tverdict\tsequence\tdetail\tseconds\n' >"$RESULTS"
# Usage lives in its own file so results.tsv keeps its fixed columns and rows
# from before this measurement stay aligned.
USAGE="$OUT/usage.tsv"
[ -f "$USAGE" ] || printf 'tag\tscenario\trun\tcalls\twithUsage\tinput\tcacheRead\tcacheWrite\toutput\n' >"$USAGE"

failures=0
for scenario in "${SCENARIOS[@]}"; do
  for run in $(seq 1 "$RUNS"); do
    printf '== %s (run %s) ==\n' "$scenario" "$run"
    run_once "$scenario" "$run"
    printf '%s  %s/%s  [%s]  %ss\n    %s\n' "$VERDICT" "$scenario" "$run" "$SEQUENCE" "$SECONDS_TAKEN" "$REASON"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scenario" "$run" "$VERDICT" "$SEQUENCE" "$REASON" "$SECONDS_TAKEN" >>"$RESULTS"
    if [ -n "${SESSION_FILE:-}" ] && [ -f "$SESSION_FILE" ]; then
      printf '%s\t%s\t%s\t%s\n' "${TAG:-}" "$scenario" "$run" "$(usage_of "$SESSION_FILE")" >>"$USAGE"
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
[ "$failures" -eq 0 ] || printf '\n%d run(s) outside the contract\n' "$failures"
exit "$([ "$failures" -eq 0 ] && echo 0 || echo 1)"

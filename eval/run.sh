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
#   ./run.sh                # the three scenarios, once each
#   ./run.sh A B            # only those
#   RUNS=5 ./run.sh         # five repetitions of each
#
# The scenarios seed .antz/ with the plan already complete, so /antz enters at
# step 5 (verification) instead of recon: about 3 dispatches per run.
#
#   A  test faithful to the criteria, implementation that violates them  -> implementation at fault
#   B  implementation faithful, test that contradicts the criteria      -> test at fault
#   C  A, plus a watcher that re-injects the fault every 2 s             -> the 3-attempt cap
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

usage() { sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
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
# agents IS the routing, and the routing is what the eval measures.
sequence() {
  jq -r '
    select(.message.content? | type == "array")
    | .message.content[]
    | select(.type == "toolCall" and .name == "antz_subagent")
    | .arguments as $a
    | (($a.chain // []) + ($a.tasks // [])) as $many
    | (if ($many | length) > 0 then $many else [{ agent: $a.agent }] end)
    | .[] | .agent
  ' "$1" 2>/dev/null | paste -sd' ' -
}

count_of() { printf '%s\n' "$1" | tr ' ' '\n' | grep -cx "$2"; }

# One scenario, one run. Leaves the verdict in VERDICT/REASON/SEQUENCE/SECONDS_TAKEN.
run_once() {
  local scenario="$1" run="$2" seed="$1"
  local sandbox="$OUT/$scenario-$run" broken="$OUT/$scenario-$run.broken.js"
  # The session file stays outside the sandbox: inside it, an agent poking at the
  # repo would find the orchestrator's own transcript and the harness's intent.
  local session="$OUT/$scenario-$run.session.jsonl" watcher="" start seconds
  [ "$scenario" = "C" ] && seed="A"   # C is A with the fault re-injected

  # --session appends to an existing file, so a leftover trace from an earlier
  # run would be read as part of this one.
  rm -f "$session" "$broken"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/.antz" "$sandbox/src"
  cp -R "$HERE/fixture/." "$sandbox/"
  cp "$HERE/scenarios/spec/"*.md "$sandbox/.antz/"
  # Named `antz.gitignore` here so it cannot ignore this directory: as a real
  # `.gitignore` holding `*` it would hide the seed from the repo itself.
  cp "$HERE/scenarios/spec/antz.gitignore" "$sandbox/.antz/.gitignore"
  cp -R "$HERE/scenarios/$seed/src/." "$sandbox/src/"
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

  start="$(date +%s)"
  # From inside the sandbox: `/antz` routes on what is in the cwd, so launching
  # it anywhere else would measure another repo — or none.
  ( cd "$sandbox" && timeout "$TIMEOUT" pi -a -p --session "$session" "/antz $PROMPT" ) \
    >"$OUT/$scenario-$run.log" 2>&1
  [ -n "$watcher" ] && kill "$watcher" 2>/dev/null
  seconds=$(( $(date +%s) - start ))

  SEQUENCE="$(sequence "$session")"
  local cwd; cwd="$(jq -r 'select(.type == "session") | .cwd' "$session" 2>/dev/null | head -1)"
  if [ "$cwd" != "$sandbox" ]; then
    VERDICT=FAIL
    REASON="pi ran in '$cwd' instead of the sandbox: the run measures nothing"
    SECONDS_TAKEN="$seconds"
    return
  fi
  [ -n "$SEQUENCE" ] || SEQUENCE="(no dispatches)"

  local gone=1; [ -d "$sandbox/.antz" ] || gone=0
  local doc=0; [ -f "$sandbox/docs/decisions/pagination.md" ] && doc=1
  local repairs; repairs=$(( $(count_of "$SEQUENCE" antz-implementer) + $(count_of "$SEQUENCE" antz-tester) ))

  VERDICT=PASS
  case "$scenario" in
    A|B)
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
        VERDICT=FAIL; REASON="the verifier repaired and closed the run itself: the repair loop never ran"
      elif [ "$extra" = "__nomatch__" ]; then
        VERDICT=FAIL; REASON="expected routing starting with '$expected', got '$SEQUENCE'"
      elif [ -n "$extra" ] && printf '%s' "$extra" | tr ' ' '\n' | grep -qvx 'antz-verifier'; then
        VERDICT=FAIL; REASON="after the repair only verifier rounds are tolerated, got '$extra'"
      elif [ "$repairs" -ne 1 ]; then
        VERDICT=FAIL; REASON="expected a single repair agent, got $repairs"
      elif [ "$gone" -eq 1 ]; then
        VERDICT=FAIL; REASON="the verifier should have deleted .antz/ after PASS"
      elif [ "$doc" -eq 0 ]; then
        VERDICT=FAIL; REASON="docs/decisions/pagination.md is missing, and only PASS writes it"
      else
        REASON="blame routed to $blame, PASS on round 2, .antz/ deleted and the decision written"
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
    *) VERDICT=FAIL; REASON="unknown scenario" ;;
  esac
  SECONDS_TAKEN="$seconds"
}

SCENARIOS=("$@")
[ "${#SCENARIOS[@]}" -eq 0 ] && SCENARIOS=(A B C)
mkdir -p "$OUT"
RESULTS="$OUT/results.tsv"
[ -f "$RESULTS" ] || printf 'scenario\trun\tverdict\tsequence\tdetail\tseconds\n' >"$RESULTS"

failures=0
for scenario in "${SCENARIOS[@]}"; do
  for run in $(seq 1 "$RUNS"); do
    printf '== %s (run %s) ==\n' "$scenario" "$run"
    run_once "$scenario" "$run"
    printf '%s  %s/%s  [%s]  %ss\n    %s\n' "$VERDICT" "$scenario" "$run" "$SEQUENCE" "$SECONDS_TAKEN" "$REASON"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scenario" "$run" "$VERDICT" "$SEQUENCE" "$REASON" "$SECONDS_TAKEN" >>"$RESULTS"
    [ "$VERDICT" = PASS ] || failures=$((failures + 1))
  done
done

printf '\n== summary ==\n'
awk -F'\t' 'NR>1 { total[$1]++; pass[$1]+=($3=="PASS") }
  END { for (s in total) printf "  %s: %d/%d\n", s, pass[s], total[s] }' "$RESULTS" | sort
printf '  traces in %s (results.tsv accumulates every run)\n' "$OUT"
[ "$failures" -eq 0 ] || printf '\n%d run(s) outside the contract\n' "$failures"
exit "$([ "$failures" -eq 0 ] && echo 0 || echo 1)"

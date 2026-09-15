#!/bin/sh
# bench/adapter-dryrun.sh -- the dry-run mock client (change
# telemetry-benchmark, sub-spec 03). A mock, not a measurement target: it
# carries no network, no credentials, no real client binary -- bench_detect
# always succeeds (the dry-run client is the harness's own code), and the
# scripted flow artifacts it materializes are shapes the outcome
# classification reads (change dir, receipts, REJECTED.md, OPEN_QUESTIONS.md,
# archive), never a byte-portrait of any real client's output.
#
# The adapter contract, exactly three functions (telemetry-benchmark
# 03-adapter):
#   bench_detect            -> 0 + a non-empty version string (always usable)
#   bench_invoke  <repo> <request-file> <run-dir>
#                           -> launches the mock client in THIS shell's
#                              foreground (so the harness's deadline kill
#                              applies to it), working directory at the
#                              fixture repo, prompt taken verbatim from the
#                              request file, entry point antz-orchestrator;
#                              leaves the raw artifacts client.stdout,
#                              client.stderr, client.exit (the harness
#                              records client.exit itself when it killed the
#                              run), plus the mock's own client.request and
#                              telemetry.kv; stdin is /dev/null, so no
#                              login, permission, or trust prompt can ever
#                              block it.
#   bench_collect <run-dir> <repo>
#                           -> prints exactly the pinned telemetry keys, one
#                              "key=value" line each, normalizing the run's
#                              telemetry.kv (missing key or missing file is
#                              the literal "null"). Pure shell builtins:
#                              launches no agent session, makes no model
#                              call, runs no external command.
#
# Scripting inputs travel in the environment the runner controls:
#   BENCH_DRYRUN_OUTCOME    approved | rejected | blocked | open-question |
#                           error | timeout (default approved)
#   BENCH_REPETITION        repetition number, from 1 (default 1); telemetry
#                           values scale with it, flow artifacts do not.
#
# Writes only inside the run dir and the materialized fixture repo.

bench_detect() {
  printf '%s\n' 'dryrun-1.0.0'
  return 0
}

bench_invoke() {
  if [ "$#" -ne 3 ]; then
    echo "usage: bench_invoke <fixture-repo-dir> <request-file> <run-dir>" >&2
    return 2
  fi
  repo="$1"
  req="$2"
  run_dir="$3"
  if [ ! -d "$repo" ] || [ ! -f "$req" ] || [ ! -d "$run_dir" ]; then
    echo "bench_invoke: no such repo dir, request file, or run dir: $repo $req $run_dir" >&2
    return 2
  fi
  outcome="${BENCH_DRYRUN_OUTCOME:-approved}"
  rep="${BENCH_REPETITION:-1}"
  case "$outcome" in
    approved|rejected|blocked|open-question|error|timeout) ;;
    *)
      echo "bench_invoke: unknown scripted outcome: $outcome" >&2
      return 2
      ;;
  esac
  case "$rep" in
    ''|*[!0-9]*|0)
      echo "bench_invoke: BENCH_REPETITION must be an integer >= 1: $rep" >&2
      return 2
      ;;
  esac

  # The mock client runs HERE, in the foreground of this shell (no
  # backgrounding, no nohup): whatever waits on bench_invoke -- the harness's
  # deadline killer included -- waits on the client itself. stdout and stderr
  # are captured into the run dir's raw artifacts; stdin is /dev/null so the
  # invocation is non-interactive by construction.
  (
    cd "$repo" || exit 70
    printf 'dryrun client: entry=antz-orchestrator\n'
    printf 'dryrun client: cwd=%s\n' "$(pwd)"
    printf 'dryrun client: repetition=%s outcome=%s\n' "$rep" "$outcome"
    cat -- "$req" > "$run_dir/client.request" || exit 70

    case "$outcome" in
      timeout)
        # The kill script: announce and stay alive far past any deadline the
        # harness sets. Nothing else is materialized -- the outcome evidence
        # is the harness's kill record, not an artifact.
        sleep 300
        ;;
      error)
        # The failed-client script: a non-zero exit, no flow artifacts
        # written, no telemetry emitted.
        printf 'dryrun client: scripted failure\n' >&2
        exit 3
        ;;
      approved)
        mkdir -p spdd/changes/dryrun-flow spdd/archive/1970-01-01-dryrun-flow || exit 71
        {
          printf '# Domain: dryrun-demo (scripted by the dry-run client)\n'
          printf '## Feature: the scripted approved flow\n'
          printf '  Scenario: dryrun-demo-01\n'
          printf '    Given the dry-run scripted outcome approved\n'
          printf '    Then the flow archives the change\n'
        } > spdd/changes/dryrun-flow/01-dryrun-demo.feature
        {
          printf '# Result: 01-dryrun-demo (dryrun-flow)\n'
          printf '\n'
          printf 'test_command=none\n'
          printf 'id=dryrun-demo-01 result=green reason=the scripted approved artifact set\n'
        } > spdd/changes/dryrun-flow/01-dryrun-demo.result
        cp -- spdd/changes/dryrun-flow/01-dryrun-demo.result \
          spdd/archive/1970-01-01-dryrun-flow/01-dryrun-demo.result || exit 71
        ;;
      rejected)
        mkdir -p spdd/changes/dryrun-flow || exit 71
        {
          printf '# Domain: dryrun-demo (scripted by the dry-run client)\n'
          printf '## Feature: the scripted rejected flow\n'
          printf '  Scenario: dryrun-demo-01\n'
          printf '    Given the dry-run scripted outcome rejected\n'
        } > spdd/changes/dryrun-flow/01-dryrun-demo.feature
        {
          printf '# REJECTED.md (scripted by the dry-run client)\n'
          printf '\n'
          printf '## Rejection 1: scripted -- the dry-run rejected artifact set\n'
        } > spdd/changes/dryrun-flow/REJECTED.md
        ;;
      blocked)
        mkdir -p spdd/changes/dryrun-flow || exit 71
        {
          printf '# Result: 01-dryrun-demo (dryrun-flow)\n'
          printf '\n'
          printf 'test_command=none\n'
          printf 'id=dryrun-demo-01 result=blocked reason=BLOCKED: scripted refusal needing no shared-contract edit\n'
        } > spdd/changes/dryrun-flow/01-dryrun-demo.result
        ;;
      open-question)
        mkdir -p spdd/changes/dryrun-flow || exit 71
        {
          printf '# Result: 01-dryrun-demo (dryrun-flow)\n'
          printf '\n'
          printf 'test_command=none\n'
          printf 'id=dryrun-demo-01 result=green reason=the scripted open-question artifact set\n'
        } > spdd/changes/dryrun-flow/01-dryrun-demo.result
        {
          printf '# OPEN_QUESTIONS.md (scripted by the dry-run client)\n'
          printf '\n'
          printf '- Which pinned value should the scripted choice take?\n'
        } > spdd/changes/dryrun-flow/OPEN_QUESTIONS.md
        ;;
    esac

    # The successful scripts report their telemetry. Values are deterministic
    # and scale with the repetition number (so an aggregate over N repetitions
    # is distinguishable from an aggregate over one); the flow artifacts
    # above never carry the repetition, so they stay byte-identical across
    # repetitions of one outcome. tokens_reasoning and tokens_cache_write
    # are deliberately absent: this mock does not expose them, and collect
    # normalizes unavailable to null.
    {
      printf 'client_version=dryrun-1.0.0\n'
      printf 'client_duration_ms=%s\n' $((400 * rep))
      printf 'tokens_input=%s\n' $((100 * rep))
      printf 'tokens_output=%s\n' $((50 * rep))
      printf 'tokens_cache_read=%s\n' $((10 * rep))
      printf 'cost_usd=%s\n' "$(awk -v r="$rep" 'BEGIN { printf "%.4f", r * 0.0125 }')"
      printf 'turns=%s\n' $((3 * rep))
      printf 'tool_calls=%s\n' $((6 * rep))
      printf 'subagent_delegations=%s\n' $((2 * rep))
      printf 'models_used=dry-model-a,dry-model-b\n'
      printf 'session_id=dryrun-session-r%s\n' "$rep"
    } > "$run_dir/telemetry.kv" || exit 71
  ) > "$run_dir/client.stdout" 2> "$run_dir/client.stderr" < /dev/null
  rc=$?
  printf '%s\n' "$rc" > "$run_dir/client.exit"
  return $rc
}

bench_collect() {
  if [ "$#" -ne 2 ] || [ ! -d "$1" ] || [ ! -d "$2" ]; then
    echo "usage: bench_collect <run-dir> <fixture-repo-dir>" >&2
    return 2
  fi
  # Normalize the run's own artifacts into the pinned telemetry keys -- pure
  # builtins only, so this launches no agent session and makes no model call.
  client_version=null
  client_duration_ms=null
  tokens_input=null
  tokens_output=null
  tokens_reasoning=null
  tokens_cache_read=null
  tokens_cache_write=null
  cost_usd=null
  turns=null
  tool_calls=null
  subagent_delegations=null
  models_used=null
  session_id=null
  kv="$1/telemetry.kv"
  if [ -f "$kv" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        client_version=*) client_version=${line#client_version=} ;;
        client_duration_ms=*) client_duration_ms=${line#client_duration_ms=} ;;
        tokens_input=*) tokens_input=${line#tokens_input=} ;;
        tokens_output=*) tokens_output=${line#tokens_output=} ;;
        tokens_reasoning=*) tokens_reasoning=${line#tokens_reasoning=} ;;
        tokens_cache_read=*) tokens_cache_read=${line#tokens_cache_read=} ;;
        tokens_cache_write=*) tokens_cache_write=${line#tokens_cache_write=} ;;
        cost_usd=*) cost_usd=${line#cost_usd=} ;;
        turns=*) turns=${line#turns=} ;;
        tool_calls=*) tool_calls=${line#tool_calls=} ;;
        subagent_delegations=*) subagent_delegations=${line#subagent_delegations=} ;;
        models_used=*) models_used=${line#models_used=} ;;
        session_id=*) session_id=${line#session_id=} ;;
      esac
    done < "$kv"
  fi
  printf 'client_version=%s\n' "$client_version"
  printf 'client_duration_ms=%s\n' "$client_duration_ms"
  printf 'tokens_input=%s\n' "$tokens_input"
  printf 'tokens_output=%s\n' "$tokens_output"
  printf 'tokens_reasoning=%s\n' "$tokens_reasoning"
  printf 'tokens_cache_read=%s\n' "$tokens_cache_read"
  printf 'tokens_cache_write=%s\n' "$tokens_cache_write"
  printf 'cost_usd=%s\n' "$cost_usd"
  printf 'turns=%s\n' "$turns"
  printf 'tool_calls=%s\n' "$tool_calls"
  printf 'subagent_delegations=%s\n' "$subagent_delegations"
  printf 'models_used=%s\n' "$models_used"
  printf 'session_id=%s\n' "$session_id"
  return 0
}

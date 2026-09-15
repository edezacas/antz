#!/bin/sh
# bench/adapter-claude.sh -- the headless Claude Code client adapter (change
# telemetry-benchmark, sub-spec 04-clients).
#
# Verified invoke shape (claude v2.1.272):
#   claude -p "<request>" --agent antz-orchestrator --output-format json
#          --dangerously-skip-permissions [--model <pinned>]
# exits 0 and prints ONE result JSON object carrying usage (input_tokens,
# output_tokens, cache_creation_input_tokens, cache_read_input_tokens),
# total_cost_usd, duration_ms, num_turns, session_id and modelUsage (per-
# model aggregates). The session transcript (JSONL, one entry per exchange,
# sidechain entries marked "isSidechain":true and carrying "agentId") lives
# under $CLAUDE_CONFIG_DIR/projects/**/<session_id>.jsonl -- inside the
# SANDBOX's relocated config root, so the measurement never reads the
# user's real transcripts.
#
# Adapter contract (sub-spec 03): EXACTLY the three functions below.
#   bench_detect                 -> 0 + non-empty version, or non-zero.
#   bench_invoke <repo> <request-file> <run-dir>
#     Runs the client in the fixture repo, under the sandbox allowlist
#     environment (BENCH_SANDBOX names the prepared root; the pinned model
#     BENCH_MODEL is forwarded with --model exactly when non-empty), with
#     stdin from /dev/null and in the foreground so a deadline kill reaches
#     it. Leaves client.stdout / client.stderr / client.exit (plus the
#     client.version string and a copy of the run's session transcript,
#     transcript.jsonl, when the client wrote one).
#   bench_collect <run-dir> <repo> -> the 13 pinned telemetry keys.
#
# Attribution contract (clients-05; resolves the README's open point
# mechanically, for the live delivery check at benchqa-05): the result-JSON
# aggregates are treated as PRIMARY-session totals, and every sidechain
# (delegated) usage the isolated transcript exposes adds to them -- token
# totals and tool_calls cover primary + sidechain; cost additionally
# requires each sidechain usage entry to expose a "costUSD" field (absent
# cost is unattributable, so the cost total goes null rather than
# undercount). turns, client_duration_ms, session_id and models_used come
# from the result itself (turn counts are the client's own; the transcript
# is not consulted for them). With no transcript: tool_calls and
# subagent_delegations are null and the token totals come from the result
# alone -- nothing crashes, nothing is invented.
#
# POSIX sh only; the bench tree uses awk/sed/grep as its only parsing aids.

bench_detect() {
  v=$(claude --version 2>/dev/null | head -n 1)
  if [ -z "$v" ]; then
    echo "bench_detect: claude not usable (no version from 'claude --version')" >&2
    return 1
  fi
  printf '%s\n' "$v"
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
  sbx="${BENCH_SANDBOX:-}"
  if [ -z "$sbx" ] || [ ! -d "$sbx/home" ]; then
    echo "bench_invoke: BENCH_SANDBOX must name a sandbox root prepared by bench_sandbox_create" >&2
    return 2
  fi
  # The request bytes verbatim (the x-sentinel keeps trailing newlines
  # through the capture -- the client receives exactly what the run dir
  # recorded as request.txt).
  prompt=$(cat -- "$req"; printf x)
  prompt=${prompt%x}
  (
    cd "$repo" || exit 70
    # The version the client reports for THIS invocation (recorded, never
    # assumed); then the headless run itself. --model is passed exactly
    # when a model is pinned.
    bench_sandbox_run "$sbx" claude --version > "$run_dir/client.version" 2> /dev/null
    if [ -n "${BENCH_MODEL:-}" ]; then
      bench_sandbox_run "$sbx" claude -p "$prompt" --agent antz-orchestrator \
        --output-format json --dangerously-skip-permissions --model "$BENCH_MODEL"
    else
      bench_sandbox_run "$sbx" claude -p "$prompt" --agent antz-orchestrator \
        --output-format json --dangerously-skip-permissions
    fi
  ) > "$run_dir/client.stdout" 2> "$run_dir/client.stderr" < /dev/null
  rc=$?
  printf '%s\n' "$rc" > "$run_dir/client.exit"
  # Pull the run's session transcript (written by the client inside the
  # sandbox's relocated config root) into the run dir, where collect can
  # attribute it. A missing session id or transcript is not an error --
  # collect then reports what the result alone supports.
  sid=$(bench_claude_result_str "$run_dir/client.stdout" session_id)
  case "$sid" in
    ''|*[!A-Za-z0-9._-]*) sid="" ;;
  esac
  if [ -n "$sid" ] && [ -d "$sbx/home/.claude/projects" ]; then
    tf=$(find "$sbx/home/.claude/projects" -type f -name "$sid.jsonl" 2>/dev/null \
      | LC_ALL=C sort | head -n 1)
    if [ -n "$tf" ]; then
      cp -- "$tf" "$run_dir/transcript.jsonl" \
        || echo "bench_invoke: transcript copy failed: $tf" >&2
    fi
  fi
  return $rc
}

bench_collect() {
  if [ "$#" -ne 2 ] || [ ! -d "$1" ] || [ ! -d "$2" ]; then
    echo "usage: bench_collect <run-dir> <fixture-repo-dir>" >&2
    return 2
  fi
  run_dir="$1"
  res="$run_dir/client.stdout"
  tr_f="$run_dir/transcript.jsonl"

  # Result-JSON scalars (empty string = the client did not report it).
  r_dur=$(bench_claude_result_num "$res" duration_ms)
  r_turns=$(bench_claude_result_num "$res" num_turns)
  r_cost=$(bench_claude_result_num "$res" total_cost_usd)
  r_in=$(bench_claude_result_num "$res" usage.input_tokens)
  r_out=$(bench_claude_result_num "$res" usage.output_tokens)
  r_cw=$(bench_claude_result_num "$res" usage.cache_creation_input_tokens)
  r_cr=$(bench_claude_result_num "$res" usage.cache_read_input_tokens)
  r_sid=$(bench_claude_result_str "$res" session_id)
  r_models=$(bench_claude_result_models "$res")

  # Sidechain attribution from the transcript (a missing or empty
  # transcript is honestly absent, not zero-usage).
  t_present=0
  t_in=0; t_out=0; t_cr=0; t_cw=0; t_cost=0
  t_su=0; t_nocost=0; t_tools=0; t_del=0
  if [ -s "$tr_f" ]; then
    t_present=1
    while IFS= read -r _bcl_line; do
      case "$_bcl_line" in
        tin=*)    t_in=${_bcl_line#tin=} ;;
        tout=*)   t_out=${_bcl_line#tout=} ;;
        tcr=*)    t_cr=${_bcl_line#tcr=} ;;
        tcw=*)    t_cw=${_bcl_line#tcw=} ;;
        tcost=*)  t_cost=${_bcl_line#tcost=} ;;
        su=*)     t_su=${_bcl_line#su=} ;;
        nocost=*) t_nocost=${_bcl_line#nocost=} ;;
        tools=*)  t_tools=${_bcl_line#tools=} ;;
        del=*)    t_del=${_bcl_line#del=} ;;
      esac
    done <<BCL_TRAN
$(bench_claude_transcript_kv "$tr_f")
BCL_TRAN
  fi

  # Totals: result value + sidechain addendum (a null result value keeps
  # the field null -- never a sidechain-only sum).
  f_in=null; f_out=null; f_cr=null; f_cw=null; f_cost=null
  if [ -n "$r_in" ];  then f_in=$([ "$t_present" = 1 ] && bench_num_add "$r_in" "$t_in" || printf '%s' "$r_in"); fi
  if [ -n "$r_out" ]; then f_out=$([ "$t_present" = 1 ] && bench_num_add "$r_out" "$t_out" || printf '%s' "$r_out"); fi
  if [ -n "$r_cr" ];  then f_cr=$([ "$t_present" = 1 ] && bench_num_add "$r_cr" "$t_cr" || printf '%s' "$r_cr"); fi
  if [ -n "$r_cw" ];  then f_cw=$([ "$t_present" = 1 ] && bench_num_add "$r_cw" "$t_cw" || printf '%s' "$r_cw"); fi
  if [ -n "$r_cost" ]; then
    if [ "$t_su" -gt 0 ] && [ "$t_nocost" -gt 0 ]; then
      f_cost=null   # sidechain usage the transcript does not price: null, never undercount
    elif [ "$t_su" -gt 0 ]; then
      f_cost=$(bench_num_add "$r_cost" "$t_cost")
    else
      f_cost=$r_cost
    fi
  fi

  # Transcript-only observations: honest null when the transcript is absent.
  f_tools=null; f_del=null
  if [ "$t_present" = 1 ]; then
    f_tools=$t_tools
    f_del=$t_del
  fi

  cv=null
  if [ -f "$run_dir/client.version" ]; then
    v=$(head -n 1 "$run_dir/client.version")
    [ -n "$v" ] && cv=$v
  fi

  printf 'client_version=%s\n' "$cv"
  printf 'client_duration_ms=%s\n' "${r_dur:-null}"
  printf 'tokens_input=%s\n' "$f_in"
  printf 'tokens_output=%s\n' "$f_out"
  printf 'tokens_reasoning=null\n'   # Claude's artifacts expose none
  printf 'tokens_cache_read=%s\n' "$f_cr"
  printf 'tokens_cache_write=%s\n' "$f_cw"
  printf 'cost_usd=%s\n' "$f_cost"
  printf 'turns=%s\n' "${r_turns:-null}"
  printf 'tool_calls=%s\n' "$f_tools"
  printf 'subagent_delegations=%s\n' "$f_del"
  printf 'models_used=%s\n' "${r_models:-null}"
  printf 'session_id=%s\n' "${r_sid:-null}"
  return 0
}

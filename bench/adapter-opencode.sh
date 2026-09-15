#!/bin/sh
# bench/adapter-opencode.sh -- the headless OpenCode client adapter (change
# telemetry-benchmark, sub-spec 04-clients).
#
# Verified invoke shape (opencode v1.18.31):
#   opencode run --agent antz-orchestrator --format json --auto
#                [--model <pinned>] "<request>"
# emits per-event JSON lines, each carrying "sessionID" (step-finish parts
# carry tokens). `opencode export <sessionID>` returns {info, messages} with
# info.tokens (input / output / reasoning / cache.read / cache.write),
# info.cost, info.model, info.time {created, updated} -- and PARENT TOTALS
# EXCLUDE child sessions: task tool parts carry state.metadata.sessionID
# naming each child (subagent) session, so the adapter exports the children
# too and sums.
#
# Adapter contract (sub-spec 03): EXACTLY the three functions below.
#   bench_detect                 -> 0 + non-empty version, or non-zero.
#   bench_invoke <repo> <request-file> <run-dir>
#     Runs the client in the fixture repo, under the sandbox allowlist
#     environment (BENCH_SANDBOX), stdin from /dev/null, foreground. Leaves
#     client.stdout / client.stderr / client.exit (+ client.version).
#     --model is passed exactly when a model is pinned.
#   bench_collect <run-dir> <repo> -> the 13 pinned telemetry keys,
#     normalizing client.stdout (session id) plus the parent and child
#     exports fetched through the sandbox (`opencode export <sid>`), and
#     saved into the run dir as export.<who>.json for audit:
#       tokens_*, cost_usd, tool_calls  summed over parent AND every child
#         a task part names -- but only when EVERY expected export was
#         available and complete; a missing/partial child export nulls the
#         affected totals (never a silently partial sum);
#       subagent_delegations            the task parts observed in the
#         PARENT export (counted even when a child export is unavailable);
#         children's own task parts are not chased (single delegation
#         level);
#       client_duration_ms              parent export's
#         info.time.updated - info.time.created;
#       models_used                     distinct info.model over the
#         exports that succeeded (parent first, then children sorted);
#       session_id                      from the run events;
#       turns                           null: OpenCode reports no turn
#         count in these artifacts (null beats a guess).
#
# POSIX sh only; parsing goes through bench/lib.sh's awk JSON readers.

bench_detect() {
  v=$(opencode --version 2>/dev/null | head -n 1)
  if [ -z "$v" ]; then
    echo "bench_detect: opencode not usable (no version from 'opencode --version')" >&2
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
  # The request bytes verbatim (the x-sentinel keeps trailing newlines).
  prompt=$(cat -- "$req"; printf x)
  prompt=${prompt%x}
  (
    cd "$repo" || exit 70
    bench_sandbox_run "$sbx" opencode --version > "$run_dir/client.version" 2> /dev/null
    if [ -n "${BENCH_MODEL:-}" ]; then
      bench_sandbox_run "$sbx" opencode run --agent antz-orchestrator \
        --format json --auto --model "$BENCH_MODEL" "$prompt"
    else
      bench_sandbox_run "$sbx" opencode run --agent antz-orchestrator \
        --format json --auto "$prompt"
    fi
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
  run_dir="$1"
  sbx="${BENCH_SANDBOX:-}"
  if [ -z "$sbx" ] || [ ! -d "$sbx/home" ]; then
    echo "bench_collect: BENCH_SANDBOX must name a sandbox root prepared by bench_sandbox_create" >&2
    return 2
  fi

  # The parent session id comes from the run events themselves.
  sid=$(bench_json_get "$run_dir/client.stdout" sessionID)
  case "$sid" in
    ''|*[!A-Za-z0-9._-]*) sid="" ;;
  esac

  # Fetch the parent export (the sandbox's client serves it); a failure
  # leaves no partial artifact behind.
  pexp="$run_dir/export.parent.json"
  rm -f -- "$pexp"
  parent_ok=0
  if [ -n "$sid" ] && bench_sandbox_run "$sbx" opencode export "$sid" > "$pexp" 2> /dev/null; then
    parent_ok=1
  else
    rm -f -- "$pexp"
  fi

  # The children a task part's state.metadata names (parent totals exclude
  # them, so attribution must fetch them too).
  kids=""
  if [ "$parent_ok" = 1 ]; then
    pkv=$(bench_opencode_export_kv "$pexp")
    kids=$(printf '%s\n' "$pkv" | sed -n 's/^child=//p' | LC_ALL=C sort -u)
  fi
  kid_files=""
  if [ -n "$kids" ]; then
    while IFS= read -r kid; do
      case "$kid" in
        ''|*[!A-Za-z0-9._-]*) continue ;;
      esac
      [ "$kid" = "$sid" ] && continue
      kexp="$run_dir/export.$kid.json"
      if bench_sandbox_run "$sbx" opencode export "$kid" > "$kexp" 2> /dev/null; then
        :
      else
        rm -f -- "$kexp"
      fi
      kid_files="$kid_files $kexp"
    done <<BOK_KIDS
$kids
BOK_KIDS
  fi

  # Sum over the parent plus every named child. Any missing or incomplete
  # export nulls the affected totals (coverage discipline); models_used
  # keeps what succeeded; the parent's own observations stand alone.
  f_in=null f_out=null f_rea=null f_cr=null f_cw=null f_cost=null f_tools=null
  expected=0 parsed=0
  m_list=""
  sum_in=0 sum_out=0 sum_rea=0 sum_cr=0 sum_cw=0 sum_cost=0 sum_tools=0
  p_dur=null p_del=null
  for f in "$pexp" $kid_files; do
    [ -f "$f" ] || { expected=$((expected + 1)); continue; }
    expected=$((expected + 1))
    ekv=$(bench_opencode_export_kv "$f")
    m=$(printf '%s\n' "$ekv" | sed -n 's/^info-model=//p' | head -n 1)
    ti=$(printf '%s\n' "$ekv" | sed -n 's/^info-tokens-input=//p' | head -n 1)
    to=$(printf '%s\n' "$ekv" | sed -n 's/^info-tokens-output=//p' | head -n 1)
    tr=$(printf '%s\n' "$ekv" | sed -n 's/^info-tokens-reasoning=//p' | head -n 1)
    cr=$(printf '%s\n' "$ekv" | sed -n 's/^info-tokens-cache-read=//p' | head -n 1)
    cw=$(printf '%s\n' "$ekv" | sed -n 's/^info-tokens-cache-write=//p' | head -n 1)
    co=$(printf '%s\n' "$ekv" | sed -n 's/^info-cost=//p' | head -n 1)
    tp=$(printf '%s\n' "$ekv" | sed -n 's/^tool-parts=//p' | head -n 1)
    # every summed value must be reported, or the sum would be partial
    complete=1
    for v in "$ti" "$to" "$tr" "$cr" "$cw" "$co" "$tp"; do
      [ -n "$v" ] || complete=0
    done
    case "$ti$to$tr$cr$cw$co$tp" in *[!0-9.]*) complete=0 ;; esac
    if [ -n "$m" ]; then
      case " $m_list " in
        *" $m "*) ;;
        *) m_list="$m_list $m" ;;
      esac
    fi
    if [ "$complete" = 1 ]; then
      parsed=$((parsed + 1))
      sum_in=$(bench_num_add "$sum_in" "$ti")
      sum_out=$(bench_num_add "$sum_out" "$to")
      sum_rea=$(bench_num_add "$sum_rea" "$tr")
      sum_cr=$(bench_num_add "$sum_cr" "$cr")
      sum_cw=$(bench_num_add "$sum_cw" "$cw")
      sum_cost=$(bench_num_add "$sum_cost" "$co")
      sum_tools=$(bench_num_add "$sum_tools" "$tp")
    fi
    if [ "$f" = "$pexp" ]; then
      cre=$(printf '%s\n' "$ekv" | sed -n 's/^info-created=//p' | head -n 1)
      upd=$(printf '%s\n' "$ekv" | sed -n 's/^info-updated=//p' | head -n 1)
      tsk=$(printf '%s\n' "$ekv" | sed -n 's/^task-parts=//p' | head -n 1)
      case "$cre$upd" in ''|*[!0-9]*) ;; *) p_dur=$(bench_num_sub "$upd" "$cre") ;; esac
      case "$tsk" in ''|*[!0-9]*) ;; *) p_del=$tsk ;; esac
    fi
  done
  if [ "$parent_ok" = 1 ] && [ "$parsed" = "$expected" ]; then
    f_in=$sum_in f_out=$sum_out f_rea=$sum_rea f_cr=$sum_cr f_cw=$sum_cw
    f_cost=$sum_cost f_tools=$sum_tools
  fi
  if [ -n "$m_list" ]; then
    # trim the leading space
    models=$(printf '%s\n' "$m_list" | sed -e 's/^ //' -e 's/ /,/g')
  else
    models=null
  fi

  cv=null
  if [ -f "$run_dir/client.version" ]; then
    v=$(head -n 1 "$run_dir/client.version")
    [ -n "$v" ] && cv=$v
  fi

  printf 'client_version=%s\n' "$cv"
  printf 'client_duration_ms=%s\n' "$p_dur"
  printf 'tokens_input=%s\n' "$f_in"
  printf 'tokens_output=%s\n' "$f_out"
  printf 'tokens_reasoning=%s\n' "$f_rea"
  printf 'tokens_cache_read=%s\n' "$f_cr"
  printf 'tokens_cache_write=%s\n' "$f_cw"
  printf 'cost_usd=%s\n' "$f_cost"
  printf 'turns=null\n'   # no turn count in these artifacts
  printf 'tool_calls=%s\n' "$f_tools"
  printf 'subagent_delegations=%s\n' "$p_del"
  printf 'models_used=%s\n' "$models"
  printf 'session_id=%s\n' "${sid:-null}"
  return 0
}

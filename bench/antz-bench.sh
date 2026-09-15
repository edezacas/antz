#!/bin/sh
# bench/antz-bench.sh -- the antz benchmark runner CLI (change
# telemetry-benchmark, sub-spec 05-runner). One entry point, two modes:
# the default RUN mode (N sequential repetitions per client against the
# bench fixture, one telemetry record per repetition appended to the
# results JSONL, and the aggregate report printed at the end) and the
# standalone REPORT mode (aggregate a JSONL without launching anything).
#
# POSIX sh only; awk/sed/grep are the only parsing aids (via bench/lib.sh);
# no jq, python, node, or any other non-POSIX interpreter. The runner is
# repo-local to bench/ and never installed globally.
#
# Contract (telemetry-benchmark 05-runner):
#   - Client selection mirrors install.sh's detection predicate (CLI on
#     PATH or the client's global config directory exists), evaluated
#     against the real host environment; --client forces one client past
#     detection; the dry-run client runs only when named explicitly.
#   - Exit 0 means every repetition produced a record -- outcome values
#     are measurements, not failures. Non-zero exits are harness-internal
#     failures (refused arguments, no usable client, an unmaterializable
#     fixture, an unwritable output path, or a missing record).

set -u

BENCH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) \
  || { printf 'antz-bench: cannot resolve the bench directory of: %s\n' "$0" >&2; exit 1; }
# shellcheck source=lib.sh
. "$BENCH_DIR/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  sh bench/antz-bench.sh [flags]                     run mode
  sh bench/antz-bench.sh report --jsonl <file> [--baseline <file>]

Run mode: for each selected client, N sequential repetitions against the
bench fixture -- each repetition materializes a fresh git repo, prepares a
fresh sandbox, runs the client headless as the antz-orchestrator under the
per-repetition deadline, and appends exactly one telemetry record to the
results JSONL. At the end the aggregate report prints to stdout.

Flags (run mode; each takes a separate value):
  --client <name>          force ONE client (claude | opencode | dryrun),
                           bypassing detection. With no --client every
                           detected client runs (Claude Code when "claude"
                           is on PATH or ~/.claude exists; OpenCode when
                           "opencode" is on PATH or ~/.config/opencode
                           exists -- install.sh's predicate); the dry-run
                           client runs only when named explicitly.
  --repetitions <n>        repetitions per client (default: 1)
  --model <value>          pin the model: forwarded to the client and
                           recorded in every record (default: unpinned)
  --timeout <seconds>      per-repetition deadline; firing yields outcome
                           "timeout" (default: 1800)
  --baseline <file>        baseline JSONL for the report's comparison
                           section (default: none)
  --jsonl <file>           results path (default: a fresh
                           bench/results/bench-<UTC timestamp>.jsonl; the
                           results directory is created on demand)
  --dryrun-outcome <out>   script the dry-run client's outcome
                           (approved | rejected | blocked | open-question |
                           error | timeout; default: approved; dryrun only)

Report mode: prints the same aggregate report standalone, from a results
JSONL (--jsonl, required) with an optional --baseline; it never launches a
client and never writes anything except its report output.

Exit contract: exit 0 means every repetition produced a record -- outcome
values (approved, rejected, blocked, open-question, timeout, error) are
measurements, not failures. Non-zero exits are harness-internal failures:
refused arguments, no usable client, a fixture that cannot be materialized,
an unwritable output path, or a repetition whose record was not written.
EOF
}

die_usage() {
  printf 'antz-bench: %s\n' "$1" >&2
  usage >&2
  exit 2
}

# ---- argument surface (pinned flags; sub-spec 05 "Out of scope": no more) ----
mode=run
f_client=""
f_repetitions=1
f_model=""
f_timeout=1800
f_baseline=""
f_jsonl=""
f_dryrun_outcome=""

need_value() {
  # $1 = flag name: refuse a flag that arrived without its value.
  [ "$#" -ge 2 ] || die_usage "missing value for $1"
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0) return 1 ;;
    *) return 0 ;;
  esac
}

if [ "${1:-}" = report ]; then
  mode=report
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --client) need_value "$@"; f_client=$2; shift 2 ;;
    --repetitions) need_value "$@"; f_repetitions=$2; shift 2 ;;
    --model) need_value "$@"; f_model=$2; shift 2 ;;
    --timeout) need_value "$@"; f_timeout=$2; shift 2 ;;
    --baseline) need_value "$@"; f_baseline=$2; shift 2 ;;
    --jsonl) need_value "$@"; f_jsonl=$2; shift 2 ;;
    --dryrun-outcome) need_value "$@"; f_dryrun_outcome=$2; shift 2 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

is_positive_int "$f_repetitions" || die_usage "--repetitions must be an integer >= 1: $f_repetitions"
is_positive_int "$f_timeout" || die_usage "--timeout must be an integer >= 1: $f_timeout"
case "$f_dryrun_outcome" in
  ''|approved|rejected|blocked|open-question|error|timeout) ;;
  *) die_usage "--dryrun-outcome must be one of approved|rejected|blocked|open-question|error|timeout: $f_dryrun_outcome" ;;
esac

if [ "$mode" = report ]; then
  # Report mode consumes only its two inputs; run-mode mechanics are refused.
  for applied in "$f_client" "$f_model" "$f_dryrun_outcome"; do
    [ -z "$applied" ] || die_usage "report mode takes only --jsonl and --baseline (offending value: $applied)"
  done
  [ "$f_repetitions" = 1 ] || die_usage "--repetitions does not apply to report mode"
  [ "$f_timeout" = 1800 ] || die_usage "--timeout does not apply to report mode"
  [ -n "$f_jsonl" ] || die_usage "report mode needs --jsonl <file>"
fi

# ---- modes -------------------------------------------------------------------
# Sub-spec 05 wires run mode; sub-spec 06 owns the report's statistics. Both
# funnel through bench_report (bench/lib.sh) so the run-end report and the
# standalone "report" mode are the same computation.

CHECKOUT_ROOT=$(dirname -- "$BENCH_DIR")
SCENARIO=toysize-doc-sync   # the one checked-in fixture scenario (01-fixture)

# Guard the adapter-facing variables against anything the invoking shell
# happens to carry: the flags are the only way in.
unset BENCH_SANDBOX BENCH_MODEL BENCH_REPETITION BENCH_DRYRUN_OUTCOME

warn() { printf 'antz-bench: %s\n' "$1" >&2; }
die_internal() { warn "$1"; exit 1; }

now_ms() {
  # The harness's OWN wall clock, in milliseconds since the epoch (second
  # resolution where %3N is unsupported); client-reported durations are
  # recorded alongside it, never substituted for it.
  ms=$(date +%s%3N 2>/dev/null)
  case "$ms" in
    ''|*[!0-9]*) ms=$(( $(date +%s) * 1000 )) ;;
  esac
  printf '%s\n' "$ms"
}

# ---- run mode ------------------------------------------------------------------

refuse_no_client() {
  # Loud refusal, non-zero, before anything is written: the escape hatch
  # is named explicitly.
  warn "no client detected: Claude Code needs the 'claude' CLI on PATH or ~/.claude; OpenCode needs the 'opencode' CLI on PATH or ~/.config/opencode"
  warn "nothing to run -- force a client past detection with --client <claude|opencode|dryrun>"
  exit 1
}

select_clients() {
  # Set CLIENTS (space-separated, claude before opencode) and FORCED (1
  # when --client named one explicitly). Selection mirrors install.sh's
  # detection predicate verbatim, evaluated against THIS process's real
  # host environment (HOME and PATH -- independent of any sandbox); the
  # dry-run client is selectable only explicitly.
  if [ -n "$f_client" ]; then
    CLIENTS="$f_client"
    FORCED=1
    return 0
  fi
  FORCED=0
  CLIENTS=""
  want_claude=0
  want_opencode=0
  command -v claude >/dev/null 2>&1 && want_claude=1
  [ -d "$HOME/.claude" ] && want_claude=1
  command -v opencode >/dev/null 2>&1 && want_opencode=1
  [ -d "$HOME/.config/opencode" ] && want_opencode=1
  [ "$want_claude" -eq 1 ] && CLIENTS="$CLIENTS claude"
  [ "$want_opencode" -eq 1 ] && CLIENTS="$CLIENTS opencode"
  [ -n "$CLIENTS" ] || refuse_no_client
  return 0
}

usability_preflight() {
  # Source each selected adapter and call its bench_detect BEFORE any
  # record can be written. A FORCED client that does not detect as usable
  # is a harness-internal failure (pinned by runner-04); an auto-detected
  # one is skipped with a visible warning. When the filter empties the
  # set, that is a host where nothing is usable -- the same loud refusal.
  usable=""
  for c in $CLIENTS; do
    if ! bench_source_adapter "$c"; then
      [ "$FORCED" -eq 1 ] && die_internal "forced client $c has no usable adapter"
      warn "client $c has no adapter: skipping it"
      continue
    fi
    cversion=$(bench_detect 2>/dev/null)
    drc=$?
    if [ "$drc" -ne 0 ] || [ -z "$cversion" ]; then
      [ "$FORCED" -eq 1 ] && die_internal "forced client $c does not detect as usable"
      warn "client $c was detected but does not detect as usable: skipping it"
      continue
    fi
    usable="$usable $c"
  done
  CLIENTS=$(printf '%s\n' "$usable" | tr -s ' ')
  CLIENTS=${CLIENTS# }
  [ -n "$CLIENTS" ] || refuse_no_client
  return 0
}

run_mode() {
  # Preflight, then the sequential repetition loop. Every preflight failure
  # is harness-internal: non-zero exit BEFORE any record is written.
  select_clients
  usability_preflight

  ANTZ_VERSION=$(tr -d ' \t\r\n' < "$CHECKOUT_ROOT/VERSION" 2>/dev/null)
  [ -n "$ANTZ_VERSION" ] || die_internal "cannot read the checkout VERSION: $CHECKOUT_ROOT/VERSION"

  RESULTS_AREA="$BENCH_DIR/results"
  mkdir -p "$RESULTS_AREA" || die_internal "cannot create the results area: $RESULTS_AREA"
  stamp=$(date -u '+%Y%m%dT%H%M%S%3NZ')
  case "$stamp" in
    ''|*[!0-9TZ%]*) stamp=$(date -u '+%Y%m%dT%H%M%SZ') ;;
  esac
  k=2
  while [ -e "$RESULTS_AREA/runs/$stamp" ] || [ -e "$RESULTS_AREA/bench-$stamp.jsonl" ]; do
    stamp="$stamp-$k"; k=$((k + 1))
  done
  RUN_STAMP=$stamp
  RUNS_DIR="$RESULTS_AREA/runs/$stamp"
  mkdir -p "$RUNS_DIR" || die_internal "cannot create the runs dir: $RUNS_DIR"

  if [ -z "$f_jsonl" ]; then
    JSONL="$RESULTS_AREA/bench-$stamp.jsonl"
  else
    JSONL=$f_jsonl
  fi
  jdir=$(dirname -- "$JSONL")
  mkdir -p -- "$jdir" 2>/dev/null
  if ! ( : >> "$JSONL" ) 2>/dev/null; then
    die_internal "results path is not writable: $JSONL"
  fi

  total_rep=0
  appended_rep=0
  for client in $CLIENTS; do
    # The runner sources EXACTLY ONE adapter at a time and calls only its
    # three contract functions (03-adapter).
    bench_source_adapter "$client" || die_internal "adapter vanished for client $client"
    rep=1
    while [ "$rep" -le "$f_repetitions" ]; do
      total_rep=$((total_rep + 1))
      if one_repetition "$client" "$rep"; then
        appended_rep=$((appended_rep + 1))
      fi
      rep=$((rep + 1))
    done
  done

  if [ "$appended_rep" -ne "$total_rep" ]; then
    records_missing=1
  else
    records_missing=0
  fi

  # The aggregate report prints to stdout at the end of the run (the same
  # computation the standalone "report" mode serves).
  if [ -n "$f_baseline" ]; then
    bench_report "$JSONL" "$f_baseline"
  else
    bench_report "$JSONL"
  fi

  [ "$records_missing" -eq 0 ] \
    || die_internal "records missing: $appended_rep of $total_rep repetitions appended a record"
  return 0
}

one_repetition() {
  # $1 = client, $2 = repetition number. Runs one fully isolated repetition
  # (fresh fixture repo, fresh sandbox, deadline-guarded invoke, collect,
  # one appended record) and returns 0 exactly when the record was written.
  # NOTHING aborts the loop: a preparation or client failure still yields
  # its record whenever the record itself can be emitted.
  client="$1"
  rep="$2"
  run_dir="$RUNS_DIR/$client-r$rep"
  mkdir -p -- "$run_dir" \
    || { warn "repetition $client r$rep: cannot create the run dir: $run_dir"; return 1; }
  bench_record_request "$run_dir" \
    || { warn "repetition $client r$rep: the request could not be recorded"; return 1; }

  work=$(mktemp -d "${TMPDIR:-/tmp}/antz-bench-$client-r$rep.XXXXXX") \
    || { warn "repetition $client r$rep: no temp space"; return 1; }
  repo="$work/repo"
  sandbox="$work/sandbox"
  rep_rc=1
  if ! bench_materialize_repo "$repo"; then
    warn "repetition $client r$rep: the fixture could not be materialized"
  elif ! bench_sandbox_create "$sandbox" >/dev/null; then
    warn "repetition $client r$rep: the sandbox could not be prepared"
  else
    do_repetition "$client" "$rep" "$work" "$repo" "$sandbox"
    rep_rc=$?
  fi
  # The repetition's temp world is its own: the repo and sandbox leave with
  # it. The run dir under the results area keeps the audit trail (request
  # copy, raw artifacts, collect keys, marker), and every fact the record
  # carries was measured while it lived.
  rm -rf -- "$work"
  return $rep_rc
}

do_repetition() {
  # $1 client, $2 repetition, $3 work dir, $4 repo, $5 sandbox root. Runs
  # the sourced adapter's invoke under the deadline, saves collect, emits
  # the record, and returns 0 exactly when the record was appended.
  client="$1"
  rep="$2"
  work="$3"
  repo="$4"
  sandbox="$5"
  run_dir="$RUNS_DIR/$client-r$rep"
  case "$client" in
    claude|opencode)
      # The checkout under test is measured: its OWN install.sh renders it
      # into the sandbox; the user's credential is copied in read-only when
      # it exists (skipped, never fabricated, when it does not).
      bench_sandbox_install "$sandbox" "$client" "$CHECKOUT_ROOT" \
        || warn "repetition $client r$rep: the sandbox render failed (the run proceeds)"
      case "$client" in
        claude)
          bench_sandbox_copy_credentials "$HOME/.claude/.credentials.json" \
            "$sandbox/home/.claude/.credentials.json" >/dev/null \
            || warn "repetition $client r$rep: the credential copy failed"
          ;;
        opencode)
          bench_sandbox_copy_credentials "$HOME/.config/opencode/auth.json" \
            "$sandbox/home/.config/opencode/auth.json" >/dev/null \
            || warn "repetition $client r$rep: the credential copy failed"
          ;;
      esac
      ;;
  esac

  export BENCH_SANDBOX="$sandbox"
  export BENCH_MODEL="$f_model"
  export BENCH_REPETITION="$rep"
  if [ -n "$f_dryrun_outcome" ]; then
    export BENCH_DRYRUN_OUTCOME="$f_dryrun_outcome"
  else
    unset BENCH_DRYRUN_OUTCOME
  fi

  started=$(now_ms)
  invoke_under_deadline "$repo" "$run_dir"
  inv_rc=$INV_RC
  wall=$(( $(now_ms) - started ))
  [ "$wall" -ge 0 ] || wall=0
  if [ "$INV_KILLED" = 1 ]; then
    bench_mark_timeout "$run_dir" \
      || warn "repetition $client r$rep: the timeout marker could not be written"
  fi
  if [ ! -f "$run_dir/client.exit" ]; then
    printf '%s\n' "$inv_rc" > "$run_dir/client.exit"
  fi
  exit_code=$(head -n 1 "$run_dir/client.exit" 2>/dev/null)
  case "$exit_code" in
    ''|*[!0-9]*) exit_code=1 ;;
  esac

  if ! bench_collect "$run_dir" "$repo" > "$run_dir/collect.kv"; then
    warn "repetition $client r$rep: collect failed (its record may be refused)"
  fi
  killed_flag=$(bench_deadline_fired "$run_dir")
  outcome=$(bench_outcome_classify "$repo" "$killed_flag") || {
    warn "repetition $client r$rep: the outcome could not be classified"
    return 1
  }
  error_note=null
  case "$outcome" in
    timeout) error_note="the harness deadline of ${f_timeout}s fired and the client was killed" ;;
    error)   error_note="no flow-outcome evidence on disk; the client exited $exit_code" ;;
  esac

  {
    printf 'run_id=%s\n' "$RUN_STAMP-$client-r$rep"
    printf 'timestamp=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'client=%s\n' "$client"
    printf 'antz_version=%s\n' "$ANTZ_VERSION"
    printf 'scenario=%s\n' "$SCENARIO"
    printf 'repetition=%s\n' "$rep"
    if [ -n "$f_model" ]; then printf 'model_pinned=%s\n' "$f_model"; else printf 'model_pinned=null\n'; fi
    printf 'wall_clock_ms=%s\n' "$wall"
    printf 'outcome=%s\n' "$outcome"
    printf 'verifier_rejections=%s\n' "$(bench_count_rejections "$repo")"
    printf 'subspecs_declared=%s\n' "$(bench_count_declared "$repo")"
    printf 'subspecs_receipted=%s\n' "$(bench_count_receipted "$repo")"
    printf 'slug=%s\n' "$(bench_observed_slug "$repo")"
    printf 'exit_code=%s\n' "$exit_code"
    printf 'error_note=%s\n' "$error_note"
    cat -- "$run_dir/collect.kv"
  } | bench_emit_record "$JSONL" \
    || { warn "repetition $client r$rep: its record was refused"; return 1; }
  warn "repetition $client r$rep: outcome $outcome (wall ${wall}ms) -> $JSONL"
  return 0
}

invoke_under_deadline() {
  # $1 = the materialized repo, $2 = the run dir. Runs the sourced adapter's
  # bench_invoke under the --timeout deadline. The adapter keeps the client
  # in its own foreground (03-adapter), so with the invoke backgrounded into
  # its own process group, a deadline kill reaches the client itself. On
  # return: INV_RC (the run's exit status) and INV_KILLED (1 when the
  # harness killed the client at the deadline).
  repo="$1"
  run_dir="$2"
  set -m   # job control: the backgrounded invoke leads its own process group
  (
    bench_invoke "$repo" "$run_dir/request.txt" "$run_dir"
  ) &
  inv_pid=$!
  INV_KILLED=0
  # Deadline watch: sleep-check, doubling the step (0.02s -> 0.25s cap) so
  # fast completions are seen fast and long runs poll cheaply; the wall
  # clock -- never a sleep count -- decides when the deadline has fired.
  inv_start=$(now_ms)
  watch_step=0
  while kill -0 "$inv_pid" 2>/dev/null; do
    [ $(( $(now_ms) - inv_start )) -lt $(( f_timeout * 1000 )) ] || break
    watch_step=$((watch_step + 1))
    case "$watch_step" in
      1) sleep 0.02 ;;
      2) sleep 0.04 ;;
      3) sleep 0.08 ;;
      4) sleep 0.16 ;;
      *) sleep 0.25 ;;
    esac
  done
  if kill -0 "$inv_pid" 2>/dev/null; then
    INV_KILLED=1
    kill -TERM -"$inv_pid" 2>/dev/null || kill -TERM "$inv_pid" 2>/dev/null
  fi
  wait "$inv_pid" 2>/dev/null
  INV_RC=$?
  set +m
  return 0
}

case "$mode" in
  report)
    # Standalone report: same computation as the run-end report, writing
    # only its stdout. It never detects, sources an adapter, or launches
    # anything.
    if [ -n "$f_baseline" ]; then
      bench_report "$f_jsonl" "$f_baseline"
    else
      bench_report "$f_jsonl"
    fi
    ;;
  *)
    run_mode
    ;;
esac

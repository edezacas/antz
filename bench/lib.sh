#!/bin/sh
# bench/lib.sh -- shared library for the antz benchmark harness (change
# telemetry-benchmark). Sourced by bench/antz-bench.sh and by the owning
# suite tests/bench-harness_test.sh; never executed standalone.
#
# Constraints (change-wide invariants): POSIX sh only; awk/sed/grep are the
# only parsing aids; no jq, python, node, or any other non-POSIX
# interpreter. The harness renders the checkout under test into its own
# sandbox when it needs antz; nothing under bench/ is ever installed
# globally.
#
# Requires BENCH_DIR: the directory holding this file, set by the sourcing
# runner before the fixture helpers are called.
#
# Fixture domain (bench-fixture, sub-spec 01): the checked-in fixture under
# "$BENCH_DIR/fixture/" -- "scenario.txt" (the exact request text the
# runner passes as the client prompt) and "repo/" (the toy project the
# request is written against, plain files carrying no git data of their
# own). Per repetition the harness materializes repo/ into a fresh temp
# directory (copy byte-for-byte, git init, one initial commit -- the only
# git the fixture ever has) and records the request bytes verbatim into
# the run dir as "request.txt" (the file the adapter's invoke takes the
# client prompt from), so every record is auditable against the fixture
# and repetitions are comparable. Materialization only ever READS the
# checkout: it never writes inside it.

bench_fix_base() {
  # Internal: print the checked-in fixture directory, or fail loudly when
  # the library precondition (BENCH_DIR naming the bench/ tree) is unmet.
  if [ -z "${BENCH_DIR:-}" ] || [ ! -d "$BENCH_DIR/fixture/repo" ]; then
    echo "bench/lib.sh: set BENCH_DIR to the bench/ directory before sourcing" >&2
    return 1
  fi
  printf '%s\n' "$BENCH_DIR/fixture"
}

bench_git_in() {
  # Internal: run git against the materialized fixture repo at $1. The
  # user's and system's git config are pinned away (GIT_CONFIG_* -> /dev/null)
  # and the committer identity is supplied by the caller with -c, so a
  # materialization is identical on every machine and can never touch any
  # repository outside its own temp destination.
  dest="$1"
  shift
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "$dest" "$@"
}

bench_materialize_repo() {
  # $1 = destination directory (created if absent; meant to be fresh temp
  # space). Copies "$BENCH_DIR/fixture/repo/" into it byte-for-byte, git
  # inits, and makes exactly one initial commit -- the only git state the
  # fixture ever has, and only ever under temp space. Reads the checked-in
  # fixture only; never writes inside the antz checkout.
  fx=$(bench_fix_base) || return 1
  dest="$1"
  mkdir -p -- "$dest" || return 1
  cp -R -- "$fx/repo/." "$dest/" || return 1
  bench_git_in "$dest" init -q || return 1
  bench_git_in "$dest" add -A || return 1
  bench_git_in "$dest" -c user.name=antz-bench -c user.email=antz-bench@example.invalid \
    commit -q -m "antz benchmark fixture: initial commit"
}

bench_request_file() {
  # Print the path of the exact request text the runner passes to the
  # client: the checked-in fixture scenario, verbatim, never regenerated.
  fx=$(bench_fix_base) || return 1
  printf '%s\n' "$fx/scenario.txt"
}

bench_record_request() {
  # $1 = the repetition's run dir (must exist). Record the exact request
  # bytes into the run dir as "request.txt" -- the same file the adapter's
  # invoke passes to the client as its prompt -- so any record is auditable
  # against the fixture after the run and every repetition provably used
  # the same bytes.
  src=$(bench_request_file) || return 1
  run_dir="$1"
  if [ ! -d "$run_dir" ]; then
    echo "bench_record_request: no such run dir: $run_dir" >&2
    return 1
  fi
  cp -- "$src" "$run_dir/request.txt"
}

# Schema domain (bench-schema, sub-spec 02): one common telemetry record --
# a closed, pinned field set in pinned order, appended to the results JSONL
# as one standalone JSON object per repetition. Unavailable values are the
# literal "null" (never 0, never missing); a reported zero stays zero.
# Outcomes are classified only from the materialized fixture repo's disk
# artifacts plus the harness's own kill record -- never from the client's
# conversational output. Counters are observations of the change dir, never
# telemetry.

bench_schema_fields() {
  # The schema's pinned field set, in pinned order (one name per line): the
  # single source of truth for record emission, so every consumer and the
  # suite diff against the same list.
  printf '%s\n' run_id timestamp client antz_version scenario repetition \
    model_pinned wall_clock_ms outcome verifier_rejections subspecs_declared \
    subspecs_receipted slug exit_code error_note client_version \
    client_duration_ms tokens_input tokens_output tokens_reasoning \
    tokens_cache_read tokens_cache_write cost_usd turns tool_calls \
    subagent_delegations models_used session_id
}

bench_emit_record() {
  # $1 = the results JSONL file; stdin = "key=value" lines, one per pinned
  # field (exactly the collect contract's shape, plus the runner-owned
  # fields). The literal value "null" means unavailable, so a field the
  # client never reported is emitted as JSON null, never as 0 and never
  # dropped.
  #
  # The record is validated whole -- closed field set (every pinned field
  # exactly once, no extras), pinned types and semantics (wall clock and the
  # counters never null; metrics null-or-number >= 0; outcome within the
  # pinned vocabulary; error_note non-null exactly when the outcome is
  # "error" or "timeout") -- and only then appended, as one line of valid
  # JSON in the pinned field order. Any violation: a diagnostic on stderr,
  # non-zero exit, and NOTHING is written -- the JSONL never gains a
  # partial record.
  if [ "$#" -ne 1 ]; then
    echo "usage: bench_emit_record <jsonl-file> < key=value-lines" >&2
    return 2
  fi
  fields=$(bench_schema_fields | tr '\n' ' ') || return 1
  if ! rec=$(awk -v fields="$fields" '
    function fail(m) { print "bench_emit_record: " m > "/dev/stderr"; bad = 1; exit 1 }
    function jstr(s,  i, n, ch, out) {
      # JSON-encode a string value: escape backslash, quote, tab, CR.
      out = "\""; n = length(s)
      for (i = 1; i <= n; i++) {
        ch = substr(s, i, 1)
        if (ch == "\\") out = out "\\\\"
        else if (ch == "\"") out = out "\\\""
        else if (ch == "\t") out = out "\\t"
        else if (ch == "\r") out = out "\\r"
        else out = out ch
      }
      return out "\""
    }
    BEGIN {
      nf = split(fields, ord, " ")
      split("repetition wall_clock_ms verifier_rejections subspecs_declared subspecs_receipted exit_code", a, " ")
      for (i = 1; i in a; i++) cls[a[i]] = "int_nn"
      split("client_duration_ms tokens_input tokens_output tokens_reasoning tokens_cache_read tokens_cache_write turns tool_calls subagent_delegations", a, " ")
      for (i = 1; i in a; i++) cls[a[i]] = "int_n"
      split("cost_usd", a, " ")
      for (i = 1; i in a; i++) cls[a[i]] = "num_n"
      split("run_id timestamp client antz_version scenario outcome", a, " ")
      for (i = 1; i in a; i++) cls[a[i]] = "str_nn"
      split("model_pinned slug error_note client_version models_used session_id", a, " ")
      for (i = 1; i in a; i++) cls[a[i]] = "str_n"
      split("approved rejected blocked open-question timeout error", a, " ")
      for (i = 1; i in a; i++) outcome_ok[a[i]] = 1
    }
    {
      if (bad) exit 1
      eq = index($0, "=")
      if (eq < 2) fail("malformed input line (not key=value): [" $0 "]")
      key = substr($0, 1, eq - 1)
      val = substr($0, eq + 1)
      if (!(key in cls)) fail("unknown field: " key)
      if (key in seen) fail("duplicate field: " key)
      seen[key] = 1
      v[key] = val
    }
    END {
      if (bad) exit 1
      if (NR == 0) fail("no fields at all")
      for (i = 1; i <= nf; i++)
        if (!(ord[i] in seen)) fail("missing field: " ord[i])
      for (i = 1; i <= nf; i++) {
        k = ord[i]; x = v[k]; c = cls[k]
        if (c ~ /_nn$/ && x == "null") fail(k " must never be null")
        if (c == "int_nn" && x !~ /^[0-9]+$/) fail(k " must be an integer >= 0")
        if (c == "int_n" && x != "null" && x !~ /^[0-9]+$/) fail(k " must be null or an integer >= 0")
        if (c == "num_n" && x != "null" && x !~ /^[0-9]+(\.[0-9]+)?$/) fail(k " must be null or a number >= 0")
      }
      if (!(v["outcome"] in outcome_ok)) fail("outcome not in the pinned vocabulary: " v["outcome"])
      noted = (v["error_note"] != "null")
      wanted = (v["outcome"] == "error" || v["outcome"] == "timeout")
      if (noted && !wanted) fail("error_note must be null unless the outcome is error or timeout")
      if (!noted && wanted) fail("error_note must be non-null when the outcome is error or timeout")
      out = "{"
      for (i = 1; i <= nf; i++) {
        k = ord[i]; x = v[k]; c = cls[k]
        out = out (i > 1 ? "," : "") "\"" k "\":"
        if (x == "null") out = out "null"
        else if (c ~ /^(int|num)_/) out = out x
        else out = out jstr(x)
      }
      print out "}"
    }
  '
  ); then
    return 1
  fi
  printf '%s\n' "$rec" >> "$1"
}

bench_change_dirs() {
  # Internal: print the fixture repo's change dirs (one path per line,
  # sorted), i.e. every "spdd/changes/<slug>/" directory -- the ones the
  # flow created, since a materialized fixture starts with no spdd/ at all.
  repo="$1"
  find "$repo/spdd/changes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort
}

bench_outcome_classify() {
  # $1 = the materialized fixture repo; $2 = "1" when the harness deadline
  # fired and killed the client (the harness's own kill record), else "0".
  # Prints the repetition's outcome, classified ONLY from the repo's disk
  # artifacts and that kill record -- never from any client output -- in the
  # pinned precedence order, first match wins:
  #   1 approved      any directory exists under "spdd/archive/"
  #   2 blocked       a receipt ("NN-*.result" in a change dir) carrying a
  #                   "result=blocked" line, or any change-dir artifact
  #                   carrying a line-start "BLOCKED: "
  #   3 rejected      "REJECTED.md" exists in the change dir
  #   4 open-question "OPEN_QUESTIONS.md" exists in the change dir
  #   5 timeout       the harness deadline fired and killed the client
  #   6 error         none of the above
  repo="$1"
  killed="${2:-0}"
  changes="$repo/spdd/changes"
  if find "$repo/spdd/archive" -mindepth 1 -type d 2>/dev/null | grep -q .; then
    printf 'approved\n'
    return 0
  fi
  # receipts with a result=blocked line (top level of each change dir), or
  # any change-dir artifact carrying a line-start BLOCKED: refusal
  if find "$changes" -mindepth 2 -maxdepth 2 -type f -name '[0-9][0-9]-*.result' \
      -exec grep -l 'result=blocked' {} \; 2>/dev/null | grep -q . ||
     find "$changes" -mindepth 2 -type f \
      -exec grep -l '^BLOCKED: ' {} \; 2>/dev/null | grep -q .; then
    printf 'blocked\n'
    return 0
  fi
  if find "$changes" -mindepth 2 -maxdepth 2 -type f -name REJECTED.md 2>/dev/null | grep -q .; then
    printf 'rejected\n'
    return 0
  fi
  if find "$changes" -mindepth 2 -maxdepth 2 -type f -name OPEN_QUESTIONS.md 2>/dev/null | grep -q .; then
    printf 'open-question\n'
    return 0
  fi
  if [ "$killed" = "1" ]; then
    printf 'timeout\n'
    return 0
  fi
  printf 'error\n'
}

bench_observed_slug() {
  # $1 = the materialized fixture repo. Print the comma-joined slug(s) of
  # the change dir(s) the flow created (sorted), or the literal "null" when
  # it created none -- the schema's "slug" value.
  slugs=$(bench_change_dirs "$1" | sed 's#.*/##' | LC_ALL=C paste -sd, -)
  if [ -n "$slugs" ]; then
    printf '%s\n' "$slugs"
  else
    printf 'null\n'
  fi
}

bench_count_declared() {
  # $1 = the fixture repo. The count of "NN-*.feature" sub-spec files across
  # the flow's change dir(s) (top level); 0 when there is no change dir.
  # Always a present integer >= 0 -- an observation, never null.
  find "$1/spdd/changes" -mindepth 2 -maxdepth 2 -type f -name '[0-9][0-9]-*.feature' 2>/dev/null \
    | awk 'END { print NR + 0 }'
}

bench_count_receipted() {
  # $1 = the fixture repo. The count of "NN-*.result" receipt files across
  # the flow's change dir(s) (top level); 0 when there is no change dir.
  find "$1/spdd/changes" -mindepth 2 -maxdepth 2 -type f -name '[0-9][0-9]-*.result' 2>/dev/null \
    | awk 'END { print NR + 0 }'
}

bench_count_rejections() {
  # $1 = the fixture repo. The number of "## Rejection " headings across the
  # change dir(s)' "REJECTED.md" files; 0 when the file is absent (or there
  # is no change dir).
  find "$1/spdd/changes" -mindepth 2 -maxdepth 2 -type f -name REJECTED.md 2>/dev/null \
    | while IFS= read -r f; do
        grep -c '^## Rejection ' "$f" 2>/dev/null || :
      done \
    | awk '{ s += $1 } END { print s + 0 }'
}

# Adapter domain (bench-adapter, sub-spec 03): every client adapter is a
# POSIX sh file "$BENCH_DIR/adapter-<client>.sh" defining exactly the three
# contract functions bench_detect / bench_invoke / bench_collect. The runner
# sources EXACTLY ONE adapter file per run (through bench_source_adapter
# below) and calls only that adapter's three functions: detect answers
# whether the client is usable (exit 0 + a non-empty version string printed;
# non-zero when not), invoke launches the client headless as the
# antz-orchestrator against the materialized fixture repo with the run's
# request file and run dir, and collect normalizes the run dir's artifacts
# into the pinned telemetry keys ("key=value" lines, the literal "null"
# where unavailable). The dry-run adapter (bench/adapter-dryrun.sh) is the
# hermetic mock client: always detected, no network, no credentials, no real
# binary, scripted outcomes and deterministic telemetry.

bench_run_artifacts() {
  # The pinned per-repetition run-dir artifact names, one per line, in run
  # order -- the single source of truth for the convention:
  #   request.txt     the exact request bytes (sub-spec 01, via
  #                   bench_record_request); the file invoke takes the client
  #                   prompt from
  #   client.stdout   the client process's raw stdout (written by invoke)
  #   client.stderr   the client process's raw stderr (written by invoke)
  #   client.exit     the client's exit code, one integer line (written by
  #                   invoke on a normal completion; when the harness's
  #                   deadline killed the client, the harness records the
  #                   kill status here instead -- invoke is dead by then)
  #   client.timeout  the harness's timeout marker, created by
  #                   bench_mark_timeout exactly when the deadline fired and
  #                   killed the client
  #   collect.kv      the "key=value" lines collect printed, saved by the
  #                   runner so the repetition's telemetry is auditable
  printf '%s\n' request.txt client.stdout client.stderr client.exit client.timeout collect.kv
}

bench_source_adapter() {
  # $1 = client name (a safe token, e.g. "dryrun"). Source EXACTLY ONE
  # adapter, "$BENCH_DIR/adapter-<client>.sh", and refuse (non-zero, before
  # anything is usable) an unknown client, an invalid name, or an adapter
  # file that does not define the full three-function contract. After a
  # successful return, bench_detect / bench_invoke / bench_collect are the
  # selected adapter's and the run calls only those three.
  if [ "$#" -ne 1 ]; then
    echo "usage: bench_source_adapter <client-name>" >&2
    return 2
  fi
  if [ -z "${BENCH_DIR:-}" ]; then
    echo "bench_source_adapter: set BENCH_DIR to the bench/ directory before sourcing" >&2
    return 1
  fi
  client="$1"
  case "$client" in
    ''|*[!A-Za-z0-9._-]*)
      echo "bench_source_adapter: invalid client name: [$client]" >&2
      return 2
      ;;
  esac
  adapter_file="$BENCH_DIR/adapter-$client.sh"
  if [ ! -f "$adapter_file" ]; then
    echo "bench_source_adapter: no adapter for client [$client]: $adapter_file" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  . "$adapter_file" || return 1
  missing=""
  for bench_contract_fn in bench_detect bench_invoke bench_collect; do
    if ! command -v "$bench_contract_fn" >/dev/null 2>&1; then
      missing="$missing $bench_contract_fn"
    fi
  done
  if [ -n "$missing" ]; then
    echo "bench_source_adapter: $adapter_file misses the adapter contract:$missing" >&2
    return 1
  fi
  return 0
}

bench_mark_timeout() {
  # $1 = the repetition's run dir. The harness's kill record: call this
  # exactly when the per-repetition deadline fired and the client was
  # killed; it leaves the run dir's timeout marker (a name pinned by
  # bench_run_artifacts).
  run_dir="$1"
  if [ ! -d "$run_dir" ]; then
    echo "bench_mark_timeout: no such run dir: $run_dir" >&2
    return 1
  fi
  printf 'harness deadline fired at %s: client killed\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$run_dir/client.timeout"
}

bench_deadline_fired() {
  # $1 = the repetition's run dir. Print "1" when the timeout marker is
  # there (the harness killed the client), else "0" -- the flag
  # bench_outcome_classify takes as its timeout evidence.
  if [ -f "$1/client.timeout" ]; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

# Clients domain (bench-clients, sub-spec 04): per-repetition sandbox,
# checkout rendering, credential copying, the minimal allowlist environment,
# and the generic JSON readers both real adapters parse with. The sandbox is
# the client process's only writable world: a fresh tree under temp space
# (bench_sandbox_create), the checkout under test rendered into it by its own
# install.sh (bench_sandbox_install), the user's real credentials copied in
# read-only (bench_sandbox_copy_credentials), and the client launched through
# bench_sandbox_run, which passes ONLY the allowlist -- PATH, HOME, TMPDIR,
# the sandbox's relocated config/data variables, and the pinned-model
# variable BENCH_MODEL (forwarded only when a model is pinned). No other
# variable from the invoking shell passes through: ANTHROPIC_*, CLAUDE_*, or
# OPENCODE_* values of the user's environment are invisible to the client.
#
# Runner-owned environment the adapters expect: BENCH_SANDBOX = the sandbox
# root prepared by bench_sandbox_create; BENCH_MODEL = the pinned model
# value, empty or unset when nothing is pinned.
#
# Layout (deliberate): CLAUDE_CONFIG_DIR and XDG_CONFIG_HOME point at the
# directories install.sh writes under HOME ($HOME/.claude, $HOME/.config), so
# the agents the render installs and the agents the client reads are the same
# files; XDG_DATA_HOME stays under its own sandbox branch.

bench_sandbox_create() {
  # $1 = sandbox root: a path that does not exist yet, or exists empty (the
  # root must be fresh -- a reused tree is refused, so no repetition can
  # inherit another's writes). Creates HOME and the relocated directories
  # under $1; prints the root on success.
  if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: bench_sandbox_create <sandbox-root>" >&2
    return 2
  fi
  root="$1"
  if [ -e "$root" ]; then
    if [ ! -d "$root" ]; then
      echo "bench_sandbox_create: not a directory: $root" >&2
      return 2
    fi
    if [ -n "$(ls -A -- "$root" 2>/dev/null)" ]; then
      echo "bench_sandbox_create: refusing a reused, non-empty sandbox root: $root" >&2
      return 2
    fi
  fi
  mkdir -p -- "$root/home/.claude" "$root/home/.config" \
    "$root/home/.local/share" "$root/tmp" || return 1
  printf '%s\n' "$root"
}

bench_sandbox_env() {
  # $1 = sandbox root. Print the client process's minimal allowlist
  # environment, one KEY=VALUE per line: the relocation variables all point
  # inside the sandbox, PATH carries over so the client finds its own
  # binaries, and BENCH_MODEL is included ONLY when a model is pinned. The
  # real config/data roots are NOT part of the environment at all -- no
  # USER_* escape hatch to the user's world.
  if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: bench_sandbox_env <sandbox-root>" >&2
    return 2
  fi
  root="$1"
  printf 'PATH=%s\n' "${PATH:-}"
  printf 'HOME=%s\n' "$root/home"
  printf 'TMPDIR=%s\n' "$root/tmp"
  printf 'XDG_CONFIG_HOME=%s\n' "$root/home/.config"
  printf 'XDG_DATA_HOME=%s\n' "$root/home/.local/share"
  printf 'CLAUDE_CONFIG_DIR=%s\n' "$root/home/.claude"
  if [ -n "${BENCH_MODEL:-}" ]; then
    printf 'BENCH_MODEL=%s\n' "$BENCH_MODEL"
  fi
}

bench_shquote() {
  # Internal: print $1 quoted as a single POSIX shell word (single quotes,
  # embedded ones re-quoted), for the eval-built env -i command line. The
  # printf-x sentinel keeps the word's TRAILING NEWLINES through command
  # substitution, so a multi-line argv token (the verbatim request text)
  # survives the quoting trip byte-for-byte.
  _bsq=$(printf '%s' "$1" | sed "s/'/'\\\\''/g"; printf x)
  _bsq=${_bsq%x}
  printf "'%s'" "$_bsq"
}

bench_sandbox_run() {
  # $1 = sandbox root, rest = command argv. Run the command under
  # `env -i` with EXACTLY the bench_sandbox_env allowlist: a variable that
  # is not on the list cannot reach the child, however the invoking shell
  # exported it. Returns the command's exit status.
  if [ "$#" -lt 2 ]; then
    echo "usage: bench_sandbox_run <sandbox-root> <command> [args...]" >&2
    return 2
  fi
  root="$1"
  shift
  if [ ! -d "$root/home" ] || [ ! -d "$root/tmp" ]; then
    echo "bench_sandbox_run: not a prepared sandbox root: $root" >&2
    return 2
  fi
  _bsr_argv=""
  for _bsr_word in "$@"; do
    _bsr_argv="$_bsr_argv $(bench_shquote "$_bsr_word")"
  done
  if [ -z "$_bsr_argv" ]; then
    echo "bench_sandbox_run: no command given" >&2
    return 2
  fi
  _bsr_list=""
  while IFS= read -r _bsr_assign; do
    _bsr_list="$_bsr_list $(bench_shquote "$_bsr_assign")"
  done <<BSR_ENV
$(bench_sandbox_env "$root")
BSR_ENV
  # The full command line is assembled as ONE quoted string before eval:
  # letting the pre-quoted words through an unquoted expansion would split
  # them at embedded newlines/tabs, which a multi-line argv token (the
  # verbatim request text) must not survive mangled.
  eval "env -i $_bsr_list $_bsr_argv"
}

bench_sandbox_install() {
  # $1 = sandbox root, $2 = client (claude | opencode), $3 = the antz
  # checkout under test. Render the checkout into the sandbox by running ITS
  # OWN install.sh, inside the sandbox environment, with the explicit
  # per-client flag (the flag skips detection and the local-checkout path
  # never touches the network). After this returns 0 the sandbox's agents
  # directory and the sandbox libdir (${XDG_CONFIG_HOME}/antz/scripts) carry
  # the checkout's content -- never the machine's global install.
  if [ "$#" -ne 3 ]; then
    echo "usage: bench_sandbox_install <sandbox-root> <claude|opencode> <checkout-dir>" >&2
    return 2
  fi
  root="$1"
  client="$2"
  co="${3%/}"
  case "$client" in
    claude) flag=--claude ;;
    opencode) flag=--opencode ;;
    *)
      echo "bench_sandbox_install: client must be claude or opencode: $client" >&2
      return 2
      ;;
  esac
  if [ ! -f "$co/install.sh" ] || [ ! -d "$co/agents/prompts" ]; then
    echo "bench_sandbox_install: not an antz checkout (no install.sh + agents/prompts): $co" >&2
    return 2
  fi
  bench_sandbox_run "$root" sh "$co/install.sh" "$flag"
}

bench_sandbox_copy_credentials() {
  # $1 = source credential file (the user's real one), $2 = destination path
  # inside the sandbox. When the source exists it is copied and the copy is
  # made read-only; the source itself is never modified. When it does not
  # exist the step is SKIPPED -- nothing is fabricated and the run proceeds
  # (a client with no credential surfaces its own failure, which the outcome
  # classification records as error). Prints 'copied <src> -> <dst>' or
  # 'skipped <src>'.
  if [ "$#" -ne 2 ]; then
    echo "usage: bench_sandbox_copy_credentials <src-file> <dst-file>" >&2
    return 2
  fi
  src="$1"
  dst="$2"
  if [ ! -f "$src" ]; then
    printf 'skipped %s\n' "$src"
    return 0
  fi
  mkdir -p -- "$(dirname -- "$dst")" || return 1
  cp -- "$src" "$dst" || return 1
  chmod a-w -- "$dst" || return 1
  printf 'copied %s -> %s\n' "$src" "$dst"
}

# The generic JSON readers the real-client adapters parse their telemetry
# artifacts with (awk is the sanctioned aid; no jq, no interpreter). The
# scanner is string-aware: braces, brackets and colons inside JSON strings
# never move the walk, arrays are transparent (any element may satisfy the
# remaining path), and a top-level SEQUENCE of JSON documents (the OpenCode
# run events, one object per line) is scanned left to right. The walk is
# document order, first match wins.

bench_json_get() {
  # $1 = file holding JSON, $2 = dotted path of object keys
  # (e.g. usage.input_tokens, or info.tokens.cache.read). Prints the scalar
  # at that path -- a string unquoted, a number or true/false literal --
  # and nothing at all when the path does not resolve.
  if [ "$#" -ne 2 ] || [ ! -f "$1" ]; then
    return 2
  fi
  awk -v path="$2" '
    function ws(s, i,   n, c) {
      n = length(s)
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == "\n" || c == "\r") { i++; continue }
        break
      }
      return i
    }
    # read_string: s[j] is the opening quote. Sets RSTR to the (escape-
    # flattened) content and returns the index just after the closing quote.
    function read_string(s, j,   n, c, out) {
      n = length(s); out = ""; j++
      while (j <= n) {
        c = substr(s, j, 1)
        if (c == "\\") { out = out substr(s, j, 2); j += 2; continue }
        if (c == "\"") { RSTR = out; return j + 1 }
        out = out c; j++
      }
      RSTR = out; return n + 1
    }
    # skip_value: return the index just past the value that starts at j
    # (whitespace-skipped first). For plain literals the terminator itself
    # is returned -- callers skip commas and whitespace anyway.
    function skip_value(s, j,   n, c, d, k) {
      n = length(s)
      j = ws(s, j)
      if (j > n) return n + 1
      c = substr(s, j, 1)
      if (c == "\"") return read_string(s, j)
      if (c == "{" || c == "[") {
        d = 0; k = j
        while (k <= n) {
          c = substr(s, k, 1)
          if (c == "\"") { k = read_string(s, k) - 1 }
          else if (c == "{" || c == "[") d++
          else if (c == "}" || c == "]") { d--; if (d == 0) return k + 1 }
          k++
        }
        return n + 1
      }
      while (j <= n) {
        c = substr(s, j, 1)
        if (c == "," || c == "}" || c == "]") return j
        j++
      }
      return n + 1
    }
    # find_key: scan containers/elements starting at `from`, where `from`
    # points AT a {/[ value or just INSIDE one (both are handled: a { or [
    # at i descends into i+1). Return the index just past the first `key:`
    # found in document order, or 0.
    function find_key(s, from, key,   n, i, c, j, after, found) {
      n = length(s); i = from
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == "\n" || c == "\r" || c == ",") { i++; continue }
        if (c == "}" || c == "]") return 0
        if (c == "{" || c == "[") {
          found = find_key(s, i + 1, key)
          if (found) return found
          i = skip_value(s, i); continue
        }
        if (c == "\"") {
          j = read_string(s, i)
          after = ws(s, j)
          if (substr(s, after, 1) == ":") {
            if (RSTR == key) return after + 1
            i = skip_value(s, after + 1); continue
          }
          i = j; continue   # a bare string element
        }
        i = skip_value(s, i); continue   # a bare literal element
      }
      return 0
    }
    { buf = buf $0 "\n" }
    END {
      nk = split(path, keys, ".")
      pos = 1
      for (k = 1; k <= nk; k++) {
        pos = find_key(buf, pos, keys[k])
        if (pos == 0) exit 1
        pos = ws(buf, pos)
        if (k < nk) {
          c = substr(buf, pos, 1)
          if (c != "{" && c != "[") exit 1
        }
      }
      c = substr(buf, pos, 1)
      if (c == "\"") { read_string(buf, pos); print RSTR; exit 0 }
      if (c == "{" || c == "[") exit 1   # not a scalar
      j = pos; n = length(buf)
      while (j <= n) {
        c = substr(buf, j, 1)
        if (c == "," || c == "}" || c == "]" || c == "\n" || c == " " || c == "\t" || c == "\r") break
        j++
      }
      v = substr(buf, pos, j - pos)
      gsub(/^[ \t\r]+|[ \t\r]+$/, "", v)
      if (v != "") print v
    }
  ' "$1" 2>/dev/null
}

# Numeric helpers: exact decimal add/subtract (the cost and duration
# arithmetic), printing the canonical minimal decimal form.

bench_num_add() {
  awk -v a="$1" -v b="$2" 'BEGIN { s = (a + b); t = sprintf("%.10f", s); sub(/0+$/, "", t); sub(/\.$/, "", t); print t }'
}

bench_num_sub() {
  awk -v a="$1" -v b="$2" 'BEGIN { s = (a - b); if (s == 0) s = 0; t = sprintf("%.10f", s); sub(/0+$/, "", t); sub(/\.$/, "", t); print t }'
}

# Claude result-JSON scalars (single-occurrence keys, first match wins).

bench_claude_result_num() {
  # $1 = result JSON file, $2 = key; prints the number or nothing.
  bench_json_get "$1" "$2" 2>/dev/null | grep -E '^[0-9]+(\.[0-9]+)?$' || :
}

bench_claude_result_str() {
  # $1 = result JSON file, $2 = key; prints the string value or nothing.
  bench_json_get "$1" "$2" 2>/dev/null | head -n 1
}

bench_claude_result_models() {
  # $1 = result JSON file: the modelUsage object's top-level keys (the
  # per-model usage maps), comma-joined in document order, or nothing.
  [ -f "$1" ] || return 0
  awk '
    { buf = buf $0 "\n" }
    END {
      i = index(buf, "\"modelUsage\"")
      if (i == 0) exit 0
      s = substr(buf, i)
      b = index(s, "{")
      if (b == 0) exit 0
      n = length(s); d = 0; instr = 0; esc = 0; cur = ""; out = ""
      for (k = b; k <= n; k++) {
        c = substr(s, k, 1)
        if (esc) { esc = 0; if (instr) { cur = cur "\\" }; continue }
        if (instr) {
          if (c == "\\") { esc = 1; continue }
          if (c == "\"") {
            instr = 0
            if (d == 1) {
              j = k + 1
              while (j <= n && substr(s, j, 1) ~ /[ \t\r\n]/) j++
              if (substr(s, j, 1) == ":") out = out (out == "" ? "" : ",") cur
            }
            cur = ""; continue
          }
          cur = cur c; continue
        }
        if (c == "\"") { instr = 1; cur = ""; continue }
        if (c == "{") d++
        else if (c == "}") { d--; if (d == 0) break }
      }
      print out
    }
  ' "$1" 2>/dev/null
}

# The Claude session-transcript reader: the sidechain attribution the
# claude adapter sums. A transcript is JSONL; this prints the run-dir
# telemetry scalars as key=value lines: tools (count of tool_use blocks over
# ALL entries, primary and sidechain), and over the "isSidechain":true
# entries only -- su (usage-carrying lines), tin/tout/tcr/tcw (token adds),
# tcost (summed costUSD), nocost (usage lines the transcript does not
# price), del (distinct agentId values). A line carrying usage adds it even
# without a cost; the cost side is what nocost makes unattributable.

bench_claude_transcript_kv() {
  # $1 = transcript JSONL file. Prints nothing when the file is absent.
  [ -f "$1" ] || return 0
  awk '
    BEGIN { tin = 0; tout = 0; tcr = 0; tcw = 0; tcost = 0; su = 0; nocost = 0; tools = 0; del = 0 }
    function lnum(line, key) {
      pat = "\"" key "\"[ \t]*:[ \t]*-?[0-9]+(\\.[0-9]+)?"
      if (match(line, pat)) {
        v = substr(line, RSTART, RLENGTH)
        sub(/^"[^"]*"[ \t]*:[ \t]*/, "", v)
        return v
      }
      return ""
    }
    {
      copy = $0
      tools += gsub(/"type"[ \t]*:[ \t]*"tool_use"/, "x", copy)
    }
    $0 ~ /"isSidechain"[ \t]*:[ \t]*true/ {
      vi = lnum($0, "input_tokens")
      vo = lnum($0, "output_tokens")
      vr = lnum($0, "cache_read_input_tokens")
      vc = lnum($0, "cache_creation_input_tokens")
      if (vi != "" || vo != "" || vr != "" || vc != "") {
        su++
        if (vi != "") tin += vi
        if (vo != "") tout += vo
        if (vr != "") tcr += vr
        if (vc != "") tcw += vc
        vs = lnum($0, "costUSD")
        if (vs == "") nocost++
        else tcost += vs
      }
      va = ""
      if (match($0, /"agentId"[ \t]*:[ \t]*"[^"]*"/)) {
        va = substr($0, RSTART, RLENGTH)
        sub(/^"agentId"[ \t]*:[ \t]*"/, "", va)
        sub(/"$/, "", va)
      }
      if (va != "" && !(va in seen)) { seen[va] = 1; del++ }
    }
    END {
      printf "tin=%d\ntout=%d\ntcr=%d\ntcw=%d\ntcost=%.10f\n", tin, tout, tcr, tcw, tcost
      printf "su=%d\nnocost=%d\ntools=%d\ndel=%d\n", su, nocost, tools, del
    }
  ' "$1" 2>/dev/null
}

# The OpenCode export reader: an `opencode export <sessionID>` document,
# printed as telemetry-relevant key=value lines -- info-model, info-cost,
# info-tokens (input / output / reasoning / cache-read / cache-write) and
# info-created / info-updated (all read through the path-scoped JSON getter,
# so per-step token/cost parts under "messages" can never masquerade as the
# session totals), tool-parts / task-parts (whole-document counts of tool
# parts and of task parts -- a delegation is an observed count, so it prints
# 0 when none were seen), and one child=<id> line per child (delegated)
# session a task part names in its state.metadata (either casing, sessionID
# or sessionId). A value the document does not carry is omitted, never
# guessed. Handles pretty-printed and compact JSON alike.

bench_opencode_export_kv() {
  f="$1"
  [ -f "$f" ] || return 0
  _boe_v=$(bench_json_get "$f" info.model);        [ -n "$_boe_v" ] && printf 'info-model=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.cost);         [ -n "$_boe_v" ] && printf 'info-cost=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.tokens.input);     [ -n "$_boe_v" ] && printf 'info-tokens-input=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.tokens.output);    [ -n "$_boe_v" ] && printf 'info-tokens-output=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.tokens.reasoning); [ -n "$_boe_v" ] && printf 'info-tokens-reasoning=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.tokens.cache.read);  [ -n "$_boe_v" ] && printf 'info-tokens-cache-read=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.tokens.cache.write); [ -n "$_boe_v" ] && printf 'info-tokens-cache-write=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.time.created); [ -n "$_boe_v" ] && printf 'info-created=%s\n' "$_boe_v"
  _boe_v=$(bench_json_get "$f" info.time.updated); [ -n "$_boe_v" ] && printf 'info-updated=%s\n' "$_boe_v"
  awk '
    { buf = buf " " $0 }
    END {
      t = buf; c1 = 0
      while (match(t, /"type"[ \t]*:[ \t]*"tool"/)) { c1++; t = substr(t, RSTART + RLENGTH) }
      print "tool-parts=" c1
      t = buf; c2 = 0
      while (match(t, /"tool"[ \t]*:[ \t]*"task"/)) { c2++; t = substr(t, RSTART + RLENGTH) }
      print "task-parts=" c2
      t = buf
      while (match(t, /"metadata"[ \t]*:[ \t]*{[^}]*"session[Ii][dD]"[ \t]*:[ \t]*"[^"]*"/)) {
        v = substr(t, RSTART, RLENGTH)
        sub(/.*"session[Ii][dD]"[ \t]*:[ \t]*"/, "", v)
        sub(/"$/, "", v)
        print "child=" v
        t = substr(t, RSTART + RLENGTH)
      }
    }
  ' "$f" 2>/dev/null
  return 0
}

# Report domain (bench-report, sub-spec 06): the single seam through which
# the runner's end-of-run report and the standalone "report" mode are the
# same computation:
#   bench_report <results.jsonl> [<baseline.jsonl>]   -> report on stdout
# The runner redirects nothing else to stdout in run mode, and report mode
# launches no client and writes no file. The statistics are pinned: n,
# arithmetic mean, standard median (the mean of the two middle sorted
# values when n is even), min, max, and nearest-rank p95 (the
# ceil(0.95*n)-th of the sorted values), over the non-null values only --
# nulls are excluded and an all-null metric reports null statistics, never
# fabricated zeros; a metric no record of the group carries is reported
# absent without failing the report. Grouping is per client (first-seen
# order); each group names the distinct model_pinned values seen and its
# outcome distribution. With a baseline, a comparison section prints the
# baseline mean and median beside the current ones with a signed mean
# delta for every client and metric present on both sides; a one-sided
# client or metric is named absent on the other side, never a zero or null
# delta. Both files are read-only inputs; the output is deterministic for
# a given input (all orderings are first-seen or sorted). Numbers print
# exact to the 6th decimal with trailing zeros trimmed (an IEEE artifact
# like 0.029999999999999995 lands back on 0.03); the JSONL line format is
# bench_emit_record's own compact, key-order-pinned shape.

bench_report_metrics() {
  # The report's pinned closed metric set, one name per line, in the
  # pinned order: exactly these fields carry statistics.
  printf '%s\n' wall_clock_ms client_duration_ms tokens_input tokens_output \
    tokens_reasoning tokens_cache_read tokens_cache_write cost_usd turns \
    tool_calls subagent_delegations
}

bench_report() {
  # $1 = the results JSONL (read-only); $2 = optional baseline JSONL
  # (read-only). Prints the aggregate report to stdout; never writes
  # either input, launches nothing, or touches anything else.
  if [ "$#" -lt 1 ] || [ -z "$1" ]; then
    echo "usage: bench_report <results.jsonl> [<baseline.jsonl>]" >&2
    return 2
  fi
  if [ ! -f "$1" ]; then
    echo "bench_report: no such results file: $1" >&2
    return 1
  fi
  baseline=""
  if [ "$#" -ge 2 ]; then
    baseline=$2
    if [ ! -f "$baseline" ]; then
      echo "bench_report: no such baseline file: $baseline" >&2
      return 1
    fi
  fi
  metrics=$(bench_report_metrics | tr '\n' ' ') || return 1
  awk -v f1="$1" -v bfile="$baseline" -v metrics="$metrics" '
    # fmt: the canonical print form -- 6-decimal rounded (killing IEEE
    # summation artifacts), trailing zeros and a bare point trimmed.
    function fmt(x,   t) {
      t = sprintf("%.6f", x)
      sub(/0+$/, "", t)
      sub(/\.$/, "", t)
      if (t == "" || t == "-" || t == "-0" || t == "0") return "0"
      return t
    }
    function fmt_signed(x) {
      if (x < 0) return fmt(x)
      return "+" fmt(x)
    }
    # svalue: the value of a string field, "" when the key is absent or
    # the value is not a string.
    function svalue(line, k,   pat, v) {
      pat = "\"" k "\":[ \t]*\"[^\"]*\""
      if (!match(line, pat)) return ""
      v = substr(line, RSTART, RLENGTH)
      sub(/^"[^"]*":[ \t]*"/, "", v)
      sub(/"$/, "", v)
      return v
    }
    # metric_slot: what a record says about metric k -- "x" the key is
    # absent, "n" present but no usable value (null), or "v" SUBSEP value.
    function metric_slot(line, k,   pat, v) {
      pat = "\"" k "\":[ \t]*[^,} \t]+"
      if (!match(line, pat)) return "x"
      v = substr(line, RSTART, RLENGTH)
      sub(/^"[^"]*":[ \t]*/, "", v)
      if (v == "null") return "n"
      if (v ~ /^[0-9]+(\.[0-9]+)?$/) return "v" SUBSEP v
      return "n"
    }
    # read_file: fold one JSONL into dataset d (1 = results, 2 =
    # baseline): first-seen group order, record counts, outcome
    # distribution, distinct pinned models, and per (group, metric) the
    # seen flag with the non-null values.
    function read_file(fn, d,   line, c, o, mo, i, s, v, kk) {
      while ((getline line < fn) > 0) {
        c = svalue(line, "client")
        if (c == "") continue
        if (!((d SUBSEP c) in gseen)) {
          gseen[d, c] = 1
          ng[d]++
          grp[d, ng[d]] = c
        }
        recs[d, c]++
        o = svalue(line, "outcome")
        if (o == "") o = "unknown"
        if (!((d SUBSEP c SUBSEP o) in odist)) {
          odist[d, c, o] = 0
          oc[d, c]++
          ol[d, c, oc[d, c]] = o
        }
        odist[d, c, o]++
        mo = svalue(line, "model_pinned")
        if (mo != "" && !((d SUBSEP c SUBSEP mo) in mseen)) {
          mseen[d, c, mo] = 1
          mn[d, c]++
          ml[d, c, mn[d, c]] = mo
        }
        for (i = 1; i <= nm; i++) {
          s = metric_slot(line, mname[i])
          if (substr(s, 1, 1) == "x") continue
          kk = d SUBSEP c SUBSEP mname[i]
          seen[kk] = 1
          if (substr(s, 1, 1) == "v") {
            v = substr(s, 3)
            cnt[kk]++
            sum[kk] += v
            val[kk, cnt[kk]] = v
          }
        }
        total[d]++
      }
      close(fn)
    }
    # stats: the six pinned statistics over the values a group metric
    # carries; "absent" when no record carried the key, null statistics
    # when all its values were null. ST_MEAN/ST_MED keep the numeric
    # mean/median for the baseline delta.
    function stats(d, c, mk,   a, kk, n, i, j, t, r, out) {
      kk = d SUBSEP c SUBSEP mk
      if (!(kk in seen)) return "absent"
      n = cnt[kk] + 0
      if (n == 0) return "n=0 mean=null median=null min=null max=null p95=null"
      for (i = 1; i <= n; i++) a[i] = val[kk, i] + 0
      for (i = 2; i <= n; i++) {
        t = a[i]
        for (j = i - 1; j >= 1 && a[j] > t; j--) a[j + 1] = a[j]
        a[j + 1] = t
      }
      ST_MEAN = sum[kk] / n
      if (n % 2 == 1) ST_MED = a[(n + 1) / 2]
      else ST_MED = (a[n / 2] + a[n / 2 + 1]) / 2
      r = int((95 * n + 99) / 100)   # ceil(0.95*n), exact integer arithmetic
      out = "n=" n " mean=" fmt(ST_MEAN) " median=" fmt(ST_MED)
      out = out " min=" fmt(a[1]) " max=" fmt(a[n]) " p95=" fmt(a[r])
      return out
    }
    function outcomes_of(d, c,   b, k, i, j, t, out) {
      k = oc[d, c] + 0
      for (i = 1; i <= k; i++) b[i] = ol[d, c, i]
      for (i = 2; i <= k; i++) {
        t = b[i]
        for (j = i - 1; j >= 1 && b[j] > t; j--) b[j + 1] = b[j]
        b[j + 1] = t
      }
      out = ""
      for (i = 1; i <= k; i++) out = out " " b[i] "=" odist[d, c, b[i]]
      return out
    }
    function models_of(d, c,   b, k, i, j, t, out) {
      k = mn[d, c] + 0
      if (k == 0) return "null"
      for (i = 1; i <= k; i++) b[i] = ml[d, c, i]
      for (i = 2; i <= k; i++) {
        t = b[i]
        for (j = i - 1; j >= 1 && b[j] > t; j--) b[j + 1] = b[j]
        b[j + 1] = t
      }
      out = b[1]
      for (i = 2; i <= k; i++) out = out "," b[i]
      return out
    }
    # print_compare: the baseline comparison lines for one client.
    function print_compare(c,   i, kk, n1, n2, c1m, c1d, c2m, c2d) {
      if (recs[2, c] + 0 == 0) {
        printf "  client %s: absent in baseline (no comparison)\n", c
        return
      }
      if (recs[1, c] + 0 == 0) {
        printf "  client %s: absent in results (no comparison)\n", c
        return
      }
      printf "  client %s:\n", c
      for (i = 1; i <= nm; i++) {
        kk = c SUBSEP mname[i]
        n1 = cnt[1 SUBSEP kk] + 0
        n2 = cnt[2 SUBSEP kk] + 0
        if (n1 == 0 && n2 == 0) continue
        if (n1 == 0) { printf "    %s: absent in results\n", mname[i]; continue }
        if (n2 == 0) { printf "    %s: absent in baseline\n", mname[i]; continue }
        stats(1, c, mname[i]); c1m = ST_MEAN; c1d = ST_MED
        stats(2, c, mname[i]); c2m = ST_MEAN; c2d = ST_MED
        printf "    %s: current mean=%s median=%s baseline mean=%s median=%s delta=%s\n", \
          mname[i], fmt(c1m), fmt(c1d), fmt(c2m), fmt(c2d), fmt_signed(c1m - c2m)
      }
    }
    BEGIN {
      nm = split(metrics, mname, " ")
      read_file(f1, 1)
      if (bfile != "") read_file(bfile, 2)
      printf "antz-bench report: total records: %d\n", total[1] + 0
      for (i = 1; i <= ng[1] + 0; i++) {
        c = grp[1, i]
        printf "client %s: records=%d models=%s\n", c, recs[1, c], models_of(1, c)
        printf "  outcomes:%s\n", outcomes_of(1, c)
        for (j = 1; j <= nm; j++) printf "  %s: %s\n", mname[j], stats(1, c, mname[j])
      }
      if (bfile == "") exit 0
      printf "baseline comparison:\n"
      for (i = 1; i <= ng[1] + 0; i++) print_compare(grp[1, i])
      for (i = 1; i <= ng[2] + 0; i++)
        if (!((1 SUBSEP grp[2, i]) in recs)) print_compare(grp[2, i])
    }
  '
}

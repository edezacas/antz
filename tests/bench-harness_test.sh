#!/usr/bin/env bash
# tests/bench-harness_test.sh -- the owning suite for the antz benchmark
# harness under bench/ (change telemetry-benchmark). The suite is hermetic
# by change contract: it exercises the plumbing through the dry-run client,
# recording stubs, canned artifacts, and report mode only -- the real
# (LLM-invoking) bench never runs here. Git is used only inside throwaway
# fixture repos under temp space; every run stays inside the harness temp
# root and reads the checkout read-only.
#
# Sub-spec 01-fixture (fixture-01..03): the checked-in benchmark fixture --
# one request file "bench/fixture/scenario.txt" plus the toy project under
# "bench/fixture/repo/" (no nested git data anywhere under the fixture) --
# and its per-repetition materialization: bench/lib.sh copies the repo
# byte-for-byte into a fresh temp directory, git inits, and makes exactly
# one initial commit, and records the exact request bytes into the run dir
# so every record is auditable against the fixture.
#
# Sub-spec 02-schema (schema-01..05): the common telemetry record -- the
# closed, pinned field set in pinned order emitted as one valid-JSON line
# per repetition by bench/lib.sh (null for unavailable, never 0, never
# missing); metric semantics; outcome classification from the fixture
# repo's disk artifacts and the harness's kill record only, in the pinned
# precedence; and the change-dir artifact counters as present integers.
#
# Sub-spec 03-adapter (adapter-01..08): the client-agnostic adapter
# contract -- bench/adapter-<client>.sh files defining exactly
# bench_detect / bench_invoke / bench_collect, sourced one per run through
# bench/lib.sh -- and the dry-run mock client: scripted outcomes that
# materialize the flow artifacts the classifier reads, run-dir raw
# artifacts (client.stdout / client.stderr / client.exit) and the
# harness's timeout marker, collect normalized to the pinned telemetry
# keys (null where unavailable, no model calls), deterministic repetition
# scaling, the deadline-kill and failed-client paths end to end, and the
# bench tree kept POSIX and interpreter-free.
#
# Sub-spec 04-clients (clients-01..08): the per-repetition sandbox -- fresh
# HOME / XDG_CONFIG_HOME / XDG_DATA_HOME / CLAUDE_CONFIG_DIR under temp
# space, the minimal allowlist environment (PATH, HOME, TMPDIR, the sandbox
# variables, the pinned-model variable; no ANTHROPIC_* / CLAUDE_* /
# OPENCODE_* passthrough), the checkout under test rendered into the sandbox
# by its own install.sh (marker VERSION, baked sandbox libdir), read-only
# credential copies that never fabricate -- and the two real-client
# adapters (Claude Code, OpenCode) exercised hermetically against recording
# stub clients: their invoke argv shapes, run-dir artifacts, transcript /
# parent-and-child-export subagent attribution (partial coverage nulls the
# affected totals), and model pinning forwarded and recorded on both sides.
#
# Sub-spec 05-runner (runner-01..06): the runner CLI -- usage and argument
# refusal, detection/forcing, the repetition loop, outputs and the exit
# contract, auditable run dirs, and the hermetic-suite law.
#
# Sub-spec 06-report (report-01..04): the aggregate report behind the
# bench_report seam, driven standalone through "report" mode -- per-client
# groups with the pinned n/mean/median/min/max/p95 statistics (nulls
# excluded, absent metrics named, never failed over), the baseline
# comparison's signed deltas and one-sided gaps, and the mode's
# standalone-ness on any conforming input.
#
# Each reported test name begins with its scenario id, so a failure maps
# straight back to the scenario it covers.
#
# The shared harness library provides the runner plumbing; this suite
# defines none of it itself. Run directly:  sh tests/bench-harness_test.sh

set -u

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=tests/harness.sh
. "$SCRIPT_DIR/tests/harness.sh"

# The bench library under test resolves the fixture from BENCH_DIR; the
# runner sets it from its own location, this suite sets it explicitly.
BENCH_DIR="$HARNESS_REPO/bench"
FIXTURE_DIR="$BENCH_DIR/fixture"
# shellcheck source=bench/lib.sh
. "$BENCH_DIR/lib.sh"

# ---- fixture-01 -------------------------------------------------------------
# The checked-in fixture is self-contained: one request file (exists,
# non-empty, holds the benchmark request text), the toy repo it is written
# against (exists, carries README.md, named by the request), and no nested
# git data -- no ".git" file and no ".git" directory -- anywhere beneath
# "bench/fixture/".

test_fixture_01() {
  ok=0
  req="$FIXTURE_DIR/scenario.txt"
  if [ ! -f "$req" ]; then
    echo "  bench/fixture/scenario.txt does not exist"
    return 1
  fi
  [ -s "$req" ] || { echo "  bench/fixture/scenario.txt is empty"; ok=1; }
  # The request is written against the toy project: it names the tool the
  # repo provides, so the two are one self-contained fixture.
  grep -qiF "toysize" "$req" \
    || { echo "  the request text does not reference the toy project (toysize)"; ok=1; }
  # The request reads like a task: imperative prompt text, not metadata.
  grep -qiF "README.md" "$req" \
    || { echo "  the request text does not name README.md (documenting the change is part of the task)"; ok=1; }

  [ -d "$FIXTURE_DIR/repo" ] \
    || { echo "  bench/fixture/repo/ does not exist"; return 1; }
  [ -s "$FIXTURE_DIR/repo/README.md" ] \
    || { echo "  bench/fixture/repo/README.md is missing or empty"; ok=1; }
  # a toy project the request is written against: the tool it names exists
  [ -f "$FIXTURE_DIR/repo/toysize.sh" ] \
    || { echo "  bench/fixture/repo/toysize.sh (the tool the request extends) is missing"; ok=1; }

  # Mechanical scan: no ".git" file and no ".git" directory anywhere under
  # the fixture -- the checked-in fixture carries no git data of its own.
  gits=$(find "$FIXTURE_DIR" -name .git)
  [ -z "$gits" ] || { echo "  git data found under bench/fixture/:"; printf '%s\n' "$gits" | sed 's/^/    /'; ok=1; }
  return $ok
}

# ---- fixture-02 -------------------------------------------------------------
# Each repetition gets a fresh, identical git repo materialized under temp
# space -- the only git the fixture ever has. Two materializations: each is
# a git repo whose working tree carries bench/fixture/repo/ byte-for-byte
# plus nothing else; each has exactly one commit, a clean status, no
# "spdd/" directory, no "antz/*" branch; mutating one leaves the other
# untouched (no shared state); the checked-in source stays pristine.

materialized_equal_to_source() {
  # $1 = materialized repo dir. True iff its working tree (minus ".git")
  # is exactly bench/fixture/repo/, file for file, byte for byte.
  ( diff -r -x .git "$FIXTURE_DIR/repo" "$1" ) > "$HARNESS_RUN_TMP/fixture-02.diff.$$" 2>&1 \
    || { echo "  materialized tree differs from bench/fixture/repo/:"; sed 's/^/    /' "$HARNESS_RUN_TMP/fixture-02.diff.$$"; return 1; }
  return 0
}

test_fixture_02() {
  ok=0
  a="$(new_tmp_dir)/repo-a"
  b="$(new_tmp_dir)/repo-b"
  bench_materialize_repo "$a" || { echo "  materialize into $a failed"; return 1; }
  bench_materialize_repo "$b" || { echo "  materialize into $b failed"; return 1; }

  # both live under temp space, never inside the antz checkout
  for r in "$a" "$b"; do
    case "$r" in
      "$HARNESS_RUN_TMP"*) ;;
      *) echo "  materialization not under temp space: $r"; ok=1 ;;
    esac
  done

  # each is a git repository whose tree is exactly the fixture repo's files
  git -C "$a" rev-parse --git-dir >/dev/null || { echo "  $a is not a git repository"; ok=1; }
  git -C "$b" rev-parse --git-dir >/dev/null || { echo "  $b is not a git repository"; ok=1; }
  materialized_equal_to_source "$a" || ok=1
  materialized_equal_to_source "$b" || ok=1

  # each has exactly one commit, a clean status, no spdd/, no antz/* branch
  [ "$(git -C "$a" rev-list --count HEAD)" = "1" ] \
    || { echo "  $a does not carry exactly one commit: $(git -C "$a" rev-list --count HEAD)"; ok=1; }
  [ "$(git -C "$b" rev-list --count HEAD)" = "1" ] \
    || { echo "  $b does not carry exactly one commit: $(git -C "$b" rev-list --count HEAD)"; ok=1; }
  [ -z "$(git -C "$a" status --porcelain)" ] \
    || { echo "  $a working tree is not clean"; ok=1; }
  [ -z "$(git -C "$b" status --porcelain)" ] \
    || { echo "  $b working tree is not clean"; ok=1; }
  [ ! -e "$a/spdd" ] || { echo "  $a carries an spdd/ directory"; ok=1; }
  [ ! -e "$b/spdd" ] || { echo "  $b carries an spdd/ directory"; ok=1; }
  [ -z "$(git -C "$a" branch --list 'antz/*')" ] \
    || { echo "  $a carries an antz/* branch"; ok=1; }
  [ -z "$(git -C "$b" branch --list 'antz/*')" ] \
    || { echo "  $b carries an antz/* branch"; ok=1; }

  # mutating one materialization leaves the other unchanged -- no shared state
  printf 'shared-state probe\n' > "$a/MUTATED.txt"
  git -C "$a" add -A
  git -C "$a" -c user.name=antz-bench -c user.email=antz-bench@example.invalid commit -qm "mutation in repo-a"
  [ "$(git -C "$a" rev-list --count HEAD)" = "2" ] \
    || { echo "  the mutation did not commit inside $a"; ok=1; }
  [ "$(git -C "$b" rev-list --count HEAD)" = "1" ] \
    || { echo "  repos share git state: $b gained a commit"; ok=1; }
  [ ! -e "$b/MUTATED.txt" ] || { echo "  repos share the working tree: $b carries MUTATED.txt"; ok=1; }
  [ -z "$(git -C "$b" status --porcelain)" ] \
    || { echo "  $b dirty after mutating $a"; ok=1; }

  # the checked-in source stayed pristine: materialization only reads it
  find "$FIXTURE_DIR" -name .git | grep -q . \
    && { echo "  git data appeared under bench/fixture/ after materializing"; ok=1; }
  [ ! -e "$FIXTURE_DIR/repo/MUTATED.txt" ] \
    || { echo "  mutation leaked into the checkout"; ok=1; }
  return $ok
}

# ---- fixture-03 -------------------------------------------------------------
# The request is passed verbatim and recorded: the runner's request source
# is exactly bench/fixture/scenario.txt, a repetition's run dir carries a
# copy of those same bytes (auditable against the fixture after the run),
# and two repetitions of the same fixture pass byte-identical requests.
# (The end-to-end pin that a running client's prompt equals this recorded
# file lives with the dry-run client and runner scenarios, bench-adapter /
# bench-runner; here the fixture-owned request plumbing is pinned whole.)

test_fixture_03() {
  ok=0
  src="$FIXTURE_DIR/scenario.txt"
  [ -s "$src" ] || { echo "  bench/fixture/scenario.txt is missing or empty"; return 1; }

  # the runner's prompt source is exactly the checked-in request file
  rf=$(bench_request_file) || { echo "  bench_request_file failed"; return 1; }
  [ "$rf" = "$src" ] || { echo "  the request source is not the checked-in scenario.txt: $rf"; ok=1; }

  # two repetitions, two run dirs: each records the request
  run1="$(new_tmp_dir)/run-1"
  run2="$(new_tmp_dir)/run-2"
  mkdir -p "$run1" "$run2" || return 1
  bench_record_request "$run1" || { echo "  recording into run dir 1 failed"; return 1; }
  bench_record_request "$run2" || { echo "  recording into run dir 2 failed"; return 1; }

  # the run dir carries a copy of the request -- the same bytes the client
  # prompt is taken from -- so the record is auditable against the fixture
  [ -f "$run1/request.txt" ] || { echo "  run dir 1 carries no request.txt"; ok=1; }
  cmp -s "$src" "$run1/request.txt" \
    || { echo "  run dir 1's request copy differs from bench/fixture/scenario.txt"; ok=1; }
  cmp -s "$src" "$run2/request.txt" \
    || { echo "  run dir 2's request copy differs from bench/fixture/scenario.txt"; ok=1; }

  # two repetitions pass byte-identical requests (repetitions are comparable)
  cmp -s "$run1/request.txt" "$run2/request.txt" \
    || { echo "  two repetitions passed differing request bytes"; ok=1; }
  [ -s "$run1/request.txt" ] || { echo "  the recorded request is empty"; ok=1; }
  return $ok
}

# ---- schema test helpers ------------------------------------------------------
# The schema domain is exercised at its own seam: bench/lib.sh's record
# emission (the path the runner appends through), outcome classification, and
# artifact counters, driven with canned key=value sets and canned fixture-repo
# artifact trees. The full "runner completes repetitions" pass is pinned again
# by the runner/adapter scenarios (bench-runner/bench-adapter).

# The schema's pinned field set, transcribed verbatim from the sub-spec's
# Background (pinned order). The suite keeps its own copy on purpose: if
# bench/lib.sh drifts from the contract, a schema test must go red.
SCHEMA_FIELDS="run_id timestamp client antz_version scenario repetition model_pinned wall_clock_ms outcome verifier_rejections subspecs_declared subspecs_receipted slug exit_code error_note client_version client_duration_ms tokens_input tokens_output tokens_reasoning tokens_cache_read tokens_cache_write cost_usd turns tool_calls subagent_delegations models_used session_id"

# The pinned outcome vocabulary.
SCHEMA_OUTCOMES="approved rejected blocked open-question timeout error"

base_kv() {
  # Print a complete conforming key=value record set (a "dryrun" approved
  # run, repetition $1), mixing non-null metrics with null ones so every
  # field of the closed set is present exactly once.
  r="$1"
  cat <<EOF
run_id=dryrun-$r
timestamp=2026-09-15T12:0$r:00Z
client=dryrun
antz_version=0.0.0-test
scenario=toysize-doc-sync
repetition=$r
model_pinned=null
wall_clock_ms=$((100 * r))
outcome=approved
verifier_rejections=0
subspecs_declared=6
subspecs_receipted=2
slug=telemetry-benchmark
exit_code=0
error_note=null
client_version=dryrun-0.0.1
client_duration_ms=50
tokens_input=100
tokens_output=200
tokens_reasoning=null
tokens_cache_read=300
tokens_cache_write=null
cost_usd=0.01
turns=7
tool_calls=9
subagent_delegations=2
models_used=dry-model-a,dry-model-b
session_id=sess-$r
EOF
}

kv_set() {
  # $1 = kv text; remaining args are key=value overrides. Prints the text
  # with each named key's line replaced (in place), so tests vary one field
  # of base_kv without hand-writing the closed set.
  text="$1"
  shift
  printf '%s\n' "$text" | while IFS= read -r line; do
    k=${line%%=*}
    for ov in "$@"; do
      if [ "${ov%%=*}" = "$k" ]; then
        line="$ov"
        break
      fi
    done
    printf '%s\n' "$line"
  done
}

json_scan_keys() {
  # $1 = one JSONL line. Print the object's key names, one per line, in
  # document order, and exit 0 ONLY if the line is valid standalone JSON
  # (flat object; strings/numbers/literals; arrays and nested objects are
  # rejected, since the schema's records are flat). Hermetic: the suite's
  # own character scanner, no external JSON tool.
  printf '%s' "$1" | awk '
    function die(m) { print "invalid JSON: " m > "/dev/stderr"; exit 1 }
    function ws() { while (i <= n && substr(s, i, 1) ~ /[ \t\r\n]/) i++ }
    function expect(c,  g) {
      g = substr(s, i, 1)
      if (g != c) die("expected [" c "] at byte " i " got [" g "]")
      i++
    }
    function parse_string(  out, c, esc, j) {
      expect("\"")
      out = ""
      while (1) {
        if (i > n) die("unterminated string")
        c = substr(s, i, 1)
        i++
        if (c == "\"") return out
        if (c == "\\") {
          if (i > n) die("truncated escape")
          esc = substr(s, i, 1)
          i++
          if (esc == "u") {
            for (j = 0; j < 4; j++) {
              if (substr(s, i, 1) !~ /[0-9a-fA-F]/) die("bad \\u escape")
              i++
            }
          } else if (esc !~ /["\\\/bfnrt]/) die("bad escape \\" esc)
        } else if (c < " ") die("raw control character in string")
        out = out c
      }
    }
    function parse_value(  c, w) {
      ws()
      if (i > n) die("missing value")
      c = substr(s, i, 1)
      if (c == "\"") { parse_string(); return }
      if (c == "[" || c == "{") die("nested arrays/objects are not flat-record values")
      w = substr(s, i)
      if (w ~ /^-?[0-9]/) {
        if (!match(w, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?/)) die("malformed number")
        i += RLENGTH
        return
      }
      if (w ~ /^null/) { i += 4; return }
      if (w ~ /^true/) { i += 5; return }
      if (w ~ /^false/) { i += 6; return }
      die("bad value at byte " i)
    }
    { s = s $0 }
    END {
      n = length(s); i = 1
      if (n == 0) die("empty line")
      ws()
      expect("{")
      ws()
      if (substr(s, i, 1) == "}") {
        i++
      } else {
        while (1) {
          ws()
          if (substr(s, i, 1) != "\"") die("expected a string key at byte " i)
          print parse_string()
          ws()
          expect(":")
          parse_value()
          ws()
          c = substr(s, i, 1)
          if (c == ",") { i++; continue }
          if (c == "}") { i++; break }
          die("expected , or } at byte " i)
        }
      }
      ws()
      if (i <= n) die("trailing content after the object")
    }
  '
}

# ---- schema-01 ----------------------------------------------------------------
# One complete JSON object per run: every completed repetition appends exactly
# one line to the results JSONL; each line is valid standalone JSON carrying
# exactly the pinned field set -- every field once, none missing, no extra --
# in the pinned order. A record that violates the closed set is refused and
# the JSONL is left untouched (never a partial record).

test_schema_01() {
  ok=0
  out="$(new_tmp_dir)/results.jsonl"

  kvf="$(new_tmp_dir)/kv"; base_kv 1 > "$kvf"
  bench_emit_record "$out" < "$kvf" || { echo "  emitting a complete record failed"; return 1; }
  kvf2="$(new_tmp_dir)/kv2"; base_kv 2 > "$kvf2"
  bench_emit_record "$out" < "$kvf2" || { echo "  emitting the second record failed"; return 1; }

  # one line per repetition, appended in order
  lines=$(wc -l < "$out" | tr -d ' ')
  [ "$lines" = "2" ] || { echo "  expected 2 lines for 2 repetitions, got $lines"; return 1; }

  # each line parses standalone as valid JSON, its keys exactly the pinned
  # field set in the pinned order, every field once, no extras
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    keys=$(json_scan_keys "$line") \
      || { echo "  line $n is not valid standalone JSON"; ok=1; continue; }
    printf '%s\n' $SCHEMA_FIELDS > "$HARNESS_RUN_TMP/expected-fields.$$"
    printf '%s\n' "$keys" > "$HARNESS_RUN_TMP/got-fields.$$"
    cmp -s "$HARNESS_RUN_TMP/got-fields.$$" "$HARNESS_RUN_TMP/expected-fields.$$" || {
      echo "  line $n's field set/order is not the pinned one:"
      diff "$HARNESS_RUN_TMP/got-fields.$$" "$HARNESS_RUN_TMP/expected-fields.$$" | sed 's/^/    /'
      ok=1
    }
    dup=$(printf '%s\n' "$keys" | sort | uniq -d)
    [ -z "$dup" ] || { echo "  line $n repeats field(s): $dup"; ok=1; }
  done < "$out"
  [ "$n" = "2" ] || { echo "  JSONL holds $n lines, expected 2"; ok=1; }

  # the library's field-set source agrees with the sub-spec's pinned list
  got=$(bench_schema_fields | tr '\n' ' ' | sed 's/ *$//')
  [ "$got" = "$SCHEMA_FIELDS" ] \
    || { echo "  bench_schema_fields does not carry the pinned set in the pinned order"; ok=1; }
  return $ok
}

test_schema_01_closed() {
  ok=0
  good="$(new_tmp_dir)/good.jsonl"
  kvf="$(new_tmp_dir)/kv"
  base_kv 1 > "$kvf"
  bench_emit_record "$good" < "$kvf" || return 1
  ref="$(new_tmp_dir)/ref"
  cp "$good" "$ref"

  reject() {
    # $1 = description. The caller sets $kvsrc to the mutated kv text; a
    # refused emit must exit non-zero and write nothing at all -- the JSONL
    # is never created, not even empty or partial.
    desc="$1"
    bad="$(new_tmp_dir)/bad.jsonl"
    if bench_emit_record "$bad" < "$kvsrc" 2>/dev/null; then
      echo "  accepted a record with $desc"
      return 1
    fi
    if [ -e "$bad" ]; then
      echo "  a refused record ($desc) still created the JSONL file"
      return 1
    fi
    return 0
  }

  # missing field
  kvsrc="$(new_tmp_dir)/src"; grep -v '^turns=' "$kvf" > "$kvsrc"
  reject "a missing field" || ok=1
  # extra field
  kvsrc="$(new_tmp_dir)/src"; { cat "$kvf"; printf 'sneaky_extra=1\n'; } > "$kvsrc"
  reject "an extra field" || ok=1
  # duplicate field
  kvsrc="$(new_tmp_dir)/src"; { cat "$kvf"; printf 'turns=4\n'; } > "$kvsrc"
  reject "a duplicated field" || ok=1
  # malformed line (no key=value shape)
  kvsrc="$(new_tmp_dir)/src"; { cat "$kvf"; printf 'not-a-pair\n'; } > "$kvsrc"
  reject "a malformed input line" || ok=1
  # empty input
  kvsrc="$(new_tmp_dir)/src"; : > "$kvsrc"
  reject "no fields at all" || ok=1

  # none of the refusals touched the good file
  cmp -s "$good" "$ref" || { echo "  refused emits modified the results JSONL"; ok=1; }
  return $ok
}

run_test "schema-01: completed repetitions append exactly one valid-JSON line each, carrying exactly the pinned field set once in the pinned order" test_schema_01
run_test "schema-01: the closed field set is enforced -- missing, extra, duplicate, or malformed input is refused without writing anything" test_schema_01_closed

# ---- schema-02 ----------------------------------------------------------------
# Metric semantics on the emitted record: wall_clock_ms is always present and
# >= 0 (never null, even on timed-out or failed runs); client-reported metrics
# are null when unavailable and >= 0 when reported; a null is never emitted as
# 0 and a true 0 is never emitted as null; models_used and slug are null or
# the comma-joined observation.

emit_kv() {
  # Append one record built from base_kv 1 with the given key=value
  # overrides to JSONL $1.
  overrides_kv=$(kv_set "$(base_kv 1)" "$@")
  kvf="$(new_tmp_dir)/kv"
  printf '%s\n' "$overrides_kv" > "$kvf"
  bench_emit_record "$1" < "$kvf"
}

test_schema_02() {
  ok=0
  out="$(new_tmp_dir)/results.jsonl"

  # a run that timed out or failed still carries a measured wall clock
  emit_kv "$out" outcome=timeout error_note="deadline fired" wall_clock_ms=0 exit_code=143 \
    || { echo "  a timeout record with wall_clock_ms=0 was refused"; return 1; }
  line=$(tail -n 1 "$out")
  case "$line" in *'"wall_clock_ms":0,'*) ;; *) echo "  wall clock 0 not emitted as bare 0: $line"; ok=1 ;; esac

  # wall_clock_ms is never null, whatever the outcome
  bad_out="$(new_tmp_dir)/bad.jsonl"
  if emit_kv "$bad_out" wall_clock_ms=null >/dev/null 2>&1; then
    echo "  accepted a record whose wall_clock_ms is null"
    ok=1
  fi
  [ ! -e "$bad_out" ] || { echo "  the refused record still wrote to the JSONL"; ok=1; }
  # ...and never negative
  if emit_kv "$(new_tmp_dir)/bad2.jsonl" wall_clock_ms=-1 >/dev/null 2>&1; then
    echo "  accepted a negative wall_clock_ms"; ok=1
  fi

  # unavailable metrics are null, never 0
  out2="$(new_tmp_dir)/results.jsonl"
  emit_kv "$out2" client_duration_ms=null tokens_input=null tokens_output=null \
    tokens_reasoning=null tokens_cache_read=null tokens_cache_write=null \
    cost_usd=null turns=null tool_calls=null subagent_delegations=null \
    models_used=null slug=null \
    || { echo "  an all-null-telemetry record was refused"; return 1; }
  line=$(tail -n 1 "$out2")
  for f in client_duration_ms tokens_input tokens_output tokens_reasoning \
    tokens_cache_read tokens_cache_write cost_usd turns tool_calls \
    subagent_delegations models_used slug; do
    case "$line" in *"\"$f\":null,"*) ;; *) echo "  $f is not emitted as null: $line"; ok=1 ;; esac
    case "$line" in *"\"$f\":0,"*) echo "  null $f was emitted as 0"; ok=1 ;; esac
  done

  # a true 0 is a 0, never null
  out3="$(new_tmp_dir)/results.jsonl"
  emit_kv "$out3" client_duration_ms=0 tokens_input=0 tokens_output=0 \
    tokens_reasoning=0 tokens_cache_read=0 tokens_cache_write=0 cost_usd=0 \
    turns=0 tool_calls=0 subagent_delegations=0 \
    || { echo "  an all-true-zero telemetry record was refused"; return 1; }
  line=$(tail -n 1 "$out3")
  for f in client_duration_ms tokens_input tokens_output tokens_reasoning \
    tokens_cache_read tokens_cache_write cost_usd turns tool_calls \
    subagent_delegations; do
    case "$line" in *"\"$f\":0,"*) ;; *) echo "  true-zero $f not emitted as bare 0: $line"; ok=1 ;; esac
    case "$line" in *"\"$f\":null,"*) echo "  true-zero $f was emitted as null"; ok=1 ;; esac
  done

  # a negative metric is refused
  if emit_kv "$(new_tmp_dir)/bad3.jsonl" tokens_input=-5 >/dev/null 2>&1; then
    echo "  accepted a negative tokens_input"; ok=1
  fi

  # models_used and slug carry the comma-joined observation verbatim
  out4="$(new_tmp_dir)/results.jsonl"
  emit_kv "$out4" models_used=model-a,model-b slug=alpha-beta,alpha-gamma \
    || { echo "  a comma-joined models_used/slug record was refused"; return 1; }
  line=$(tail -n 1 "$out4")
  case "$line" in *'"models_used":"model-a,model-b"'*) ;; *) echo "  models_used not emitted comma-joined: $line"; ok=1 ;; esac
  case "$line" in *'"slug":"alpha-beta,alpha-gamma"'*) ;; *) echo "  slug not emitted comma-joined: $line"; ok=1 ;; esac

  # string values with JSON metacharacters survive as valid JSON
  out5="$(new_tmp_dir)/results.jsonl"
  emit_kv "$out5" run_id='he said "hi" \ and left' \
    || { echo "  a record with quotes/backslash in a string field was refused"; return 1; }
  json_scan_keys "$(tail -n 1 "$out5")" > /dev/null \
    || { echo "  the escaped record is not valid standalone JSON: $(tail -n 1 "$out5")"; ok=1; }
  return $ok
}

# ---- schema-03 ----------------------------------------------------------------
# The outcome vocabulary and its precedence, classified from the materialized
# fixture repo's disk artifacts and the harness's own kill record only.

new_repo() {
  # Print a fresh empty fixture-repo directory (no spdd/ at all).
  r="$(new_tmp_dir)/repo"
  mkdir -p "$r"
  printf '%s' "$r"
}

new_change_dir() {
  # $1 = repo, $2 = slug: the flow created this change dir.
  mkdir -p "$1/spdd/changes/$2"
}

test_schema_03_precedence() {
  ok=0

  # every artifact for every outcome at once: approved (order 1) wins even
  # over a blocked receipt, REJECTED.md, OPEN_QUESTIONS.md, and the kill
  r=$(new_repo)
  new_change_dir "$r" alpha
  mkdir -p "$r/spdd/archive/2026-09-15-run"
  printf 'id=s-1 result=blocked reason=x\n' > "$r/spdd/changes/alpha/01-a.result"
  printf '## Rejection 1: nope\n' > "$r/spdd/changes/alpha/REJECTED.md"
  : > "$r/spdd/changes/alpha/OPEN_QUESTIONS.md"
  got=$(bench_outcome_classify "$r" 1)
  [ "$got" = "approved" ] || { echo "  archive present but got '$got'"; ok=1; }

  # an empty archive/ directory is NOT approval evidence
  r=$(new_repo)
  new_change_dir "$r" alpha
  mkdir -p "$r/spdd/archive"
  : > "$r/spdd/archive/README"
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  archive without a directory gave '$got', expected error"; ok=1; }

  # blocked (order 2) via a receipt's result=blocked line, beating rejected,
  # open-question, and the kill
  r=$(new_repo)
  new_change_dir "$r" alpha
  printf 'id=s-1 result=green reason=t\ndone\n' > "$r/spdd/changes/alpha/01-a.result"
  printf 'id=s-2 result=blocked reason=BLOCKED: plan\n' > "$r/spdd/changes/alpha/02-b.result"
  printf '## Rejection 1: nope\n' > "$r/spdd/changes/alpha/REJECTED.md"
  : > "$r/spdd/changes/alpha/OPEN_QUESTIONS.md"
  got=$(bench_outcome_classify "$r" 1)
  [ "$got" = "blocked" ] || { echo "  blocked receipt gave '$got'"; ok=1; }

  # blocked via the refusal marker (line-start BLOCKED:) on any change-dir
  # artifact, even with green receipts
  r=$(new_repo)
  new_change_dir "$r" alpha
  printf 'BLOCKED: oversized plan, see above\n' > "$r/spdd/changes/alpha/03-c.result"
  printf 'notes\n' > "$r/spdd/changes/alpha/NOTES.md"
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "blocked" ] || { echo "  refusal marker gave '$got'"; ok=1; }

  # rejected (order 3) beats open-question and the kill
  r=$(new_repo)
  new_change_dir "$r" alpha
  printf '## Rejection 1: nope\n' > "$r/spdd/changes/alpha/REJECTED.md"
  : > "$r/spdd/changes/alpha/OPEN_QUESTIONS.md"
  got=$(bench_outcome_classify "$r" 1)
  [ "$got" = "rejected" ] || { echo "  REJECTED.md gave '$got'"; ok=1; }

  # open-question (order 4) beats the kill
  r=$(new_repo)
  new_change_dir "$r" alpha
  : > "$r/spdd/changes/alpha/OPEN_QUESTIONS.md"
  got=$(bench_outcome_classify "$r" 1)
  [ "$got" = "open-question" ] || { echo "  OPEN_QUESTIONS.md gave '$got'"; ok=1; }

  # timeout (order 5): a clean change dir plus the harness kill record
  r=$(new_repo)
  new_change_dir "$r" alpha
  got=$(bench_outcome_classify "$r" 1)
  [ "$got" = "timeout" ] || { echo "  killed clean run gave '$got'"; ok=1; }
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  unkilled clean run gave '$got'"; ok=1; }

  # error (order 6): nothing above matched
  r=$(new_repo)
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  empty repo gave '$got'"; ok=1; }

  # every declared outcome is reachable and the vocabulary is closed
  case " $SCHEMA_OUTCOMES " in *" error "*) ;; *) echo "  vocabulary lost error"; ok=1 ;; esac
  return $ok
}

test_schema_03_disk_only() {
  ok=0

  # the client's conversational output is never evidence: a repo whose only
  # content is a stray client.stdout (in the repo root, outside any change
  # dir) claiming every outcome classifies as error
  r=$(new_repo)
  {
    printf 'BLOCKED: whatever the client said\n'
    printf 'id=s-1 result=blocked reason=nope\n'
    printf 'approved approved approved\n'
  } > "$r/client.stdout"
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  client prose outside the change dirs gave '$got', expected error"; ok=1; }

  # a result=blocked line in a NON-receipt file is not receipt evidence
  r=$(new_repo)
  new_change_dir "$r" alpha
  printf 'see id=s-1 result=blocked reason=x\n' > "$r/spdd/changes/alpha/README.md"
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  result=blocked in README gave '$got', expected error"; ok=1; }

  # a receipt-shaped claim in a wrongly named file ("1-x.result", single
  # digit -- not an NN-*.result receipt) is not receipt evidence
  r=$(new_repo)
  new_change_dir "$r" alpha
  printf 'id=s-1 result=blocked reason=x\n' > "$r/spdd/changes/alpha/1-x.result"
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  a malformed-name receipt gave '$got', expected error"; ok=1; }

  # a green receipt is not blocked evidence either
  r=$(new_repo)
  new_change_dir "$r" alpha
  printf 'id=s-1 result=green reason=t\n' > "$r/spdd/changes/alpha/01-a.result"
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  a green receipt gave '$got', expected error"; ok=1; }

  # "BLOCKED:" without the pinned ": " spacing is not a refusal marker
  r=$(new_repo)
  new_change_dir "$r" alpha
  printf 'BLOCKED:needs a space\n' > "$r/spdd/changes/alpha/01-a.result"
  got=$(bench_outcome_classify "$r" 0)
  [ "$got" = "error" ] || { echo "  an unpinned refusal marker gave '$got', expected error"; ok=1; }
  return $ok
}

# ---- schema-04 ----------------------------------------------------------------
# The artifact counters are observations, never telemetry: always a present
# integer >= 0, counted from the change dir's artifacts (0 when absent).

test_schema_04() {
  ok=0

  r=$(new_repo)
  new_change_dir "$r" alpha
  new_change_dir "$r" beta
  a="$r/spdd/changes/alpha"; b="$r/spdd/changes/beta"
  mkdir -p "$a/sub"
  : > "$a/01-a.feature"; : > "$a/02-b.feature"          # declared: 2
  : > "$a/e2e-qa.feature"                                # not NN-*
  : > "$a/1-c.feature"                                   # single digit
  : > "$a/101-x.feature"                                 # three digits
  : > "$a/sub/04-deep.feature"                           # not top level
  : > "$b/03-c.feature"                                  # declared total: 3
  : > "$a/01-a.result"; : > "$a/10-b.result"             # receipted: 2
  : > "$a/zz.result"; : > "$a/sub/03-deep.result"        # neither counts
  : > "$b/01-b.result"                                   # receipted total: 3
  {
    printf '## Rejection 1: timeout\n'
    printf '## Rejection  2: double space is still a match\n'
    printf '   ## Rejection 3: indented -- not a heading line\n'
    printf '### Rejection 4: subheading -- no\n'
    printf '## Rejection:5 -- no space after the word\n'
    printf '## Rejections 6: plural -- no\n'
    printf '## Rejection 7: yes\n'
  } > "$a/REJECTED.md"                                     # 3 matches
  printf '## Rejection 1: beta\n' > "$b/REJECTED.md"       # +1 => 4

  d=$(bench_count_declared "$r")
  [ "$d" = "3" ] || { echo "  subspecs_declared: expected 3, got '$d'"; ok=1; }
  c=$(bench_count_receipted "$r")
  [ "$c" = "3" ] || { echo "  subspecs_receipted: expected 3, got '$c'"; ok=1; }
  j=$(bench_count_rejections "$r")
  [ "$j" = "4" ] || { echo "  verifier_rejections: expected 4, got '$j'"; ok=1; }

  # every counter is a present integer, never null, on an empty repo too
  e=$(new_repo)
  for f in bench_count_declared bench_count_receipted bench_count_rejections; do
    v=$($f "$e")
    case "$v" in
      ''|*[!0-9]*) echo "  $f on an empty repo returned non-integer '$v'"; ok=1 ;;
      0) ;;
      *) echo "  $f on an empty repo returned '$v', expected 0"; ok=1 ;;
    esac
  done
  # and on a repo with a change dir but no REJECTED.md
  m=$(new_repo)
  new_change_dir "$m" solo
  v=$(bench_count_rejections "$m")
  [ "$v" = "0" ] || { echo "  absent REJECTED.md gave '$v', expected 0"; ok=1; }

  # the slug field: null with no change dir, the slug alone with one, all
  # observed slugs comma-joined with several
  v=$(bench_observed_slug "$e")
  [ "$v" = "null" ] || { echo "  no change dirs gave slug '$v', expected null"; ok=1; }
  v=$(bench_observed_slug "$m")
  [ "$v" = "solo" ] || { echo "  one change dir gave slug '$v', expected solo"; ok=1; }
  v=$(bench_observed_slug "$r")
  [ "$v" = "alpha,beta" ] || { echo "  two change dirs gave slug '$v', expected alpha,beta"; ok=1; }
  return $ok
}

# ---- schema-05 ----------------------------------------------------------------
# A failed run still yields a complete record; error_note is non-null exactly
# when the outcome is error or timeout.

test_schema_05() {
  ok=0
  out="$(new_tmp_dir)/results.jsonl"

  # three repetitions: good, client failure (non-zero exit, no telemetry, no
  # flow artifacts), good -- every repetition still appends its record
  kvf="$(new_tmp_dir)/kv1"; base_kv 1 > "$kvf"
  bench_emit_record "$out" < "$kvf" || { echo "  good record refused"; return 1; }
  emit_kv "$out" outcome=error exit_code=7 error_note="client exited 7 with no usable telemetry" \
    client_duration_ms=null tokens_input=null tokens_output=null tokens_reasoning=null \
    tokens_cache_read=null tokens_cache_write=null cost_usd=null turns=null tool_calls=null \
    subagent_delegations=null models_used=null session_id=null slug=null \
    wall_clock_ms=987 verifier_rejections=0 subspecs_declared=0 subspecs_receipted=0 \
    || { echo "  the failed-run record was refused"; return 1; }
  kvf="$(new_tmp_dir)/kv3"; base_kv 3 > "$kvf"
  bench_emit_record "$out" < "$kvf" || { echo "  third record refused"; return 1; }
  [ "$(wc -l < "$out" | tr -d ' ')" = "3" ] \
    || { echo "  the JSONL lost a line: $(wc -l < "$out") lines"; ok=1; }

  # the failed record is COMPLETE: parses, pinned set, telemetry null,
  # exit code and reason present, wall clock measured anyway
  line=$(sed -n 2p "$out")
  json_scan_keys "$line" > "$HARNESS_RUN_TMP/f.$$" \
    || { echo "  failed-run record is not valid JSON"; return 1; }
  printf '%s\n' $SCHEMA_FIELDS > "$HARNESS_RUN_TMP/e.$$"
  cmp -s "$HARNESS_RUN_TMP/e.$$" "$HARNESS_RUN_TMP/f.$$" \
    || { echo "  failed-run record lost the pinned field set"; ok=1; }
  for f in client_duration_ms tokens_input tokens_output tokens_reasoning \
    tokens_cache_read tokens_cache_write cost_usd turns tool_calls \
    subagent_delegations models_used session_id; do
    case "$line" in *"\"$f\":null,"* | *"\"$f\":null}"*) ;; *) echo "  failed-run telemetry $f is not null"; ok=1 ;; esac
  done
  case "$line" in *'"outcome":"error"'*) ;; *) echo "  outcome is not error: $line"; ok=1 ;; esac
  case "$line" in *'"exit_code":7,'*) ;; *) echo "  exit_code 7 not carried: $line"; ok=1 ;; esac
  case "$line" in *'"wall_clock_ms":987,'*) ;; *) echo "  wall clock missing on a failed run: $line"; ok=1 ;; esac
  case "$line" in *'"error_note":"client exited 7 with no usable telemetry"'*) ;; *) echo "  error_note missing the reason: $line"; ok=1 ;; esac

  # a timeout record may carry the note too
  emit_kv "$(new_tmp_dir)/t.jsonl" outcome=timeout exit_code=143 \
    error_note="harness deadline fired at 5s" >/dev/null \
    || { echo "  a timeout record with error_note was refused"; ok=1; }

  # error_note is non-null exactly when the outcome is error or timeout
  if emit_kv "$(new_tmp_dir)/n1.jsonl" error_note="stray note" >/dev/null 2>&1; then
    echo "  accepted error_note on an approved run"; ok=1
  fi
  if emit_kv "$(new_tmp_dir)/n2.jsonl" outcome=error exit_code=1 error_note=null >/dev/null 2>&1; then
    echo "  accepted an error outcome without error_note"; ok=1
  fi
  if emit_kv "$(new_tmp_dir)/n3.jsonl" outcome=timeout exit_code=143 error_note=null >/dev/null 2>&1; then
    echo "  accepted a timeout without error_note"; ok=1
  fi

  # the outcome vocabulary is closed
  if emit_kv "$(new_tmp_dir)/n4.jsonl" outcome=success >/dev/null 2>&1; then
    echo "  accepted an outcome outside the pinned vocabulary"; ok=1
  fi
  return $ok
}


run_test "schema-02: metric semantics hold on the record -- wall clock never null and >= 0, unavailable metrics null (never 0), true zeros kept (never null), models_used and slug null or comma-joined" test_schema_02
run_test "schema-03: outcomes classify from disk artifacts in the pinned precedence (approved > blocked > rejected > open-question > timeout > error)" test_schema_03_precedence
run_test "schema-03: no outcome derives from the client's textual output -- stray prose, non-receipt or malformed-name blocked claims are not evidence" test_schema_03_disk_only
run_test "schema-04: verifier_rejections, subspecs_declared, subspecs_receipted count the change dir's artifacts as present integers >= 0 (0 when absent), and slug is null or the observed comma-joined slug(s)" test_schema_04
run_test "schema-05: a failed repetition still appends one complete record (outcome error, null telemetry, exit code and error_note carried) and error_note is non-null exactly when the outcome is error or timeout" test_schema_05

run_test "fixture-01: the checked-in fixture is self-contained (non-empty request naming the toy project; repo/ with README.md and toysize.sh; no .git file or directory anywhere under bench/fixture/)" test_fixture_01
run_test "fixture-02: two materializations are each a fresh one-commit clean git repo equal byte-for-byte to bench/fixture/repo/ plus nothing else (no spdd/, no antz/* branch), sharing no state, with the checked-in source untouched" test_fixture_02
run_test "fixture-03: the runner's prompt source is exactly scenario.txt and each repetition's run dir records those same bytes (request.txt), byte-identical across repetitions" test_fixture_03

# ---- adapter test helpers ---------------------------------------------------
# Sub-spec 03 is exercised at its seams: bench/lib.sh's adapter sourcing (the
# mechanism with which a run selects exactly one adapter), the pinned run-dir
# artifact convention, and the dry-run adapter itself -- the suite's mock
# client. As the runner does per run, the suite sources exactly one adapter,
# through the contract helper, and calls only its three functions.
#
# The suite keeps its own transcriptions of the pinned lists on purpose: if
# the implementation drifts from the contract, these tests must go red.

# The collect contract's pinned telemetry keys, in the pinned order (from
# the sub-spec's adapter-03 scenario text).
COLLECT_KEYS="client_version client_duration_ms tokens_input tokens_output tokens_reasoning tokens_cache_read tokens_cache_write cost_usd turns tool_calls subagent_delegations models_used session_id"

# The pinned run-dir artifact names, in run order (sub-spec 01's request
# copy, the raw client artifacts adapter-02 pins, and the harness's timeout
# marker).
RUN_ARTIFACTS="request.txt client.stdout client.stderr client.exit client.timeout collect.kv"

bench_source_adapter dryrun \
  || { printf 'FATAL: bench/adapter-dryrun.sh cannot be sourced\n' >&2; exit 1; }

now_ms() {
  # Milliseconds since the epoch when the platform's date supports them;
  # second-resolution (x1000) otherwise.
  ms=$(date +%s%3N 2>/dev/null)
  case "$ms" in
    ''|*[!0-9]*) ms=$(( $(date +%s) * 1000 )) ;;
  esac
  printf '%s\n' "$ms"
}

prep_repetition() {
  # $1 = a fresh root dir for one repetition: materializes the fixture repo
  # at $1/repo, the run dir at $1/run (request recorded), and an untouched
  # probe dir at $1/probe for the write-confinement checks.
  root="$1"
  mkdir -p "$root/run" "$root/probe" || return 1
  bench_materialize_repo "$root/repo" || return 1
  bench_record_request "$root/run" || return 1
}

assert_confined() {
  # $1 = the repetition's root. The adapter wrote nothing beside the
  # repo/run/probe trio, and nothing at all inside the probe dir.
  root="$1"
  stray=$(find "$root" -mindepth 1 -maxdepth 1 | grep -vE '/(repo|run|probe)$')
  [ -z "$stray" ] || { echo "  files appeared outside the fixture repo and the run dir:"; printf '%s\n' "$stray" | sed 's/^/    /'; return 1; }
  [ -z "$(find "$root/probe" -mindepth 1)" ] \
    || { echo "  the probe dir gained entries -- a write outside the run dir and the fixture repo"; return 1; }
  return 0
}

invoke_bounded() {
  # $1 repo, $2 request file, $3 run dir, $4 scripted outcome, $5 repetition,
  # $6 bound in whole seconds. Runs the dry-run client and returns its exit
  # code; 124 means it blocked or overran the bound -- which a login,
  # permission, or trust prompt would cause.
  (
    BENCH_DRYRUN_OUTCOME="$4"
    BENCH_REPETITION="$5"
    export BENCH_DRYRUN_OUTCOME BENCH_REPETITION
    bench_invoke "$1" "$2" "$3"
  ) &
  pid=$!
  i=0
  lim=$(( $6 * 10 ))
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt "$lim" ]; do
    sleep 0.1
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 124
  fi
  wait "$pid" 2>/dev/null
}

kill_after_deadline() {
  # $1 = the repetition's prepared root dir, $2 = deadline in whole seconds.
  # Acts as the harness's deadline enforcer over a timeout-scripted dry-run
  # invoke: the client runs in its own process group (bash job control) so
  # the kill reaches the client itself -- which it can only do because the
  # adapter runs it in the foreground. On return: KD_ALIVE (1 = still alive
  # at the deadline), KD_RC (the killed run's wait status), KD_WALL (elapsed
  # ms), KD_DEADLINE_MS; the harness's kill record (the timeout marker, and
  # client.exit from the kill status) is left in the run dir.
  root="$1"
  dl="$2"
  set -m
  (
    BENCH_DRYRUN_OUTCOME=timeout
    BENCH_REPETITION=1
    export BENCH_DRYRUN_OUTCOME BENCH_REPETITION
    bench_invoke "$root/repo" "$root/run/request.txt" "$root/run"
  ) &
  pid=$!
  KD_T0=$(now_ms)
  sleep "$dl"
  if kill -0 "$pid" 2>/dev/null; then
    KD_ALIVE=1
    kill -TERM -"$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  else
    KD_ALIVE=0
  fi
  wait "$pid" 2>/dev/null
  KD_RC=$?
  set +m
  KD_WALL=$(( $(now_ms) - KD_T0 ))
  KD_DEADLINE_MS=$(( dl * 1000 ))
  bench_mark_timeout "$root/run" || return 1
  if [ ! -f "$root/run/client.exit" ]; then
    printf '%s\n' "$KD_RC" > "$root/run/client.exit"
  fi
  return 0
}

emit_record_from() {
  # $1 jsonl, $2 repo, $3 run dir, $4 repetition, $5 killed flag (0|1),
  # $6 wall_clock_ms, $7 exit_code, $8 error_note (literal "null" allowed).
  # Assembles one repetition's record exactly the way the runner will: the
  # harness-owned fields, the artifact counters, the disk-classified
  # outcome, and the adapter's collect output -- then emits through the
  # schema. Sets LAST_OUTCOME to the classified outcome.
  LAST_OUTCOME=$(bench_outcome_classify "$2" "$5") || return 1
  {
    printf 'run_id=dryrun-r%s-%s\n' "$4" "$LAST_OUTCOME"
    printf 'timestamp=2026-09-15T00:00:00Z\n'
    printf 'client=dryrun\n'
    printf 'antz_version=0.0.0-suite\n'
    printf 'scenario=toysize-doc-sync\n'
    printf 'repetition=%s\n' "$4"
    printf 'model_pinned=null\n'
    printf 'wall_clock_ms=%s\n' "$6"
    printf 'outcome=%s\n' "$LAST_OUTCOME"
    printf 'verifier_rejections=%s\n' "$(bench_count_rejections "$2")"
    printf 'subspecs_declared=%s\n' "$(bench_count_declared "$2")"
    printf 'subspecs_receipted=%s\n' "$(bench_count_receipted "$2")"
    printf 'slug=%s\n' "$(bench_observed_slug "$2")"
    printf 'exit_code=%s\n' "$7"
    printf 'error_note=%s\n' "$8"
    bench_collect "$3" "$2"
  } | bench_emit_record "$1"
}

collect_val() {
  # $1 = collect output, $2 = key. Prints that key's value (empty when the
  # key is absent).
  printf '%s\n' "$1" | sed -n "s/^$2=//p"
}

adapter_lines() {
  # $1 = a bench file: its non-comment text (crude but adequate comment
  # stripper -- everything from a # on), for the mechanical scans.
  sed -e 's/#.*//' "$1"
}

# ---- adapter-01 ----------------------------------------------------------------
# One contract, three functions, one sourced adapter: every
# "bench/adapter-<client>.sh" defines exactly bench_detect / bench_invoke /
# bench_collect and nothing else; bench_detect exits 0 with a non-empty
# version string when the client is usable and non-zero when it is not; the
# runner's sourcing helper takes exactly one adapter per run and refuses
# unknown clients and contract-violating adapters.

test_adapter_01() {
  ok=0
  adapters=$(find "$BENCH_DIR" -maxdepth 1 -type f -name 'adapter-*.sh' | LC_ALL=C sort)
  [ -n "$adapters" ] || { echo "  no bench/adapter-<client>.sh files exist at all"; return 1; }
  printf '%s\n' "$adapters" | grep -q '/adapter-dryrun.sh$' \
    || { echo "  bench/adapter-dryrun.sh is missing"; ok=1; }
  for f in $adapters; do
    defs=$(awk '/^[A-Za-z_][A-Za-z0-9_]*\(\)[ \t]*\{/ { sub(/\(\).*/, ""); print }' "$f" \
      | LC_ALL=C sort | tr '\n' ' ')
    [ "$defs" = "bench_collect bench_detect bench_invoke " ] \
      || { echo "  $(basename "$f") defines a function set outside the contract: [$defs]"; ok=1; }
    adapter_lines "$f" | grep -Eq '(^|[;&|(]|[ \t])function [A-Za-z_]' \
      && { echo "  $(basename "$f") defines a function in another form"; ok=1; }
  done

  # the run-dir artifact convention is pinned in the library, once
  got=$(bench_run_artifacts | tr '\n' ' ' | sed 's/ *$//')
  [ "$got" = "$RUN_ARTIFACTS" ] \
    || { echo "  bench_run_artifacts drifts from the pinned run-dir artifact names: [$got]"; ok=1; }

  # usable client: bench_detect exits 0 and prints a non-empty version
  v=$(bench_detect) || { echo "  the dry-run adapter does not detect as usable"; ok=1; }
  [ -n "$v" ] || { echo "  bench_detect printed an empty version string"; ok=1; }

  td=$(new_tmp_dir)
  # not usable: an adapter whose bench_detect exits non-zero must land the
  # sourcing + detect sequence as "unusable" (fresh shell -- no inherited
  # function definitions)
  printf '%s\n' '#!/bin/sh' \
    'bench_detect() { return 3; }' \
    'bench_invoke() { return 0; }' \
    'bench_collect() { return 0; }' > "$td/adapter-fake.sh"
  env sh -c '
    . "$1"
    BENCH_DIR="$2"
    bench_source_adapter fake || exit 9
    if bench_detect; then exit 100; fi
    exit 0
  ' sh "$BENCH_DIR/lib.sh" "$td" \
    || { echo "  a non-zero bench_detect was not honored as unusable"; ok=1; }
  # an unknown client is refused
  env sh -c '. "$1"; BENCH_DIR="$2"; bench_source_adapter nosuchclient >/dev/null 2>&1' \
    sh "$BENCH_DIR/lib.sh" "$td" \
    && { echo "  sourcing an unknown client was not refused"; ok=1; }
  # an adapter missing a contract function is refused, naming the miss
  printf '%s\n' '#!/bin/sh' \
    'bench_detect() { return 0; }' \
    'bench_invoke() { return 0; }' > "$td/adapter-broken.sh"
  err=$(env sh -c '. "$1"; BENCH_DIR="$2"; bench_source_adapter broken' \
    sh "$BENCH_DIR/lib.sh" "$td" 2>&1) \
    && { echo "  sourcing a contract-violating adapter was not refused"; ok=1; }
  case "$err" in
    *bench_collect*) ;;
    *) echo "  the refusal did not name the missing contract function: $err"; ok=1 ;;
  esac
  # one adapter per run: sourcing one named adapter selects that file's
  # functions (two fresh shells, one adapter each)
  printf '%s\n' '#!/bin/sh' \
    'bench_detect() { printf "%s\n" ONE; }' \
    'bench_invoke() { return 0; }' \
    'bench_collect() { return 0; }' > "$td/adapter-one.sh"
  printf '%s\n' '#!/bin/sh' \
    'bench_detect() { printf "%s\n" TWO; }' \
    'bench_invoke() { return 0; }' \
    'bench_collect() { return 0; }' > "$td/adapter-two.sh"
  r1=$(env sh -c '. "$1"; BENCH_DIR="$2"; bench_source_adapter one && bench_detect' \
    sh "$BENCH_DIR/lib.sh" "$td") \
    || { echo "  sourcing a conforming synthetic adapter failed"; ok=1; }
  r2=$(env sh -c '. "$1"; BENCH_DIR="$2"; bench_source_adapter two && bench_detect' \
    sh "$BENCH_DIR/lib.sh" "$td") \
    || { echo "  sourcing the second synthetic adapter failed"; ok=1; }
  [ "$r1" = "ONE" ] && [ "$r2" = "TWO" ] \
    || { echo "  sourcing did not select exactly the named adapter ($r1/$r2)"; ok=1; }
  return $ok
}

# ---- adapter-02 ----------------------------------------------------------------
# invoke launches the mock client headless: working directory at the fixture
# repo, prompt taken from the request file, the antz-orchestrator as its
# entry point, non-interactive by construction (its stdin is /dev/null and
# no prompt can block the invocation), leaving the run dir's raw artifacts
# (client.stdout, client.stderr, client.exit) and running the client in the
# foreground, so a deadline kill reaches it (pinned behaviorally by
# adapter-06; here the mechanical no-backgrounding discipline).

test_adapter_02() {
  ok=0
  root=$(new_tmp_dir)
  prep_repetition "$root" || return 1
  invoke_bounded "$root/repo" "$root/run/request.txt" "$root/run" approved 1 10
  rc=$?
  [ "$rc" = 124 ] && { echo "  the invocation blocked or overran 10s -- something can prompt"; return 1; }
  [ "$rc" = 0 ] || { echo "  the approved invoke exited $rc"; ok=1; }

  # raw artifacts in the run dir
  for a in client.stdout client.stderr client.exit; do
    [ -f "$root/run/$a" ] || { echo "  the run dir lacks the raw artifact $a"; ok=1; }
  done
  [ "$(cat "$root/run/client.exit")" = "0" ] \
    || { echo "  client.exit does not carry the client's exit code"; ok=1; }
  [ "$(bench_deadline_fired "$root/run")" = "0" ] \
    || { echo "  a normal run left a timeout marker"; ok=1; }

  # entry point, working directory, and prompt provenance
  grep -q '^dryrun client: entry=antz-orchestrator$' "$root/run/client.stdout" \
    || { echo "  the client did not record the antz-orchestrator entry point"; ok=1; }
  want_cwd=$(cd "$root/repo" && pwd)
  grep -q "^dryrun client: cwd=$want_cwd\$" "$root/run/client.stdout" \
    || { echo "  the client did not run with its working directory at the fixture repo"; ok=1; }
  [ -f "$root/run/client.request" ] || { echo "  the client recorded no prompt"; ok=1; }
  cmp -s "$root/run/request.txt" "$root/run/client.request" \
    || { echo "  the client's prompt is not the request file's bytes"; ok=1; }

  # non-interactive by construction + foreground discipline (mechanical):
  # stdin closed from the device, no backgrounding, nohup, or disown
  grep -q '< /dev/null' "$BENCH_DIR/adapter-dryrun.sh" \
    || { echo "  the adapter does not run its client with stdin from /dev/null"; ok=1; }
  adapter_lines "$BENCH_DIR/adapter-dryrun.sh" \
    | grep -Eq 'nohup|disown|[^&]&[ \t]*$' \
    && { echo "  the adapter backgrounds its client -- a deadline kill could not apply"; ok=1; }

  assert_confined "$root" || ok=1
  return $ok
}

# ---- adapter-03 ----------------------------------------------------------------
# collect normalizes the run dir's artifacts into exactly the pinned
# telemetry keys -- one "key=value" line each, in the pinned order, the
# literal "null" where unavailable -- and makes no model call of its own:
# it survives an EMPTY PATH (pure builtins, so it launches nothing), and
# the dry-run adapter references no client binary and no network tool.

test_adapter_03() {
  ok=0
  root=$(new_tmp_dir)
  prep_repetition "$root" || return 1
  invoke_bounded "$root/repo" "$root/run/request.txt" "$root/run" approved 1 10 \
    || { echo "  the approved invoke failed"; return 1; }
  out=$(bench_collect "$root/run" "$root/repo") \
    || { echo "  collect failed after a completed run"; return 1; }

  # exactly one key=value line per pinned telemetry key, in the pinned order
  printf '%s\n' $COLLECT_KEYS > "$HARNESS_RUN_TMP/a3-exp.$$"
  printf '%s\n' "$out" | sed 's/=.*//' > "$HARNESS_RUN_TMP/a3-got.$$"
  cmp -s "$HARNESS_RUN_TMP/a3-got.$$" "$HARNESS_RUN_TMP/a3-exp.$$" \
    || { echo "  collect's key set or order drifts from the pinned telemetry keys:"; diff "$HARNESS_RUN_TMP/a3-got.$$" "$HARNESS_RUN_TMP/a3-exp.$$" | sed 's/^/    /'; ok=1; }
  for k in $COLLECT_KEYS; do
    n=$(printf '%s\n' "$out" | grep -c "^$k=")
    [ "$n" = "1" ] || { echo "  collect printed $n lines for $k, expected 1"; ok=1; }
  done
  # unavailable values are the literal null (the mock reports no reasoning
  # or cache-write tokens); available ones are non-empty
  [ "$(collect_val "$out" tokens_reasoning)" = "null" ] \
    || { echo "  an unreported key is not the literal null"; ok=1; }
  [ "$(collect_val "$out" tokens_cache_write)" = "null" ] \
    || { echo "  an unreported key is not the literal null"; ok=1; }
  for k in client_version client_duration_ms tokens_input cost_usd session_id; do
    v=$(collect_val "$out" "$k")
    [ -n "$v" ] && [ "$v" != "null" ] || { echo "  a reported key ($k) is null or empty"; ok=1; }
  done

  # no telemetry to normalize at all: every key is the literal null
  bare=$(new_tmp_dir)
  mkdir -p "$bare/run" || return 1
  out2=$(bench_collect "$bare/run" "$root/repo") \
    || { echo "  collect failed over an empty run dir"; return 1; }
  nulls=$(printf '%s\n' "$out2" | grep -c '=null$')
  [ "$nulls" = "13" ] || { echo "  an empty run dir collected to $nulls nulls, expected 13"; ok=1; }

  # no agent session, no model call: collect runs to completion with an
  # EMPTY PATH, i.e. it launches no external command whatsoever
  out3=$(env -i PATH= /bin/sh -c '
    . "$1"
    BENCH_DIR="$2"
    bench_source_adapter dryrun >/dev/null && bench_collect "$3" "$4"
  ' sh "$BENCH_DIR/lib.sh" "$BENCH_DIR" "$root/run" "$root/repo") \
    || { echo "  collect ran external commands (it may launch nothing)"; ok=1; }
  printf '%s\n' "$out3" | sed 's/=.*//' > "$HARNESS_RUN_TMP/a3-got2.$$"
  cmp -s "$HARNESS_RUN_TMP/a3-got2.$$" "$HARNESS_RUN_TMP/a3-exp.$$" \
    || { echo "  the PATH-less collect printed something other than the pinned keys"; ok=1; }
  adapter_lines "$BENCH_DIR/adapter-dryrun.sh" | grep -Eqw 'curl|wget' \
    && { echo "  the dry-run adapter reaches for the network"; ok=1; }
  adapter_lines "$BENCH_DIR/adapter-dryrun.sh" | grep -Eqi 'claude|opencode' \
    && { echo "  the dry-run adapter references a real client binary"; ok=1; }
  return $ok
}

# ---- adapter-04 ----------------------------------------------------------------
# The dry-run client scripts every outcome class by materializing the
# matching flow artifacts: one test per Examples row. Each invocation
# completes quickly (timeout: only once the harness kills it), with no
# network and no real client binary, and the materialized fixture repo
# carries exactly the artifacts that make the runner classify the outcome
# -- which is then the resulting record's outcome.

test_adapter_04_row() {
  outcome="$1"
  ok=0
  root=$(new_tmp_dir)
  prep_repetition "$root" || return 1
  outjsonl="$(new_tmp_dir)/results.jsonl"
  if [ "$outcome" = "timeout" ]; then
    kill_after_deadline "$root" 1 || return 1
    killed=1
    ec="$KD_RC"
    wall="$KD_WALL"
    note="harness deadline fired after 1s"
    [ "$KD_ALIVE" = "1" ] || { echo "  the timeout script ended before the deadline"; ok=1; }
    [ -s "$root/run/client.timeout" ] || { echo "  the run dir lacks the timeout marker"; ok=1; }
  else
    t0=$(now_ms)
    invoke_bounded "$root/repo" "$root/run/request.txt" "$root/run" "$outcome" 1 10
    rc=$?
    [ "$rc" = 124 ] && { echo "  the $outcome invocation did not complete quickly"; return 1; }
    wall=$(( $(now_ms) - t0 ))
    if [ "$wall" -ge 1000 ]; then echo "  the invocation took ${wall}ms -- not well under a second"; ok=1; fi
    killed=0
    ec="$rc"
    if [ "$outcome" = "error" ]; then
      [ "$rc" -ne 0 ] || { echo "  the error script exited 0"; ok=1; }
      note="dry-run exited $rc with no telemetry"
    else
      [ "$rc" = 0 ] || { echo "  the $outcome invoke exited $rc"; ok=1; }
      note=null
    fi
    [ "$(bench_deadline_fired "$root/run")" = "0" ] \
      || { echo "  a non-killed run left a timeout marker"; ok=1; }
  fi
  adapter_lines "$BENCH_DIR/adapter-dryrun.sh" | grep -Eqw 'curl|wget' \
    && { echo "  the dry-run adapter reaches for the network"; ok=1; }

  # the materialized disk artifacts alone classify the outcome
  got=$(bench_outcome_classify "$root/repo" "$killed")
  [ "$got" = "$outcome" ] \
    || { echo "  the scripted artifacts classified as '$got', expected $outcome"; ok=1; }

  # and the resulting record carries it
  emit_record_from "$outjsonl" "$root/repo" "$root/run" 1 "$killed" "$wall" "$ec" "$note" \
    || { echo "  the $outcome repetition's record was refused"; ok=1; return $ok; }
  line=$(tail -n 1 "$outjsonl")
  json_scan_keys "$line" > /dev/null \
    || { echo "  the record is not valid JSON: $line"; ok=1; }
  case "$line" in
    *'"outcome":"'"$outcome"'"'*) ;;
    *) echo "  the record's outcome is not $outcome: $line"; ok=1 ;;
  esac
  assert_confined "$root" || ok=1
  return $ok
}

# ---- adapter-05 ----------------------------------------------------------------
# Determinism with repetition-varying telemetry: the same scripted outcome
# run twice carries byte-identical flow artifacts and reports the same
# outcome and the same telemetry keys, while the telemetry values scale
# deterministically with the repetition number (so an aggregate over N is
# distinguishable from an aggregate over one), and client_version is the
# fixed non-empty detected version.

test_adapter_05() {
  ok=0
  c1f="$HARNESS_RUN_TMP/a5-c1.$$"; c2f="$HARNESS_RUN_TMP/a5-c2.$$"; c3f="$HARNESS_RUN_TMP/a5-c3.$$"
  r1=$(new_tmp_dir); r2=$(new_tmp_dir); r3=$(new_tmp_dir)
  for r in "$r1" "$r2" "$r3"; do
    prep_repetition "$r" || return 1
  done
  invoke_bounded "$r1/repo" "$r1/run/request.txt" "$r1/run" approved 1 10 \
    || { echo "  repetition 1 failed"; return 1; }
  invoke_bounded "$r2/repo" "$r2/run/request.txt" "$r2/run" approved 2 10 \
    || { echo "  repetition 2 failed"; return 1; }
  invoke_bounded "$r3/repo" "$r3/run/request.txt" "$r3/run" approved 2 10 \
    || { echo "  repetition 2 (rerun) failed"; return 1; }

  # byte-identical flow artifacts in their respective fixture repos
  diff -r -x .git "$r1/repo" "$r2/repo" > "$HARNESS_RUN_TMP/a5.diff.$$" 2>&1 \
    || { echo "  flow artifacts vary with the repetition number:"; sed 's/^/    /' "$HARNESS_RUN_TMP/a5.diff.$$"; ok=1; }

  # the same outcome, from both repos
  o1=$(bench_outcome_classify "$r1/repo" 0)
  o2=$(bench_outcome_classify "$r2/repo" 0)
  { [ "$o1" = approved ] && [ "$o2" = approved ]; } \
    || { echo "  the two runs did not both classify as approved ($o1/$o2)"; ok=1; }

  # the same telemetry keys, in the pinned order, from both collects
  c1=$(bench_collect "$r1/run" "$r1/repo"); printf '%s\n' "$c1" > "$c1f"
  c2=$(bench_collect "$r2/run" "$r2/repo"); printf '%s\n' "$c2" > "$c2f"
  c3=$(bench_collect "$r3/run" "$r3/repo"); printf '%s\n' "$c3" > "$c3f"
  printf '%s\n' $COLLECT_KEYS > "$HARNESS_RUN_TMP/a5-exp.$$"
  for cf in "$c1f" "$c2f"; do
    sed 's/=.*//' "$cf" > "$cf.keys.$$"
    cmp -s "$cf.keys.$$" "$HARNESS_RUN_TMP/a5-exp.$$" \
      || { echo "  a collect drifted from the pinned key set: $cf"; ok=1; }
  done

  # deterministic per repetition: the same repetition number collects
  # byte-identically
  cmp -s "$c2f" "$c3f" \
    || { echo "  repetition 2 collected differently across reruns (not deterministic)"; ok=1; }

  # the scaling values differ with the repetition number, upward
  for k in client_duration_ms tokens_input tokens_output tokens_cache_read turns tool_calls subagent_delegations; do
    v1=$(collect_val "$c1" "$k")
    v2=$(collect_val "$c2" "$k")
    case "$v1 $v2" in
      *null*) echo "  $k went null on a scripted success"; ok=1; continue ;;
    esac
    [ "$v2" -gt "$v1" ] \
      || { echo "  $k does not scale up with the repetition ($v1 -> $v2)"; ok=1; }
  done
  f1=$(collect_val "$c1" cost_usd)
  f2=$(collect_val "$c2" cost_usd)
  awk -v a="$f1" -v b="$f2" 'BEGIN { exit (b + 0 > a + 0 && a + 0 > 0) ? 0 : 1 }' \
    || { echo "  cost_usd does not scale with the repetition ($f1 -> $f2)"; ok=1; }
  # an aggregate over N repetitions is distinguishable from one over 1
  t1=$(collect_val "$c1" tokens_input)
  t2=$(collect_val "$c2" tokens_input)
  [ "$((t1 + t2))" != "$t1" ] || { echo "  a two-repetition aggregate equals the single"; ok=1; }

  # a fixed non-empty client_version: across reps and against detect
  cv1=$(collect_val "$c1" client_version)
  cv2=$(collect_val "$c2" client_version)
  [ -n "$cv1" ] && [ "$cv1" = "$cv2" ] && [ "$cv1" = "$(bench_detect)" ] \
    || { echo "  client_version is not the fixed non-empty detected version ($cv1/$cv2)"; ok=1; }
  return $ok
}

# ---- adapter-06 ----------------------------------------------------------------
# The timeout script exercises the harness kill: the dry-run process stays
# alive past a few-seconds deadline until the harness kills it, leaving the
# run dir's timeout marker; the record's outcome is timeout with a non-null
# error_note, wall_clock_ms at least the deadline, and null client
# telemetry.

test_adapter_06() {
  ok=0
  root=$(new_tmp_dir)
  prep_repetition "$root" || return 1
  kill_after_deadline "$root" 1 || return 1

  [ "$KD_ALIVE" = "1" ] || { echo "  the dry-run process did not stay alive past the deadline"; ok=1; }
  [ "$KD_RC" -ne 0 ] || { echo "  the killed dry-run process exited 0"; ok=1; }
  [ -s "$root/run/client.timeout" ] || { echo "  the run dir lacks a non-empty timeout marker"; ok=1; }
  [ "$(bench_deadline_fired "$root/run")" = "1" ] \
    || { echo "  bench_deadline_fired does not read the timeout marker"; ok=1; }
  [ "$KD_WALL" -ge "$KD_DEADLINE_MS" ] \
    || { echo "  the run ended at ${KD_WALL}ms, before the ${KD_DEADLINE_MS}ms deadline"; ok=1; }

  # the timeout classification is the harness's kill record: the repo alone
  # is not timeout evidence
  got=$(bench_outcome_classify "$root/repo" 1)
  [ "$got" = "timeout" ] || { echo "  killed classify gave '$got'"; ok=1; }
  got0=$(bench_outcome_classify "$root/repo" 0)
  [ "$got0" = "error" ] || { echo "  the same repo classified '$got0' without the kill record"; ok=1; }

  outjsonl="$(new_tmp_dir)/results.jsonl"
  emit_record_from "$outjsonl" "$root/repo" "$root/run" 1 1 "$KD_WALL" "$KD_RC" \
    "harness deadline fired after 1s" \
    || { echo "  the timeout record was refused"; return 1; }
  line=$(tail -n 1 "$outjsonl")
  json_scan_keys "$line" > /dev/null || { echo "  the timeout record is not valid JSON"; ok=1; }
  case "$line" in *'"outcome":"timeout"'*) ;; *) echo "  record outcome is not timeout: $line"; ok=1 ;; esac
  case "$line" in *'"error_note":"harness deadline fired after 1s"'*) ;; *) echo "  error_note missing or null: $line"; ok=1 ;; esac
  wm=$(printf '%s' "$line" | sed -n 's/.*"wall_clock_ms":\([0-9]*\).*/\1/p')
  [ -n "$wm" ] && [ "$wm" -ge "$KD_DEADLINE_MS" ] \
    || { echo "  the record's wall_clock_ms ($wm) is below the deadline"; ok=1; }
  ec=$(printf '%s' "$line" | sed -n 's/.*"exit_code":\([0-9]*\).*/\1/p')
  [ -n "$ec" ] && [ "$ec" != "null" ] || { echo "  the record's exit_code is null: $line"; ok=1; }
  for k in $COLLECT_KEYS; do
    case "$line" in
      *"\"$k\":null,"* | *"\"$k\":null}"*) ;;
      *) echo "  killed telemetry $k is not null in the record"; ok=1 ;;
    esac
  done
  assert_confined "$root" || ok=1
  return $ok
}

# ---- adapter-07 ----------------------------------------------------------------
# The error script exercises the failed-client path end to end: the process
# exits non-zero, writes no flow artifacts, emits no telemetry; the record's
# outcome is error with null telemetry, a non-null exit_code, and a
# non-null error_note.

test_adapter_07() {
  ok=0
  root=$(new_tmp_dir)
  prep_repetition "$root" || return 1
  invoke_bounded "$root/repo" "$root/run/request.txt" "$root/run" error 1 10
  rc=$?
  [ "$rc" = 124 ] && { echo "  the error invocation hung"; return 1; }
  [ "$rc" -ne 0 ] || { echo "  the error script exited 0"; return 1; }
  [ "$(cat "$root/run/client.exit")" = "$rc" ] \
    || { echo "  client.exit does not carry the failed client's exit code"; ok=1; }

  # no flow artifacts: the fixture repo still equals the pristine
  # materialization
  materialized_equal_to_source "$root/repo" > /dev/null \
    || { echo "  the error script wrote flow artifacts into the fixture repo"; ok=1; }
  [ ! -e "$root/repo/spdd" ] || { echo "  the error script created spdd/"; ok=1; }

  # no telemetry emitted: collect normalizes to all-null
  c=$(bench_collect "$root/run" "$root/repo")
  for k in $COLLECT_KEYS; do
    [ "$(collect_val "$c" "$k")" = "null" ] \
      || { echo "  the error run emitted telemetry for $k"; ok=1; }
  done

  outjsonl="$(new_tmp_dir)/results.jsonl"
  emit_record_from "$outjsonl" "$root/repo" "$root/run" 1 0 250 "$rc" \
    "dry-run exited $rc with no telemetry" \
    || { echo "  the error record was refused"; return 1; }
  line=$(tail -n 1 "$outjsonl")
  json_scan_keys "$line" > /dev/null || { echo "  the error record is not valid JSON"; ok=1; }
  case "$line" in *'"outcome":"error"'*) ;; *) echo "  record outcome is not error: $line"; ok=1 ;; esac
  ec=$(printf '%s' "$line" | sed -n 's/.*"exit_code":\([0-9]*\).*/\1/p')
  [ "$ec" = "$rc" ] || { echo "  the record's exit_code is not the client's ($ec vs $rc)"; ok=1; }
  case "$line" in *'"error_note":"dry-run exited '*) ;; *) echo "  error_note missing or null: $line"; ok=1 ;; esac
  for k in $COLLECT_KEYS; do
    case "$line" in
      *"\"$k\":null,"* | *"\"$k\":null}"*) ;;
      *) echo "  the error record carries non-null telemetry for $k"; ok=1 ;;
    esac
  done
  assert_confined "$root" || ok=1
  return $ok
}

# ---- adapter-08 ----------------------------------------------------------------
# The bench tree stays POSIX and interpreter-free: every bench/*.sh parses
# under sh -n, invokes no python/python3/jq/node/perl/ruby (nor kin), and
# carries no bashisms -- awk, sed, grep, and standard utilities are the
# only text tools.

test_adapter_08() {
  ok=0
  files=$(find "$BENCH_DIR" -maxdepth 1 -type f -name '*.sh' | LC_ALL=C sort)
  [ -n "$files" ] || { echo "  no bench/*.sh files found"; return 1; }
  seen_lib=0
  for f in $files; do
    err=$(sh -n "$f" 2>&1) || { echo "  sh -n rejects $(basename "$f"): $err"; ok=1; }
    case "$f" in */lib.sh) seen_lib=1 ;; esac
    if adapter_lines "$f" | grep -Eqw 'python|python2|python3|jq|node|nodejs|perl|ruby|php|lua|tclsh'; then
      echo "  $(basename "$f") invokes a non-POSIX interpreter"; ok=1
    fi
    if adapter_lines "$f" | grep -Eq '\[\[|<<<|(^|;|&|\(|[ \t])local[ \t]|(^|;|&|[ \t])declare[ \t]'; then
      echo "  $(basename "$f") uses a bashism outside POSIX sh"; ok=1
    fi
  done
  [ "$seen_lib" = 1 ] || { echo "  bench/lib.sh is missing from the scan"; ok=1; }
  # the allowed aids are the ones actually in use (a file that parsed while
  # using nothing else could not name them; this pins the substitutes)
  if adapter_lines "$BENCH_DIR/lib.sh" | grep -q 'awk'; then :; else echo "  bench/lib.sh no longer parses with awk"; ok=1; fi
  return $ok
}

# ---- clients test helpers -----------------------------------------------------
# Sub-spec 04 is exercised hermetically: the sandbox machinery of bench/lib.sh
# runs real sandboxed processes, the checkout rendering goes through the staged
# checkout's OWN install.sh, and both real adapters are driven against
# recording stub clients placed FIRST on PATH (the machine's real Claude Code
# and OpenCode are never invoked) with canned artifacts. A stub records every
# invocation's argv (raw bytes per argument, one file each), its environment,
# and its working directory under the sandbox HOME, so the invoke shape and
# the allowlist environment are directly inspectable after the run.

# The pinned allowlist key names, transcribed from the clients-01 scenario
# (PATH, HOME, TMPDIR, the sandbox variables, the pinned-model variable),
# sorted. The suite keeps its own copy on purpose: a drift goes red here.
SBX_ALLOW_KEYS="BENCH_MODEL CLAUDE_CONFIG_DIR HOME PATH TMPDIR XDG_CONFIG_HOME XDG_DATA_HOME"

# Canned Claude result JSON (one object; the fields the sub-spec pins).
CLAUDE_CANNED_RESULT='{"type":"result","subtype":"success","is_error":false,"duration_ms":4567,"num_turns":9,"result":"flow complete","session_id":"sess-abc-123","total_cost_usd":1.25,"usage":{"input_tokens":1000,"output_tokens":300,"cache_creation_input_tokens":200,"cache_read_input_tokens":5000},"modelUsage":{"stub-model-one":{"inputTokens":800,"costUSD":1.0},"stub-model-two":{"inputTokens":200,"costUSD":0.25}}}'

# The same result with no modelUsage object at all (clients-08: models_used
# is null exactly when the client reported no models).
CLAUDE_CANNED_RESULT_NOMODELS='{"type":"result","subtype":"success","is_error":false,"duration_ms":4567,"num_turns":9,"result":"flow complete","session_id":"sess-abc-123","total_cost_usd":1.25,"usage":{"input_tokens":1000,"output_tokens":300,"cache_creation_input_tokens":200,"cache_read_input_tokens":5000}}'

# Canned session transcript (JSONL): a primary entry with two tool_use
# blocks, two priced sidechain entries (agent side-1; usage adds
# 400+20 input, 50+10 output, 30+0 cache-write, 60+5 cache-read, cost
# 0.5+0.125) with one more tool_use each, and an unpriced sidechain entry
# with no usage (adds agent side-2 to the delegation count only).
CLAUDE_CANNED_TRANSCRIPT='{"type":"assistant","isSidechain":false,"message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{}},{"type":"tool_use","id":"t2","name":"Bash","input":{}}]}}
{"type":"assistant","isSidechain":true,"agentId":"side-1","message":{"content":[{"type":"tool_use","id":"t3","name":"Write","input":{}}]},"usage":{"input_tokens":400,"output_tokens":50,"cache_creation_input_tokens":30,"cache_read_input_tokens":60},"costUSD":0.5}
{"type":"assistant","isSidechain":true,"agentId":"side-1","message":{"content":[{"type":"tool_use","id":"t4","name":"Grep","input":{}}]},"usage":{"input_tokens":20,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":5},"costUSD":0.125}
{"type":"system","subtype":"stop","isSidechain":true,"agentId":"side-2"}'

# The same sidechain usage WITHOUT the costUSD fields: an unattributable
# cost, so the cost total goes null while the token adds still hold.
CLAUDE_CANNED_TRANSCRIPT_NOCOST='{"type":"assistant","isSidechain":true,"agentId":"side-1","message":{"content":[{"type":"tool_use","id":"t3","name":"Write","input":{}}]},"usage":{"input_tokens":400,"output_tokens":50,"cache_creation_input_tokens":30,"cache_read_input_tokens":60}}
{"type":"assistant","isSidechain":true,"agentId":"side-1","message":{"content":[{"type":"tool_use","id":"t4","name":"Grep","input":{}}]},"usage":{"input_tokens":20,"output_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":5}}'

# Canned OpenCode run events (JSONL; the session id the parent export is
# fetched for comes from here), and the parent + two child exports. The
# parent's totals (1000/200/40/300/20, cost 1.5) exclude the children; its
# two task parts name them under state.metadata (one "sessionID", one
# "sessionId" -- both casings must be found).
OC_CANNED_EVENTS='{"type":"text","sessionID":"ses_parent_1","part":{"type":"text","text":"working"}}
{"type":"step-finish","sessionID":"ses_parent_1","part":{"type":"step-finish","tokens":{"input":10,"output":2,"reasoning":0,"cache":{"read":5,"write":1}},"cost":0.01}}'

OC_CANNED_PARENT='{"info":{"id":"ses_parent_1","title":"bench run","model":"anthropic/stub-model-x","cost":1.5,"tokens":{"input":1000,"output":200,"reasoning":40,"cache":{"read":300,"write":20}},"time":{"created":1000000,"updated":1004500}},"messages":[{"role":"user","parts":[{"type":"text","text":"go"}]},{"role":"assistant","parts":[{"type":"tool","tool":"task","state":{"status":"completed","metadata":{"sessionID":"ses_child_a"}}},{"type":"tool","tool":"task","state":{"status":"completed","metadata":{"sessionId":"ses_child_b"}}},{"type":"tool","tool":"bash","state":{"output":"ok"}}]}]}'

OC_CANNED_CHILD_A='{"info":{"id":"ses_child_a","model":"anthropic/stub-model-x","cost":0.25,"tokens":{"input":100,"output":30,"reasoning":5,"cache":{"read":10,"write":2}},"time":{"created":1001000,"updated":1002000}},"messages":[{"role":"assistant","parts":[{"type":"tool","tool":"bash","state":{"output":"a"}}]}]}'

OC_CANNED_CHILD_B='{"info":{"id":"ses_child_b","model":"openai/stub-model-y","cost":0.125,"tokens":{"input":50,"output":10,"reasoning":0,"cache":{"read":1,"write":0}},"time":{"created":1002000,"updated":1003000}},"messages":[{"role":"assistant","parts":[{"type":"tool","tool":"edit","state":{}},{"type":"tool","tool":"read","state":{}}]}]}'

make_claude_stub() {
  # $1 = a bin dir to receive the executable "claude" recording stub.
  # Invocation 1 answers --version; any other invocation replays the canned
  # result/stderr from $HOME/canned/, writes the canned transcript into the
  # relocated config tree under the result's session id (what the real
  # client leaves for the adapter to copy), and exits with the canned code.
  mkdir -p "$1" || return 1
  cat > "$1/claude" <<'EOS'
#!/bin/sh
d="$HOME/stub"
mkdir -p "$d"
n=0
[ -f "$d/invocations" ] && n=$(cat "$d/invocations")
n=$((n + 1))
printf '%s\n' "$n" > "$d/invocations"
i=0
for a in "$@"; do
  i=$((i + 1))
  printf '%s' "$a" > "$d/argv.$n.$i"
done
env | LC_ALL=C sort > "$d/env.$n"
pwd > "$d/cwd.$n"
if [ "${1:-}" = "--version" ]; then
  printf '%s\n' "9.9.9-stub"
  exit 0
fi
cat "$HOME/canned/result.json" 2>/dev/null
if [ -f "$HOME/canned/result.stderr" ]; then cat "$HOME/canned/result.stderr" >&2; fi
sid=""
if [ -f "$HOME/canned/result.json" ]; then
  sid=$(sed -n 's/.*"session_id"[^"]*"\([^"]*\)".*/\1/p' "$HOME/canned/result.json" | head -n 1)
fi
case "$sid" in ''|*[!A-Za-z0-9._-]*) sid='' ;; esac
if [ -n "$sid" ] && [ -f "$HOME/canned/transcript.jsonl" ]; then
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/stubproj"
  cp "$HOME/canned/transcript.jsonl" "$CLAUDE_CONFIG_DIR/projects/stubproj/$sid.jsonl"
fi
rc=$(cat "$HOME/canned/exit" 2>/dev/null || printf '0')
exit "$rc"
EOS
  chmod +x "$1/claude"
}

make_opencode_stub() {
  # $1 = a bin dir to receive the executable "opencode" recording stub.
  # --version answers with the pinned stub version; "export <sid>" replays
  # $HOME/canned/export-<sid>.json when present (non-zero when absent -- an
  # unavailable export, exactly the partial-coverage case); anything else is
  # the run mode, replaying the canned events.
  mkdir -p "$1" || return 1
  cat > "$1/opencode" <<'EOS'
#!/bin/sh
d="$HOME/stub"
mkdir -p "$d"
n=0
[ -f "$d/invocations" ] && n=$(cat "$d/invocations")
n=$((n + 1))
printf '%s\n' "$n" > "$d/invocations"
i=0
for a in "$@"; do
  i=$((i + 1))
  printf '%s' "$a" > "$d/argv.$n.$i"
done
env | LC_ALL=C sort > "$d/env.$n"
pwd > "$d/cwd.$n"
case "${1:-}" in
  --version)
    printf '%s\n' "1.18.31-stub"
    exit 0
    ;;
  export)
    f="$HOME/canned/export-$2.json"
    if [ -f "$f" ]; then
      cat "$f"
      exit 0
    fi
    printf 'no such session: %s\n' "$2" 1>&2
    exit 1
    ;;
esac
cat "$HOME/canned/events.jsonl" 2>/dev/null
if [ -f "$HOME/canned/result.stderr" ]; then cat "$HOME/canned/result.stderr" >&2; fi
rc=$(cat "$HOME/canned/exit" 2>/dev/null || printf '0')
exit "$rc"
EOS
  chmod +x "$1/opencode"
}

plant_claude_canned() {
  # $1 = the sandbox HOME; stage the canned Claude artifacts + exit code.
  mkdir -p "$1/canned" || return 1
  printf '%s\n' "$CLAUDE_CANNED_RESULT" > "$1/canned/result.json"
  printf '%s\n' "$CLAUDE_CANNED_TRANSCRIPT" > "$1/canned/transcript.jsonl"
  printf 'claude stub noise on stderr\n' > "$1/canned/result.stderr"
  printf '0\n' > "$1/canned/exit"
}

plant_opencode_canned() {
  # $1 = the sandbox HOME; stage the canned events, all three exports,
  # stderr noise, and exit code.
  mkdir -p "$1/canned" || return 1
  printf '%s\n' "$OC_CANNED_EVENTS" > "$1/canned/events.jsonl"
  printf '%s\n' "$OC_CANNED_PARENT" > "$1/canned/export-ses_parent_1.json"
  printf '%s\n' "$OC_CANNED_CHILD_A" > "$1/canned/export-ses_child_a.json"
  printf '%s\n' "$OC_CANNED_CHILD_B" > "$1/canned/export-ses_child_b.json"
  printf 'opencode stub noise on stderr\n' > "$1/canned/result.stderr"
  printf '0\n' > "$1/canned/exit"
}

stub_arg_index() {
  # $1 stub dir, $2 invocation no., $3 token -- print the 1-based argv index
  # of the first argument equal to the token (tokens never carry trailing
  # newlines, so command substitution is exact here).
  d="$1"; n="$2"; tok="$3"; i=1
  while [ -f "$d/argv.$n.$i" ]; do
    if [ "$(cat "$d/argv.$n.$i")" = "$tok" ]; then
      printf '%s\n' "$i"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

stub_arg_pair() {
  # $1 stub dir, $2 invocation, $3 flag, $4 value -- 0 when the flag appears
  # immediately followed by that value.
  i=$(stub_arg_index "$1" "$2" "$3") || return 1
  j=$((i + 1))
  [ -f "$1/argv.$2.$j" ] || return 1
  [ "$(cat "$1/argv.$2.$j")" = "$4" ]
}

stub_arg_absent() {
  # $1 stub dir, $2 invocation, $3 token -- 0 when NO argument equals it.
  if stub_arg_index "$1" "$2" "$3" >/dev/null; then
    echo "  invocation $2 carries argument [$3] but must not"
    return 1
  fi
  return 0
}

stub_arg_bytes_file() {
  # $1 stub dir, $2 invocation, $3 file -- 0 when SOME argument's bytes are
  # exactly the file's (the multi-line prompt, compared whole).
  d="$1"; n="$2"; f="$3"; i=1
  while [ -f "$d/argv.$n.$i" ]; do
    if cmp -s "$d/argv.$n.$i" "$f"; then
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

expect_env_kv() {
  # $1 = a stub env dump, rest KEY=VALUE lines -- each must appear exactly.
  f="$1"; shift
  for kv in "$@"; do
    grep -Fxq "$kv" "$f" || { echo "  client env lacks [$kv]"; return 1; }
  done
}

expect_env_absent() {
  # $1 = a stub env dump, rest KEY -- no line may start with KEY=.
  f="$1"; shift
  for k in "$@"; do
    if grep -q "^$k=" "$f"; then
      echo "  client env carries $k=... but must not"
      return 1
    fi
  done
  return 0
}

env_key_set() {
  # $1 = stub env dump -- the exported key names, sorted, minus the ones a
  # POSIX shell sets for itself (PWD/SHLVL/_) so the set can be pinned.
  cut -d= -f1 < "$1" | grep -vE '^(PWD|SHLVL|_)$' | LC_ALL=C sort | tr '\n' ' '
}

assert_collect_kv() {
  # $1 = collect output, rest key=value -- the 13 pinned keys must appear as
  # exactly 13 lines in the pinned order, each with the expected value.
  out="$1"; shift
  n=0
  for k in $COLLECT_KEYS; do
    n=$((n + 1))
    line=$(printf '%s\n' "$out" | sed -n "${n}p")
    case "$line" in
      "$k="*) ;;
      *) echo "  collect line $n: expected key $k, got [$line]"; return 1 ;;
    esac
  done
  total=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
  [ "$total" = "$n" ] || { echo "  collect printed $total lines, expected $n"; return 1; }
  for exp in "$@"; do
    k=${exp%%=*}
    got=$(collect_val "$out" "$k")
    want=${exp#*=}
    [ "$got" = "$want" ] || { echo "  $k: expected [$want], got [$got]"; return 1; }
  done
  return 0
}

# ---- clients-01 ----------------------------------------------------------------
# One sandbox per repetition: a fresh tree under temp space for HOME,
# XDG_CONFIG_HOME, XDG_DATA_HOME and CLAUDE_CONFIG_DIR; the client process
# sees ONLY the minimal allowlist environment (no ANTHROPIC_* / CLAUDE_* /
# OPENCODE_* passthrough, not even the runner-owned BENCH_SANDBOX); and a
# client running in the sandbox writes nowhere outside the sandbox tree --
# the canary planted beside the sandbox root survives untouched.

test_clients_01() {
  t=$(new_tmp_dir)
  t2=$(new_tmp_dir)
  sbx="$t/sbx"
  mkdir -p "$t/bin"
  cat > "$t/bin/wclient" <<'EOS'
#!/bin/sh
env > "$HOME/client-env.txt"
printf 'x\n' > "$HOME/wrote-home"
printf 'x\n' > "$TMPDIR/wrote-tmp"
printf 'x\n' > "$CLAUDE_CONFIG_DIR/wrote-claude"
printf 'x\n' > "$XDG_CONFIG_HOME/wrote-xdgconfig"
printf 'x\n' > "$XDG_DATA_HOME/wrote-xdgdata"
EOS
  chmod +x "$t/bin/wclient"
  printf 'canary-bytes\n' > "$t/canary"

  bench_sandbox_create "$sbx" > /dev/null \
    || { echo "  bench_sandbox_create refused a fresh root"; return 1; }
  for d in home home/.claude home/.config home/.local/share tmp; do
    [ -d "$sbx/$d" ] || { echo "  sandbox lacks directory: $d"; return 1; }
  done
  # a reused, non-empty root is refused (no repetition inherits another's writes)
  if bench_sandbox_create "$sbx" > /dev/null 2>&1; then
    echo "  reusing a non-empty sandbox root was accepted"
    return 1
  fi

  # inventory before the client runs (bin + canary + sbx skeleton exist now)
  (cd "$t" && find . | LC_ALL=C sort) > "$t2/before"
  # the invoking shell carries hostile variables; the allowlist drops them all
  (
    ANTHROPIC_API_KEY='leak-anthropic'
    CLAUDE_CODE_STUFF='leak-claude'
    OPENCODE_AUTH_CONTENT='leak-opencode'
    BENCH_SANDBOX='/not/in/the/sandbox'
    BENCH_MODEL='pin-model-test'
    export ANTHROPIC_API_KEY CLAUDE_CODE_STUFF OPENCODE_AUTH_CONTENT BENCH_SANDBOX BENCH_MODEL
    PATH="$t/bin:$PATH" bench_sandbox_run "$sbx" wclient
  ) || { echo "  the sandboxed client invocation failed"; return 1; }
  (cd "$t" && find . | LC_ALL=C sort) > "$t2/after"

  envf="$sbx/home/client-env.txt"
  [ -f "$envf" ] || { echo "  the client recorded no environment dump"; return 1; }
  # minimal allowlist: exactly the pinned key set (shell-self-set PWD/SHLVL/_
  # filtered), values pointing inside the sandbox
  got=$(env_key_set "$envf")
  [ "$got" = "$SBX_ALLOW_KEYS " ] \
    || { echo "  client env key set [$got] is not the allowlist [$SBX_ALLOW_KEYS ]"; return 1; }
  expect_env_kv "$envf" \
    "HOME=$sbx/home" \
    "TMPDIR=$sbx/tmp" \
    "XDG_CONFIG_HOME=$sbx/home/.config" \
    "XDG_DATA_HOME=$sbx/home/.local/share" \
    "CLAUDE_CONFIG_DIR=$sbx/home/.claude" \
    "BENCH_MODEL=pin-model-test" \
    || return 1
  expect_env_absent "$envf" ANTHROPIC_API_KEY CLAUDE_CODE_STUFF OPENCODE_AUTH_CONTENT BENCH_SANDBOX || return 1

  # the client's writes land in the sandbox tree only
  for w in home/wrote-home tmp/wrote-tmp home/.claude/wrote-claude home/.config/wrote-xdgconfig home/.local/share/wrote-xdgdata; do
    [ -f "$sbx/$w" ] || { echo "  client write missing inside the sandbox: $w"; return 1; }
  done
  added=$(LC_ALL=C comm -13 "$t2/before" "$t2/after")
  stray=$(printf '%s\n' "$added" | grep -v '^\./sbx/')
  [ -z "$stray" ] || { echo "  files appeared outside the sandbox tree:"; printf '%s\n' "$stray" | sed 's/^/    /'; return 1; }
  printf 'canary-bytes\n' | cmp -s - "$t/canary" \
    || { echo "  the canary beside the sandbox root changed"; return 1; }
  return 0
}

# ---- clients-02 ----------------------------------------------------------------
# The measured antz is the checkout under test, rendered into the sandbox by
# its OWN install.sh (forced per client, inside the sandbox environment): the
# sandbox's agents directory and scripts libdir carry the checkout's content
# -- VERSION in every antz:generated marker, the orchestrator body already
# referencing the SANDBOX's libdir, no placeholder surviving -- and the
# machine's global install is never written to or read from.

test_clients_02() {
  t=$(new_tmp_dir)
  co="$t/checkout"
  stage_checkout "$co" || { echo "  staging the checkout failed"; return 1; }
  ver=$(tr -d ' \t\r\n' < "$co/VERSION")

  sbx="$t/sbx-claude"
  bench_sandbox_create "$sbx" > /dev/null || return 1
  bench_sandbox_install "$sbx" claude "$co" > "$t/install-claude.log" 2>&1 \
    || { echo "  sandbox render for claude failed:"; sed 's/^/    /' "$t/install-claude.log"; return 1; }
  ag="$sbx/home/.claude/agents"
  [ -f "$ag/antz-specifier.md" ] || { echo "  no antz-specifier.md rendered into the sandbox agents dir"; return 1; }
  [ -f "$ag/antz-orchestrator.md" ] || { echo "  no antz-orchestrator.md rendered into the sandbox agents dir"; return 1; }
  grep -qF "# antz:generated version=$ver " "$ag/antz-specifier.md" \
    || { echo "  the sandbox specifier agent lacks the checkout VERSION in its antz:generated marker"; return 1; }
  grep -qF '__ANTZ_SCRIPTS_DIR__' "$ag/antz-orchestrator.md" \
    && { echo "  the __ANTZ_SCRIPTS_DIR__ placeholder survived the render"; return 1; }
  grep -qF "$sbx/home/.config/antz/scripts" "$ag/antz-orchestrator.md" \
    || { echo "  the orchestrator body does not reference the sandbox libdir"; return 1; }
  for s in antz-flow.sh antz-probe.sh antz-skills.sh antz-set-model.sh; do
    [ -f "$sbx/home/.config/antz/scripts/$s" ] || { echo "  sandbox libdir lacks $s"; return 1; }
  done
  # the forced flag renders ONLY that client
  [ ! -e "$sbx/home/.config/opencode" ] \
    || { echo "  a claude-forced render wrote OpenCode destinations"; return 1; }

  sbx2="$t/sbx-opencode"
  bench_sandbox_create "$sbx2" > /dev/null || return 1
  bench_sandbox_install "$sbx2" opencode "$co" > "$t/install-opencode.log" 2>&1 \
    || { echo "  sandbox render for opencode failed:"; sed 's/^/    /' "$t/install-opencode.log"; return 1; }
  ag2="$sbx2/home/.config/opencode/agents"
  [ -f "$ag2/antz-specifier.md" ] || { echo "  no antz-specifier.md rendered into the sandbox OpenCode agents dir"; return 1; }
  grep -qF "# antz:generated version=$ver " "$ag2/antz-specifier.md" \
    || { echo "  the OpenCode sandbox specifier agent lacks the checkout VERSION marker"; return 1; }
  grep -qF '__ANTZ_SCRIPTS_DIR__' "$ag2/antz-orchestrator.md" \
    && { echo "  the placeholder survived the OpenCode render"; return 1; }
  grep -qF "$sbx2/home/.config/antz/scripts" "$ag2/antz-orchestrator.md" \
    || { echo "  the OpenCode orchestrator body does not reference the sandbox libdir"; return 1; }
  [ ! -e "$sbx2/home/.claude/agents" ] \
    || { echo "  an opencode-forced render wrote Claude Code destinations"; return 1; }

  # refusals: an unknown client, and a dir that is not an antz checkout
  if bench_sandbox_install "$sbx" gemini "$co" > /dev/null 2>&1; then
    echo "  an unknown client was accepted for the sandbox render"
    return 1
  fi
  mkdir -p "$t/not-a-checkout"
  if bench_sandbox_install "$sbx" claude "$t/not-a-checkout" > /dev/null 2>&1; then
    echo "  a non-checkout dir was accepted for the sandbox render"
    return 1
  fi
  return 0
}

# ---- clients-03 ----------------------------------------------------------------
# Credentials are copied into the sandbox read-only; the original's bytes and
# location never change; an absent credential is SKIPPED (never fabricated),
# the preparation still succeeds, and the client's own failure surfaces as an
# error outcome classification -- no run is poisoned into faking auth.

test_clients_03() {
  t=$(new_tmp_dir)
  sbx="$t/sbx"
  bench_sandbox_create "$sbx" > /dev/null || return 1
  real="$t/realhome"
  mkdir -p "$real/.claude" "$real/.local/share/opencode" "$t/bin"
  printf 'CLAUDE-CRED-BLOB\n' > "$real/.claude/.credentials.json"
  printf 'OPENCODE-AUTH-BLOB\n' > "$real/.local/share/opencode/auth.json"

  out=$(bench_sandbox_copy_credentials "$real/.claude/.credentials.json" "$sbx/home/.claude/.credentials.json") \
    || { echo "  the Claude credential copy failed: $out"; return 1; }
  case "$out" in copied\ *) ;; *) echo "  expected a 'copied' outcome, got [$out]"; return 1 ;; esac
  printf 'CLAUDE-CRED-BLOB\n' | cmp -s - "$sbx/home/.claude/.credentials.json" \
    || { echo "  the sandbox credential differs from the original's bytes"; return 1; }
  # the copy is read-only (no write bit anywhere in its mode)
  mode=$(ls -l "$sbx/home/.claude/.credentials.json" | awk '{print $1}')
  case "$mode" in *w*) echo "  the sandbox credential is still writable [$mode]"; return 1 ;; esac
  # the original is unchanged: same bytes, still writable, same location
  printf 'CLAUDE-CRED-BLOB\n' | cmp -s - "$real/.claude/.credentials.json" \
    || { echo "  the original credential's bytes changed"; return 1; }
  [ -w "$real/.claude/.credentials.json" ] \
    || { echo "  the original credential lost its write permission"; return 1; }

  out=$(bench_sandbox_copy_credentials "$real/.local/share/opencode/auth.json" "$sbx/home/.local/share/opencode/auth.json") \
    || { echo "  the OpenCode credential copy failed: $out"; return 1; }
  case "$out" in copied\ *) ;; *) echo "  expected a 'copied' outcome, got [$out]"; return 1 ;; esac
  printf 'OPENCODE-AUTH-BLOB\n' | cmp -s - "$sbx/home/.local/share/opencode/auth.json" \
    || { echo "  the sandbox auth.json differs from the original"; return 1; }

  # absent credential: skipped, nothing fabricated, exit status stays success
  sbx2="$t/sbx-nocred"
  bench_sandbox_create "$sbx2" > /dev/null || return 1
  out=$(bench_sandbox_copy_credentials "$real/.claude/absent-credentials.json" "$sbx2/home/.claude/.credentials.json") \
    || { echo "  copying an absent credential failed: $out"; return 1; }
  case "$out" in skipped\ *) ;; *) echo "  expected a 'skipped' outcome, got [$out]"; return 1 ;; esac
  [ ! -e "$sbx2/home/.claude/.credentials.json" ] \
    || { echo "  a credential was FABRICATED for the absent file"; return 1; }

  # the run still proceeds: a credential-requiring client in the sandbox
  # fails on its own, and that failure classifies as an error outcome
  cat > "$t/bin/needs-cred" <<'EOS'
#!/bin/sh
if [ -f "$HOME/.claude/.credentials.json" ]; then
  printf 'would run the flow\n'
  exit 0
fi
printf 'not logged in\n' 1>&2
exit 77
EOS
  chmod +x "$t/bin/needs-cred"
  rc=0
  PATH="$t/bin:$PATH" bench_sandbox_run "$sbx2" needs-cred > "$t/nocred.out" 2> "$t/nocred.err" || rc=$?
  [ "$rc" -ne 0 ] || { echo "  the credential-less client claimed success"; return 1; }
  grep -q 'not logged in' "$t/nocred.err" || { echo "  the client's own failure did not surface"; return 1; }
  prep_repetition "$t/rep" || { echo "  repetition prep failed"; return 1; }
  outcome=$(bench_outcome_classify "$t/rep/repo" 0) || { echo "  classification failed"; return 1; }
  [ "$outcome" = error ] || { echo "  a credential-less failed run classified as [$outcome], expected error"; return 1; }
  return 0
}

# ---- clients-04 ----------------------------------------------------------------
# The Claude adapter's invoke shape, pinned through a recording stub: the
# print (headless) flag carrying the request text verbatim, the agent
# selection naming antz-orchestrator, the single-result JSON output format,
# the permission auto-approval flag, and --model exactly when a model is
# pinned (never when not); the stub runs at the fixture repo in the
# clients-01 sandbox environment; the run dir gains the pinned raw artifacts
# (client.stdout / client.stderr / client.exit) plus the recorded version
# and the session transcript pulled out of the sandbox.

test_clients_04() {
  t=$(new_tmp_dir)
  make_claude_stub "$t/bin" || return 1
  bench_source_adapter claude || { echo "  the claude adapter refuses to source"; return 1; }
  prep_repetition "$t/rep" || return 1
  sbx="$t/sbx"
  bench_sandbox_create "$sbx" > /dev/null || return 1
  plant_claude_canned "$sbx/home" || return 1
  printf 'untouched\n' > "$t/canary"

  stub="$sbx/home/stub"
  (
    unset BENCH_MODEL 2>/dev/null
    ANTHROPIC_API_KEY='should-not-leak'
    export ANTHROPIC_API_KEY BENCH_SANDBOX="$sbx"
    PATH="$t/bin:$PATH" bench_invoke "$t/rep/repo" "$t/rep/run/request.txt" "$t/rep/run"
  ) || { echo "  bench_invoke returned non-zero"; return 1; }

  n=$(cat "$stub/invocations" 2>/dev/null)
  [ "$n" = 2 ] || { echo "  the stub ran $n times, expected 2 (version + run)"; return 1; }
  # the recorded version call is headless-safe too, and precedes the run
  [ "$(cat "$stub/argv.1.1")" = "--version" ] || { echo "  invocation 1 is not --version"; return 1; }
  # the run invocation carries the pinned flags
  [ "$(cat "$stub/argv.2.1")" = "-p" ] || { echo "  the run argv does not start with the print flag -p"; return 1; }
  stub_arg_pair "$stub" 2 --agent antz-orchestrator || { echo "  no '--agent antz-orchestrator' pair in the run argv"; return 1; }
  stub_arg_pair "$stub" 2 --output-format json || { echo "  no '--output-format json' pair in the run argv"; return 1; }
  stub_arg_index "$stub" 2 --dangerously-skip-permissions > /dev/null \
    || { echo "  no permission auto-approval flag in the run argv"; return 1; }
  stub_arg_bytes_file "$stub" 2 "$t/rep/run/request.txt" \
    || { echo "  the request bytes never arrived verbatim as an argv word"; return 1; }
  # unpinned: no model flag at all
  stub_arg_absent "$stub" 2 --model || return 1
  stub_arg_absent "$stub" 2 -m || return 1
  # the clients-01 environment reached the client intact (and nothing else)
  expect_env_kv "$stub/env.2" \
    "HOME=$sbx/home" \
    "CLAUDE_CONFIG_DIR=$sbx/home/.claude" \
    "XDG_CONFIG_HOME=$sbx/home/.config" \
    || return 1
  expect_env_absent "$stub/env.2" ANTHROPIC_API_KEY BENCH_SANDBOX BENCH_MODEL || return 1
  # working directory: the fixture repo
  want_cwd=$(CDPATH= cd -- "$t/rep/repo" && pwd)
  [ "$(cat "$stub/cwd.2")" = "$want_cwd" ] \
    || { echo "  the client ran at [$(cat "$stub/cwd.2")], expected the fixture repo"; return 1; }

  # the run dir's pinned artifacts
  run="$t/rep/run"
  cmp -s "$sbx/home/canned/result.json" "$run/client.stdout" \
    || { echo "  client.stdout is not the stub's stdout"; return 1; }
  grep -q 'claude stub noise' "$run/client.stderr" || { echo "  client.stderr lost the stub's stderr"; return 1; }
  [ "$(cat "$run/client.exit")" = 0 ] || { echo "  client.exit is not the stub's 0"; return 1; }
  [ "$(cat "$run/client.version")" = "9.9.9-stub" ] || { echo "  client.version was not recorded"; return 1; }
  cmp -s "$sbx/home/canned/transcript.jsonl" "$run/transcript.jsonl" \
    || { echo "  the session transcript was not pulled from the sandbox config tree"; return 1; }
  # the canary beside the sandbox root survived the whole repetition
  printf 'untouched\n' | cmp -s - "$t/canary" || { echo "  the canary changed"; return 1; }
  return 0
}

# ---- clients-05 ----------------------------------------------------------------
# The Claude adapter's collect: result JSON plus the isolated transcript,
# with subagent attribution. Tokens and cost cover the primary result AND
# the sidechain usage the transcript exposes (a sidechain usage entry the
# transcript does not PRICE nulls the cost total rather than undercount);
# turns / duration / session / models come from the result; tool_calls
# counts tool_use blocks across primary and sidechain entries; with no
# transcript the token totals come from the result alone and the
# transcript-only fields are null -- nothing crashes, nothing is invented.

test_clients_05() {
  t=$(new_tmp_dir)
  bench_source_adapter claude || return 1
  r="$t/rep"
  mkdir -p "$r/run" "$r/repo" || return 1
  printf '%s\n' "$CLAUDE_CANNED_RESULT" > "$r/run/client.stdout"
  printf '%s\n' "$CLAUDE_CANNED_TRANSCRIPT" > "$r/run/transcript.jsonl"
  printf '9.9.9-stub\n' > "$r/run/client.version"

  out=$(bench_collect "$r/run" "$r/repo") || { echo "  collect failed"; return 1; }
  assert_collect_kv "$out" \
    client_version=9.9.9-stub \
    client_duration_ms=4567 \
    tokens_input=1420 \
    tokens_output=360 \
    tokens_reasoning=null \
    tokens_cache_read=5065 \
    tokens_cache_write=230 \
    cost_usd=1.875 \
    turns=9 \
    tool_calls=4 \
    subagent_delegations=2 \
    models_used=stub-model-one,stub-model-two \
    session_id=sess-abc-123 \
    || { echo "  attributed collect: $(printf '%s\n' "$out" | tr '\n' '|')"; return 1; }

  # unpriced sidechain usage: the cost total goes null, the token adds hold
  printf '%s\n' "$CLAUDE_CANNED_TRANSCRIPT_NOCOST" > "$r/run/transcript.jsonl"
  out=$(bench_collect "$r/run" "$r/repo") || return 1
  assert_collect_kv "$out" \
    cost_usd=null \
    tokens_input=1420 \
    tool_calls=2 \
    || { echo "  unpriced sidechain usage must null the cost, tokens keep adding: $(printf '%s\n' "$out" | tr '\n' '|')"; return 1; }

  # no transcript: result-only totals, transcript-only fields null
  rm -f "$r/run/transcript.jsonl"
  out=$(bench_collect "$r/run" "$r/repo") || return 1
  assert_collect_kv "$out" \
    tokens_input=1000 \
    tokens_output=300 \
    tokens_cache_read=5000 \
    tokens_cache_write=200 \
    cost_usd=1.25 \
    turns=9 \
    client_duration_ms=4567 \
    session_id=sess-abc-123 \
    models_used=stub-model-one,stub-model-two \
    tool_calls=null \
    subagent_delegations=null \
    || { echo "  transcript-less collect must be result-only + null: $(printf '%s\n' "$out" | tr '\n' '|')"; return 1; }

  # a run with no artifacts at all: all-null telemetry, still the 13 keys
  r2="$t/empty"
  mkdir -p "$r2/run" "$r2/repo" || return 1
  out=$(bench_collect "$r2/run" "$r2/repo") || { echo "  collect on an empty run dir must not crash"; return 1; }
  assert_collect_kv "$out" \
    client_version=null client_duration_ms=null tokens_input=null tokens_output=null \
    tokens_reasoning=null tokens_cache_read=null tokens_cache_write=null cost_usd=null \
    turns=null tool_calls=null subagent_delegations=null models_used=null session_id=null \
    || { echo "  the all-null collect is wrong: $(printf '%s\n' "$out" | tr '\n' '|')"; return 1; }
  return 0
}

# ---- clients-06 ----------------------------------------------------------------
# The OpenCode adapter's invoke shape, pinned through a recording stub: the
# run subcommand carrying the request text verbatim, the agent selection
# naming antz-orchestrator, the JSON event format, the permission
# auto-approval flag, and the model flag exactly when a model is pinned;
# the stub runs at the fixture repo in the clients-01 sandbox environment.

test_clients_06() {
  t=$(new_tmp_dir)
  make_opencode_stub "$t/bin" || return 1
  bench_source_adapter opencode || { echo "  the opencode adapter refuses to source"; return 1; }
  prep_repetition "$t/rep" || return 1
  sbx="$t/sbx"
  bench_sandbox_create "$sbx" > /dev/null || return 1
  plant_opencode_canned "$sbx/home" || return 1

  stub="$sbx/home/stub"
  (
    unset BENCH_MODEL 2>/dev/null
    OPENCODE_AUTH_CONTENT='should-not-leak'
    export OPENCODE_AUTH_CONTENT BENCH_SANDBOX="$sbx"
    PATH="$t/bin:$PATH" bench_invoke "$t/rep/repo" "$t/rep/run/request.txt" "$t/rep/run"
  ) || { echo "  bench_invoke returned non-zero"; return 1; }

  n=$(cat "$stub/invocations" 2>/dev/null)
  [ "$n" = 2 ] || { echo "  the stub ran $n times, expected 2 (version + run)"; return 1; }
  [ "$(cat "$stub/argv.1.1")" = "--version" ] || { echo "  invocation 1 is not --version"; return 1; }
  [ "$(cat "$stub/argv.2.1")" = "run" ] || { echo "  the run invocation does not start with the run subcommand"; return 1; }
  stub_arg_pair "$stub" 2 --agent antz-orchestrator || { echo "  no '--agent antz-orchestrator' pair in the run argv"; return 1; }
  stub_arg_pair "$stub" 2 --format json || { echo "  no '--format json' pair in the run argv"; return 1; }
  stub_arg_index "$stub" 2 --auto > /dev/null \
    || { echo "  no permission auto-approval flag (--auto) in the run argv"; return 1; }
  stub_arg_bytes_file "$stub" 2 "$t/rep/run/request.txt" \
    || { echo "  the request bytes never arrived verbatim as an argv word"; return 1; }
  stub_arg_absent "$stub" 2 --model || return 1
  stub_arg_absent "$stub" 2 -m || return 1
  expect_env_kv "$stub/env.2" \
    "HOME=$sbx/home" \
    "XDG_CONFIG_HOME=$sbx/home/.config" \
    "XDG_DATA_HOME=$sbx/home/.local/share" \
    || return 1
  expect_env_absent "$stub/env.2" OPENCODE_AUTH_CONTENT BENCH_SANDBOX BENCH_MODEL || return 1
  want_cwd=$(CDPATH= cd -- "$t/rep/repo" && pwd)
  [ "$(cat "$stub/cwd.2")" = "$want_cwd" ] \
    || { echo "  the client ran at [$(cat "$stub/cwd.2")], expected the fixture repo"; return 1; }

  run="$t/rep/run"
  cmp -s "$sbx/home/canned/events.jsonl" "$run/client.stdout" \
    || { echo "  client.stdout is not the stub's event stream"; return 1; }
  grep -q 'opencode stub noise' "$run/client.stderr" || { echo "  client.stderr lost the stub's stderr"; return 1; }
  [ "$(cat "$run/client.exit")" = 0 ] || { echo "  client.exit is not the stub's 0"; return 1; }
  [ "$(cat "$run/client.version")" = "1.18.31-stub" ] || { echo "  client.version was not recorded"; return 1; }
  return 0
}

# ---- clients-07 ----------------------------------------------------------------
# The OpenCode adapter's collect: run events plus the parent and child
# session exports fetched through the sandbox. Tokens, cost and tool_calls
# sum over the parent AND both children (a task part's state.metadata names
# each child); duration is the parent's time span; models_used lists the
# distinct exported models; session_id comes from the events; turns stay
# null. When one child's export is unavailable, the affected totals go null
# (never a silently partial sum) while subagent_delegations still counts the
# parent's task parts and models_used keeps the exports that succeeded.

test_clients_07() {
  t=$(new_tmp_dir)
  make_opencode_stub "$t/bin" || return 1
  bench_source_adapter opencode || return 1
  prep_repetition "$t/rep" || return 1
  sbx="$t/sbx"
  bench_sandbox_create "$sbx" > /dev/null || return 1
  plant_opencode_canned "$sbx/home" || return 1
  (
    BENCH_SANDBOX="$sbx"
    export BENCH_SANDBOX
    PATH="$t/bin:$PATH" bench_invoke "$t/rep/repo" "$t/rep/run/request.txt" "$t/rep/run"
  ) || { echo "  invoke failed"; return 1; }

  run="$t/rep/run"
  # collect fetches the exports THROUGH the sandbox, so the stub must be on
  # PATH here too (never the machine's real opencode)
  out=$(PATH="$t/bin:$PATH" BENCH_SANDBOX="$sbx" bench_collect "$run" "$t/rep/repo") \
    || { echo "  collect failed"; return 1; }
  assert_collect_kv "$out" \
    client_version=1.18.31-stub \
    client_duration_ms=4500 \
    tokens_input=1150 \
    tokens_output=240 \
    tokens_reasoning=45 \
    tokens_cache_read=311 \
    tokens_cache_write=22 \
    cost_usd=1.875 \
    turns=null \
    tool_calls=6 \
    subagent_delegations=2 \
    models_used=anthropic/stub-model-x,openai/stub-model-y \
    session_id=ses_parent_1 \
    || { echo "  full-coverage collect: $(printf '%s\n' "$out" | tr '\n' '|')"; return 1; }
  # the fetched exports are kept in the run dir for audit
  for e in export.parent.json export.ses_child_a.json export.ses_child_b.json; do
    [ -s "$run/$e" ] || { echo "  collect saved no $e in the run dir"; return 1; }
  done

  # child B's export becomes unavailable: summed totals go null, the
  # parent's own observations stand, partial models survive
  rm -f "$sbx/home/canned/export-ses_child_b.json"
  out=$(PATH="$t/bin:$PATH" BENCH_SANDBOX="$sbx" bench_collect "$run" "$t/rep/repo") || return 1
  assert_collect_kv "$out" \
    tokens_input=null \
    tokens_output=null \
    tokens_reasoning=null \
    tokens_cache_read=null \
    tokens_cache_write=null \
    cost_usd=null \
    tool_calls=null \
    subagent_delegations=2 \
    models_used=anthropic/stub-model-x \
    client_duration_ms=4500 \
    session_id=ses_parent_1 \
    || { echo "  partial-coverage collect: $(printf '%s\n' "$out" | tr '\n' '|')"; return 1; }
  [ ! -e "$run/export.ses_child_b.json" ] \
    || { echo "  a failed export left a partial artifact in the run dir"; return 1; }
  return 0
}

# ---- clients-08 ----------------------------------------------------------------
# Model pinning is forwarded and recorded on both sides: with a pinned
# model, both adapters pass their model flag with the value (and the stub's
# environment carries BENCH_MODEL), the record's model_pinned is that value,
# and models_used records what the client reports actually ran; with no pin,
# no model flag appears, the client never sees BENCH_MODEL, model_pinned is
# null, and a client that reports no models yields models_used null.

test_clients_08() {
  t=$(new_tmp_dir)

  # -- Claude, pinned: flag forwarded, env forwarded, record carries both --
  make_claude_stub "$t/bin" || return 1
  bench_source_adapter claude || return 1
  prep_repetition "$t/rep" || return 1
  sbx="$t/sbx"
  bench_sandbox_create "$sbx" > /dev/null || return 1
  plant_claude_canned "$sbx/home" || return 1
  (
    BENCH_SANDBOX="$sbx"
    BENCH_MODEL='stub/claude-pin'
    export BENCH_SANDBOX BENCH_MODEL
    PATH="$t/bin:$PATH" bench_invoke "$t/rep/repo" "$t/rep/run/request.txt" "$t/rep/run"
  ) || { echo "  pinned claude invoke failed"; return 1; }
  stub="$sbx/home/stub"
  stub_arg_pair "$stub" 2 --model stub/claude-pin \
    || { echo "  the pinned model never reached the claude stub's argv"; return 1; }
  expect_env_kv "$stub/env.2" "BENCH_MODEL=stub/claude-pin" || return 1
  out=$(bench_collect "$t/rep/run" "$t/rep/repo") || return 1
  collect=$(printf '%s\n' "$out")
  text=$(kv_set "$(base_kv 1)" client=claude run_id=clients08-r1 model_pinned=stub/claude-pin)
  text=$(kv_set "$text" models_used="$(collect_val "$collect" models_used)")
  printf '%s\n' "$text" | bench_emit_record "$t/records.jsonl" \
    || { echo "  the pinned record was refused by the schema"; return 1; }
  grep -qF '"model_pinned":"stub/claude-pin"' "$t/records.jsonl" \
    || { echo "  the record does not carry the pinned model"; return 1; }
  grep -qF '"models_used":"stub-model-one,stub-model-two"' "$t/records.jsonl" \
    || { echo "  the record does not carry the client-reported models"; return 1; }

  # -- Claude, unpinned, client reports NO models: no flag, no env, nulls --
  sbx2="$t/sbx2"
  bench_sandbox_create "$sbx2" > /dev/null || return 1
  plant_claude_canned "$sbx2/home" || return 1
  printf '%s\n' "$CLAUDE_CANNED_RESULT_NOMODELS" > "$sbx2/home/canned/result.json"
  rm -f "$sbx2/home/canned/transcript.jsonl"
  mkdir -p "$t/rep/run2"
  (
    unset BENCH_MODEL 2>/dev/null
    BENCH_SANDBOX="$sbx2"
    export BENCH_SANDBOX
    PATH="$t/bin:$PATH" bench_invoke "$t/rep/repo" "$t/rep/run/request.txt" "$t/rep/run2"
  ) || { echo "  unpinned claude invoke failed"; return 1; }
  stub2="$sbx2/home/stub"
  stub_arg_absent "$stub2" 2 --model || return 1
  stub_arg_absent "$stub2" 2 -m || return 1
  expect_env_absent "$stub2/env.2" BENCH_MODEL || return 1
  out=$(BENCH_SANDBOX="$sbx2" bench_collect "$t/rep/run2" "$t/rep/repo") || return 1
  assert_collect_kv "$out" models_used=null session_id=sess-abc-123 || return 1
  text=$(kv_set "$(base_kv 2)" models_used="$(collect_val "$out" models_used)")
  printf '%s\n' "$text" | bench_emit_record "$t/records.jsonl" || return 1
  sed -n '2p' "$t/records.jsonl" | grep -qF '"model_pinned":null' \
    || { echo "  an unpinned run must record model_pinned null"; return 1; }
  sed -n '2p' "$t/records.jsonl" | grep -qF '"models_used":null' \
    || { echo "  a client that reported no models must record models_used null"; return 1; }

  # -- OpenCode, pinned: flag forwarded too --
  sbx3="$t/sbx3"
  bench_sandbox_create "$sbx3" > /dev/null || return 1
  plant_opencode_canned "$sbx3/home" || return 1
  mkdir -p "$t/rep/run3"
  (
    BENCH_SANDBOX="$sbx3"
    BENCH_MODEL='anthropic/stub-pin'
    export BENCH_SANDBOX BENCH_MODEL
    PATH="$t/bin:$PATH" bench_invoke "$t/rep/repo" "$t/rep/run/request.txt" "$t/rep/run3"
  ) || { echo "  pinned opencode invoke failed"; return 1; }
  stub3="$sbx3/home/stub"
  stub_arg_pair "$stub3" 2 --model anthropic/stub-pin \
    || { echo "  the pinned model never reached the opencode stub's argv"; return 1; }
  expect_env_kv "$stub3/env.2" "BENCH_MODEL=anthropic/stub-pin" || return 1
  return 0
}

run_test "adapter-01: every adapter defines exactly the three contract functions, detect means usable (exit 0 + non-empty version) vs non-zero, and one adapter is sourced per run with unknown or contract-violating adapters refused" test_adapter_01
run_test "adapter-02: invoke runs the client at the fixture repo with the request file's prompt and the antz-orchestrator entry, non-interactively and in the foreground, leaving client.stdout / client.stderr / client.exit and writing nowhere else" test_adapter_02
run_test "adapter-03: collect prints exactly the 13 pinned telemetry keys as key=value lines in order, null where unavailable, and launches nothing itself (survives an empty PATH, names no client binary or network tool)" test_adapter_03
run_test "adapter-04: outcome 'approved' -- the dry-run script completes fast with no network or real binary, its artifacts classify as approved, and the record's outcome is approved" test_adapter_04_row approved
run_test "adapter-04: outcome 'rejected' -- the dry-run script completes fast with no network or real binary, its artifacts classify as rejected, and the record's outcome is rejected" test_adapter_04_row rejected
run_test "adapter-04: outcome 'blocked' -- the dry-run script completes fast with no network or real binary, its artifacts classify as blocked, and the record's outcome is blocked" test_adapter_04_row blocked
run_test "adapter-04: outcome 'open-question' -- the dry-run script completes fast with no network or real binary, its artifacts classify as open-question, and the record's outcome is open-question" test_adapter_04_row open-question
run_test "adapter-04: outcome 'error' -- the dry-run script completes fast with no network or real binary, its artifacts classify as error, and the record's outcome is error" test_adapter_04_row error
run_test "adapter-04: outcome 'timeout' -- killed at the deadline, the dry-run script's state classifies as timeout and the record's outcome is timeout" test_adapter_04_row timeout
run_test "adapter-05: the same scripted outcome across repetitions carries byte-identical flow artifacts and the same outcome and telemetry keys, with values scaling deterministically with the repetition number and a fixed non-empty client_version" test_adapter_05
run_test "adapter-06: the timeout script stays alive past the deadline until the harness kills it (marker left); the record is outcome timeout with non-null error_note, wall_clock_ms >= the deadline, and null client telemetry" test_adapter_06
run_test "adapter-07: the error script exits non-zero, writes no flow artifacts, emits no telemetry; the record is outcome error with null telemetry, a non-null exit_code, and a non-null error_note" test_adapter_07
run_test "adapter-08: every bench/*.sh parses under sh -n and invokes no non-POSIX interpreter or bashism -- awk, sed, grep, and standard utilities only" test_adapter_08
run_test "clients-01: one fresh per-repetition sandbox (HOME, XDG_CONFIG_HOME, XDG_DATA_HOME, CLAUDE_CONFIG_DIR under temp space, reuse refused) whose client sees only the minimal allowlist environment and writes nowhere outside the sandbox tree" test_clients_01
run_test "clients-02: the checkout under test renders into the sandbox through its own install.sh per client -- VERSION in the antz:generated markers, the orchestrator body on the sandbox libdir with no placeholder surviving, unknown clients and non-checkouts refused" test_clients_02
run_test "clients-03: real credentials are copied into the sandbox read-only with the originals byte- and permission-intact, and an absent credential is skipped -- never fabricated -- so the client's own failure classifies as error" test_clients_03
run_test "clients-04: the Claude adapter invokes the stub with -p and the verbatim request, --agent antz-orchestrator, --output-format json, permission auto-approval, --model only when pinned, at the fixture repo in the sandbox environment, leaving the pinned run-dir artifacts plus the recorded version and transcript" test_clients_04
run_test "clients-05: the Claude adapter's collect attributes result plus sidechain tokens and priced sidechain cost (unpriced sidechain usage nulls cost, never undercounts), takes turns/duration/session/models from the result, counts tool_use and delegations from the transcript, and stays result-only with nulls when no transcript exists" test_clients_05
run_test "clients-06: the OpenCode adapter invokes the stub with the run subcommand and the verbatim request, --agent antz-orchestrator, --format json, --auto, and the model flag only when pinned, at the fixture repo in the sandbox environment" test_clients_06
run_test "clients-07: the OpenCode adapter's collect sums tokens, cost and tool parts over the parent plus both named child exports (audited into the run dir), reads duration from the parent's time span, keeps distinct models and the parent's task-part delegations -- and nulls the affected totals rather than a partial sum when a child export is unavailable" test_clients_07
run_test "clients-08: a pinned model reaches both stubs as the model flag and BENCH_MODEL, lands in the record as model_pinned alongside the client-reported models_used, and an unpinned run passes no flag, hides BENCH_MODEL, records model_pinned null -- models_used null exactly when the client reported none" test_clients_08

# ---- runner test helpers ------------------------------------------------------
# Sub-spec 05 drives the runner CLI whole: a checkout staged into harness
# temp space (product files plus a copy of the current bench/ tree), invoked
# through ONE funnel helper with a fully controlled environment. The funnel
# (bench_cli) is the suite's only runner invocation point and always pins
# HOME and PATH via env -i, so the real host's client config, credentials,
# and binaries never reach the runner (runner-06 hermeticity).

# External tools a runner invocation execs (the bench tree's parsing aids,
# git for materialization, install.sh's render path, and the stubs' helpers)
# -- symlinked into a farm dir that carries NO client CLIs, so tests can
# hand the runner a PATH with the real binaries absent.
FARM_TOOLS="awk basename cat chmod cmp comm cp cut date diff dirname env file find git grep head ls mkdir mktemp paste printf rm sed sleep sh sort tail tee touch tr wc which"

make_bin_farm() {
  # $1 = dir to fill with tool symlinks; prints the dir for PATH use.
  d="$1"
  mkdir -p "$d" || return 1
  for tool in $FARM_TOOLS; do
    p=$(command -v "$tool" 2>/dev/null) || { echo "make_bin_farm: missing tool: $tool" >&2; return 1; }
    ln -s "$p" "$d/$tool" || return 1
  done
  printf '%s\n' "$d"
}

RUNNER_FARM=""
runner_farm() {
  # Sets RUNNER_FARM: the farm's content is fixed, so one build serves every
  # runner test (it is read-only after this). No command substitution at the
  # call sites — a subshell would lose the cached value.
  if [ -z "$RUNNER_FARM" ]; then
    RUNNER_FARM=$(make_bin_farm "$(new_tmp_dir)/farm") || return 1
  fi
}

RUNNER_STAGE_TEMPLATE=""
stage_runner_checkout() {
  # $1 = destination: the stage_checkout product files PLUS a copy of the
  # current bench/ tree, so the staged runner (and the sandbox render it
  # drives) exercises the working tree's current state inside temp space.
  # Built once as a template; each checkout is a hardlink clone (the
  # runner and its render only ever read the staged product files, and
  # materialization copies them onward, so nothing writes through a link).
  # srdest, not dest: stage_checkout reuses the global name dest.
  srdest="$1"
  if [ -z "$RUNNER_STAGE_TEMPLATE" ]; then
    RUNNER_STAGE_TEMPLATE=$(new_tmp_dir)/template
    stage_checkout "$RUNNER_STAGE_TEMPLATE" || return 1
    cp -R "$HARNESS_REPO/bench" "$RUNNER_STAGE_TEMPLATE/bench" || return 1
  fi
  cp -Rl -- "$RUNNER_STAGE_TEMPLATE" "$srdest" || return 1
  # bench/results is per-invocation state: start every clone clean
  rm -rf -- "$srdest/bench/results"
}

bench_cli() {
  # $1 = staged checkout, $2 = runner HOME, $3 = runner PATH. Leading
  # KEY=VALUE arguments (single words, no spaces) are appended to the
  # pinned environment -- the clientconfig group relocates the runner's
  # XDG roots this way; every other argument is a runner CLI argument.
  # The suite's single runner funnel: env -i carries ONLY HOME, PATH, and
  # those leading assignments, so the real host's client config,
  # credentials, and binaries never reach the runner (runner-06
  # hermeticity). Returns the runner's exit status; stdout/stderr pass
  # through to the caller's redirections.
  co="$1"; h="$2"; p="$3"; shift 3
  _bc_env=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      [A-Za-z_]*=*) _bc_env="${_bc_env:+$_bc_env }$1"; shift ;;
      *) break ;;
    esac
  done
  # shellcheck disable=SC2086
  env -i HOME="$h" PATH="$p" $_bc_env sh "$co/bench/antz-bench.sh" "$@" < /dev/null
}

rec_val() {
  # $1 = JSONL file, $2 = line number, $3 = field name -- the field's value
  # on that record line with any surrounding quotes stripped. Use for
  # comma-free values (run_id, outcome, client, repetition, model_pinned...).
  sed -n "${2}p" "$1" | grep -o "\"$3\"[^,}]*" | head -n 1 \
    | sed -e "s/^\"$3\"://" -e 's/^"//' -e 's/"$//'
}

rec_count() {
  # $1 = JSONL file (must exist): its record line count.
  wc -l < "$1" | tr -d ' '
}

# Runner-test client stubs: SELF-CONTAINED replayers. Unlike the clients-
# section stubs (which replay files planted under the sandbox HOME), the
# runner creates its sandboxes itself, so these stubs carry their canned
# artifacts beside themselves (dirname "$0"), and every invocation is
# answerable: --version for detect, canned telemetry for the run, canned
# exports for collect. An optional tripwire marker records (as a file) the
# fact that the client was invoked at all -- report mode must never touch
# it, and the marker's path needs no knowledge of the runner's temp layout.
make_runner_claude_stub() {
  # $1 = bin dir, $2 = optional tripwire marker file.
  d="$1"
  mkdir -p "$d/claude-stub.d" || return 1
  printf '%s\n' "$CLAUDE_CANNED_RESULT" > "$d/claude-stub.d/result.json"
  cat > "$d/claude" <<EOS || return 1
#!/bin/sh
${2:+printf 'claude launched\n' > '$2' 2>/dev/null}
if [ "\${1:-}" = "--version" ]; then
  printf '%s\n' '9.9.9-stub'
  exit 0
fi
cat "\$(dirname "\$0")/claude-stub.d/result.json"
exit 0
EOS
  chmod +x "$d/claude"
}

make_runner_opencode_stub() {
  # $1 = bin dir, $2 = optional tripwire marker file.
  d="$1"
  mkdir -p "$d/opencode-stub.d" || return 1
  printf '%s\n' "$OC_CANNED_EVENTS" > "$d/opencode-stub.d/events.jsonl"
  printf '%s\n' "$OC_CANNED_PARENT" > "$d/opencode-stub.d/export-ses_parent_1.json"
  printf '%s\n' "$OC_CANNED_CHILD_A" > "$d/opencode-stub.d/export-ses_child_a.json"
  printf '%s\n' "$OC_CANNED_CHILD_B" > "$d/opencode-stub.d/export-ses_child_b.json"
  cat > "$d/opencode" <<EOS || return 1
#!/bin/sh
${2:+printf 'opencode launched\n' > '$2' 2>/dev/null}
sd="\$(dirname "\$0")/opencode-stub.d"
case "\${1:-}" in
  --version)
    printf '%s\n' '1.18.31-stub'
    exit 0
    ;;
  export)
    if [ -f "\$sd/export-\$2.json" ]; then
      cat "\$sd/export-\$2.json"
      exit 0
    fi
    printf 'no such session: %s\n' "\$2" 1>&2
    exit 1
    ;;
esac
cat "\$sd/events.jsonl"
exit 0
EOS
  chmod +x "$d/opencode"
}

make_recording_opencode_stub() {
  # $1 = bin dir: the clientconfig group's observer. It answers the adapter
  # contract exactly like make_runner_opencode_stub (--version, canned run
  # events, canned exports), and on EACH run invocation it records beside
  # itself what the client sees inside the sandbox: the credential at the
  # sandbox's data-dir location, the credential at the sandbox's config-dir
  # location (the pre-fix source path, so a decoy there is observable), and
  # the provider config at the sandbox's config-dir location -- existence,
  # mode and writability in oc-record.d/seen.N, plus the bytes seen in
  # oc-record.d/captured.N.<label> (written exactly when the file existed).
  # The sandbox dies with the repetition; the recording lives outside it.
  d="$1"
  mkdir -p "$d/oc-record.d" || return 1
  printf '%s\n' "$OC_CANNED_EVENTS" > "$d/oc-record.d/events.jsonl" || return 1
  printf '%s\n' "$OC_CANNED_PARENT" > "$d/oc-record.d/export-ses_parent_1.json" || return 1
  printf '%s\n' "$OC_CANNED_CHILD_A" > "$d/oc-record.d/export-ses_child_a.json" || return 1
  printf '%s\n' "$OC_CANNED_CHILD_B" > "$d/oc-record.d/export-ses_child_b.json" || return 1
  cat > "$d/opencode" <<EOS || return 1
#!/bin/sh
sd="\$(dirname "\$0")/oc-record.d"
case "\${1:-}" in
  --version)
    printf '%s\n' '1.18.31-stub'
    exit 0
    ;;
  export)
    if [ -f "\$sd/export-\$2.json" ]; then
      cat "\$sd/export-\$2.json"
      exit 0
    fi
    printf 'no such session: %s\n' "\$2" 1>&2
    exit 1
    ;;
esac
# The run invocation is the only one reaching here: record the sandbox's
# client files under the environment the sandbox relocated.
n=\$(cat "\$sd/runs" 2>/dev/null)
n=\${n:-0}
n=\$((n + 1))
printf '%s\n' "\$n" > "\$sd/runs"
: > "\$sd/seen.\$n"
seen() {
  # \$1 = label, \$2 = path to observe.
  if [ -f "\$2" ]; then
    printf '%s=exists\n' "\$1" >> "\$sd/seen.\$n"
    mode=\$(ls -l "\$2" | awk '{print \$1}')
    printf '%s.mode=%s\n' "\$1" "\$mode" >> "\$sd/seen.\$n"
    if [ -w "\$2" ]; then
      printf '%s.writable=yes\n' "\$1" >> "\$sd/seen.\$n"
    else
      printf '%s.writable=no\n' "\$1" >> "\$sd/seen.\$n"
    fi
    cp "\$2" "\$sd/captured.\$n.\$1" || exit 3
  else
    printf '%s=absent\n' "\$1" >> "\$sd/seen.\$n"
  fi
}
seen cred_data "\$XDG_DATA_HOME/opencode/auth.json"
seen cred_config "\$XDG_CONFIG_HOME/opencode/auth.json"
seen provider_config "\$XDG_CONFIG_HOME/opencode/opencode.json"
cat "\$sd/events.jsonl"
exit 0
EOS
  chmod +x "$d/opencode"
}

# ---- runner-01 ----------------------------------------------------------------
# The CLI surface is documented on -h and refuses unknown flags: usage
# documents both modes, every flag, their defaults, and the exit contract
# on stdout with exit 0 (-h and --help alike); an unknown flag (or a bad
# flag value) prints the usage to stderr, exits non-zero, and writes
# nothing to stdout.

test_runner_01_help_documents_surface() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  # the farm carries no client CLIs: usage must not need any (no detection)
  [ ! -e "$farm/claude" ] && [ ! -e "$farm/opencode" ] || { echo "  the tool farm carries a client CLI"; return 1; }
  bench_cli "$t/co" "$t/home" "$farm" -h > "$t/h.out" 2> "$t/h.err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  -h exited $rc, expected 0"; return 1; }
  [ -s "$t/h.out" ] || { echo "  -h printed no usage to stdout"; return 1; }
  [ ! -s "$t/h.err" ] || { echo "  -h wrote to stderr:"; sed 's/^/    /' "$t/h.err"; return 1; }
  # both modes, every flag, defaults, and the exit contract are documented
  for frag in 'Usage' 'report' '--client' '--repetitions' '--model' '--timeout' '--baseline' '--jsonl' '--dryrun-outcome' 'claude' 'opencode' 'dryrun' '1800' 'default: 1' 'bench/results/bench-' 'UTC timestamp' 'every repetition produced a record' 'harness-internal'; do
    require "$t/h.out" "$frag" || { echo "    (in the -h usage text)"; return 1; }
  done
  # --help: the same text, the same exit
  bench_cli "$t/co" "$t/home" "$farm" --help > "$t/help.out" 2> "$t/help.err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  --help exited $rc, expected 0"; return 1; }
  cmp -s "$t/h.out" "$t/help.out" || { echo "  --help printed a different text than -h"; return 1; }
  return 0
}

test_runner_01_refuses_bad_arguments() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  for bad in '--frobnicate' '--repetitions x' '--repetitions 0' '--timeout abc' '--timeout 0' '--dryrun-outcome sideways' '--client' '--jsonl' 'run' 'report' 'report --frobnicate' 'report --client dryrun --jsonl'; do
    # shellcheck disable=SC2086
    bench_cli "$t/co" "$t/home" "$farm" $bad > "$t/out" 2> "$t/err"
    rc=$?
    [ "$rc" -ne 0 ] || { echo "  accepted bad arguments [$bad]"; return 1; }
    [ ! -s "$t/out" ] || { echo "  [$bad] wrote to stdout:"; sed 's/^/    /' "$t/out"; return 1; }
    require "$t/err" 'Usage' || { echo "    (after bad arguments [$bad], on stderr)"; return 1; }
  done
  return 0
}

run_test "runner-01: -h and --help print the same usage to stdout with exit 0, documenting both modes, every flag, their defaults, and the exit contract" test_runner_01_help_documents_surface
run_test "runner-01: an unknown flag, a missing or invalid flag value, or a stray positional prints the usage to stderr, exits non-zero, and writes nothing to stdout" test_runner_01_refuses_bad_arguments

# ---- runner-02 ----------------------------------------------------------------
# Client selection mirrors install.sh's detection predicate (CLI on PATH or
# the global config directory), evaluated against the runner process's own
# environment; --client forces exactly one client past detection; the
# dry-run client is selectable only explicitly; nothing detected is a loud
# refusal naming --client.

test_runner_02_both_detected() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  make_runner_claude_stub "$t/bin" || return 1
  make_runner_opencode_stub "$t/bin" || return 1
  mkdir -p "$t/hosthome"   # config-dir detection deliberately NOT triggered
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" --repetitions 2 --jsonl "$t/res.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the both-detected run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/res.jsonl")" = 4 ] \
    || { echo "  two detected clients x 2 repetitions must yield 4 records, got $(rec_count "$t/res.jsonl")"; return 1; }
  i=1
  while [ "$i" -le 4 ]; do
    [ "$(rec_val "$t/res.jsonl" "$i" client)" != dryrun ] \
      || { echo "  record $i: the dry-run client was auto-selected"; return 1; }
    i=$((i + 1))
  done
  # every detected client ran the FULL repetition count (claude first --
  # install.sh's predicate order)
  [ "$(rec_val "$t/res.jsonl" 1 client)" = claude ] || { echo "  record 1 is not claude"; return 1; }
  [ "$(rec_val "$t/res.jsonl" 2 client)" = claude ] && [ "$(rec_val "$t/res.jsonl" 2 repetition)" = 2 ] \
    || { echo "  record 2 is not claude repetition 2"; return 1; }
  [ "$(rec_val "$t/res.jsonl" 3 client)" = opencode ] && [ "$(rec_val "$t/res.jsonl" 3 repetition)" = 1 ] \
    || { echo "  record 3 is not opencode repetition 1"; return 1; }
  [ "$(rec_val "$t/res.jsonl" 4 client)" = opencode ] && [ "$(rec_val "$t/res.jsonl" 4 repetition)" = 2 ] \
    || { echo "  record 4 is not opencode repetition 2"; return 1; }
  # the records are real measurements of the stub telemetry
  [ "$(rec_val "$t/res.jsonl" 1 tokens_input)" = 1000 ] \
    || { echo "  the claude record's telemetry did not come from the run"; return 1; }
  return 0
}

test_runner_02_forcing_bypasses_detection() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  mkdir -p "$t/emptyhome"

  # on a host where NOTHING is detected, --client dryrun still runs (the
  # forcing contract: even where detection would not select it)
  bench_cli "$t/co" "$t/emptyhome" "$farm" --client dryrun --jsonl "$t/a.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  forced dryrun on a nothing-detected host exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/a.jsonl")" = 1 ] || { echo "  forced dryrun did not run"; return 1; }
  [ "$(rec_val "$t/a.jsonl" 1 client)" = dryrun ] || { echo "  forced run recorded the wrong client"; return 1; }

  # on a both-detected host, --client runs EXACTLY that client
  make_runner_claude_stub "$t/bin" || return 1
  make_runner_opencode_stub "$t/bin" || return 1
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" --client dryrun --jsonl "$t/b.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  forced dryrun on a both-detected host exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/b.jsonl")" = 1 ] \
    && [ "$(rec_val "$t/b.jsonl" 1 client)" = dryrun ] \
    || { echo "  --client dryrun ran more than the dry-run client"; return 1; }
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" --client claude --jsonl "$t/c.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  forced claude exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/c.jsonl")" = 1 ] || { echo "  forced claude did not run"; return 1; }
  [ "$(rec_val "$t/c.jsonl" 1 client)" = claude ] \
    || { echo "  --client claude also ran another client"; return 1; }
  return 0
}

test_runner_02_nothing_detected_refuses_loudly() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  mkdir -p "$t/emptyhome"
  bench_cli "$t/co" "$t/emptyhome" "$farm" --jsonl "$t/none.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -ne 0 ] || { echo "  nothing-detected was accepted"; return 1; }
  require "$t/err" '--client' || { echo "    (the refusal must name --client as the escape hatch)"; return 1; }
  [ -s "$t/err" ] || { echo "  the refusal was not loud (empty stderr)"; return 1; }
  [ ! -e "$t/none.jsonl" ] || { echo "  the refusal wrote records"; return 1; }
  return 0
}

test_runner_02_detected_but_unusable_client_is_skipped() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  make_runner_opencode_stub "$t/bin" || return 1
  # Claude is DETECTED by the predicate (~/.claude exists) but its adapter
  # cannot detect as usable (no claude anywhere on the PATH); OpenCode is
  # detected via its CLI stub and is fully usable.
  mkdir -p "$t/hosthome/.claude"
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" --repetitions 1 --jsonl "$t/res.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the partially-usable host run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/res.jsonl")" = 1 ] \
    || { echo "  expected opencode's single record only, got $(rec_count "$t/res.jsonl")"; return 1; }
  [ "$(rec_val "$t/res.jsonl" 1 client)" = opencode ] \
    || { echo "  the unusable claude client produced a record"; return 1; }
  require "$t/err" 'claude' || { echo "    (the skip of the unusable client must be visible on stderr)"; return 1; }
  return 0
}

run_test "runner-02: with no --client, every client detected by install.sh's predicate runs the full repetition count (claude then opencode) and the dry-run client runs for none of them" test_runner_02_both_detected
run_test "runner-02: --client forces exactly that client -- dryrun runs on a host where nothing is detected, and on a both-detected host only the named client runs" test_runner_02_forcing_bypasses_detection
run_test "runner-02: with no --client and nothing detected, the runner refuses loudly naming --client, exits non-zero, and writes no records" test_runner_02_nothing_detected_refuses_loudly
run_test "runner-02: a client the predicate detects but whose adapter does not detect as usable is skipped with a visible warning while the usable detected client still runs its full repetitions" test_runner_02_detected_but_unusable_client_is_skipped

# ---- runner-03 ----------------------------------------------------------------
# N sequential repetitions, each fully isolated, errors never abort the
# loop: one record appended per repetition in run order with "repetition"
# counting from 1; a freshly materialized fixture repo and a freshly
# prepared sandbox every time; a repetition that errors or times out still
# appends its record and the remaining repetitions still run.

test_runner_03_one_record_per_fresh_repetition() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --repetitions 3 --jsonl "$t/res.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the 3-repetition dry-run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ -f "$t/res.jsonl" ] || { echo "  no results JSONL at the --jsonl path"; return 1; }
  [ "$(rec_count "$t/res.jsonl")" = 3 ] \
    || { echo "  expected exactly 3 records, found $(rec_count "$t/res.jsonl"):"; cat "$t/res.jsonl"; return 1; }
  rep=1
  while [ "$rep" -le 3 ]; do
    [ "$(rec_val "$t/res.jsonl" "$rep" client)" = dryrun ] \
      || { echo "  record $rep: client must be dryrun"; return 1; }
    [ "$(rec_val "$t/res.jsonl" "$rep" repetition)" = "$rep" ] \
      || { echo "  record $rep: repetition must count from 1, in run order"; return 1; }
    [ "$(rec_val "$t/res.jsonl" "$rep" outcome)" = approved ] \
      || { echo "  record $rep: outcome must be approved"; return 1; }
    # the dry-run client's telemetry scales with the repetition number it
    # receives, so this pins per-repetition state AND the run order at once
    [ "$(rec_val "$t/res.jsonl" "$rep" tokens_input)" = $((100 * rep)) ] \
      || { echo "  record $rep: tokens_input must scale with the repetition (100 * repetition)"; return 1; }
    rep=$((rep + 1))
  done
  # a freshly materialized fixture repo per repetition: the mock client
  # prints its cwd, the three cwds are three distinct paths (nothing is
  # shared), and each repetition measured its OWN approved-flow state --
  # outcome approved (a directory under spdd/archive/ in that repo) with
  # exactly one sub-spec declared and receipted. The runner releases the
  # repo when the repetition ends; the run dir keeps the audit trail.
  cwds=$(find "$t/co/bench/results/runs" -name client.stdout -exec sed -n 's/^dryrun client: cwd=//p' {} \; | LC_ALL=C sort)
  n=$(printf '%s\n' "$cwds" | grep -c .)
  [ "$n" = 3 ] || { echo "  repetitions did not run in distinct fixture repos (saw $n distinct cwds of 3)"; return 1; }
  i=1
  while [ "$i" -le 3 ]; do
    [ "$(rec_val "$t/res.jsonl" "$i" subspecs_declared)" = 1 ] \
      && [ "$(rec_val "$t/res.jsonl" "$i" subspecs_receipted)" = 1 ] \
      || { echo "  record $i: the repetition's own repo must show one declared and one receipted sub-spec"; return 1; }
    i=$((i + 1))
  done
  return 0
}

run_test "runner-03: three forced dry-run repetitions append exactly one record each, in run order with repetition counting from 1, each in a freshly materialized fixture repo (distinct cwds, per-repetition flow artifacts) with repetition-scaled telemetry" test_runner_03_one_record_per_fresh_repetition

test_runner_03_error_and_timeout_reps_do_not_abort_the_loop() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM

  # a scripted error repetition: it appends its record and the NEXT
  # repetition still runs (repetition 2 exists)
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --repetitions 2 \
    --dryrun-outcome error --jsonl "$t/err.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the error-scripted run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/err.jsonl")" = 2 ] \
    || { echo "  an erroring repetition aborted the loop (records: $(rec_count "$t/err.jsonl") of 2)"; return 1; }
  i=1
  while [ "$i" -le 2 ]; do
    [ "$(rec_val "$t/err.jsonl" "$i" outcome)" = error ] \
      || { echo "  record $i: expected outcome error"; return 1; }
    [ "$(rec_val "$t/err.jsonl" "$i" repetition)" = "$i" ] \
      || { echo "  record $i: repetition out of order"; return 1; }
    i=$((i + 1))
  done

  # a deadline kill is likewise just a measured repetition: every
  # repetition appends its timeout record and the loop runs to N
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --repetitions 2 \
    --dryrun-outcome timeout --timeout 1 --jsonl "$t/to.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the timeout-scripted run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/to.jsonl")" = 2 ] \
    || { echo "  a timed-out repetition aborted the loop (records: $(rec_count "$t/to.jsonl") of 2)"; return 1; }
  for i in 1 2; do
    [ "$(rec_val "$t/to.jsonl" "$i" outcome)" = timeout ] \
      || { echo "  record $i: expected outcome timeout"; return 1; }
    [ "$(rec_val "$t/to.jsonl" "$i" wall_clock_ms)" -ge 1000 ] \
      || { echo "  record $i: wall clock must at least reach the 1s deadline the harness enforced"
      return 1; }
  done
  return 0
}

run_test "runner-03: a repetition that errors or that the deadline kills still appends its record and the remaining repetitions run (error and timeout loops both complete all N)" test_runner_03_error_and_timeout_reps_do_not_abort_the_loop

# ---- runner-05 ----------------------------------------------------------------
# Every repetition leaves an auditable run dir: under the results area, at
# least the recorded request copy, the raw client stdout / stderr / exit
# artifacts, the collect keys, and the timeout marker when the deadline
# fired; disjoint across repetitions and invocations, each record
# identifying its repetition (run_id maps to the repetition's run dir).

test_runner_05_run_dirs_are_auditable() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM

  # a two-repetition approved run: a disjoint, fully audited run dir per
  # repetition, each named by its record
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --repetitions 2 \
    --jsonl "$t/ok.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the dry-run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  rid=$(rec_val "$t/ok.jsonl" 1 run_id)
  [ -n "$rid" ] || { echo "  the record carries no run_id"; return 1; }
  stamp=${rid%-dryrun-r*}
  [ "$stamp" != "$rid" ] || { echo "  run_id [$rid] does not name its client and repetition"; return 1; }
  for n in 1 2; do
    d="$t/co/bench/results/runs/$stamp/dryrun-r$n"
    [ -d "$d" ] || { echo "  no run dir for repetition $n: $d"; return 1; }
    [ -f "$d/request.txt" ] || { echo "  run dir r$n lacks request.txt"; return 1; }
    cmp -s "$d/request.txt" "$t/co/bench/fixture/scenario.txt" \
      || { echo "  run dir r$n: request.txt is not the recorded fixture request bytes"; return 1; }
    for art in client.stdout client.stderr client.exit collect.kv; do
      [ -f "$d/$art" ] || { echo "  run dir r$n lacks $art"; return 1; }
    done
    grep -Eq '^[0-9]+$' "$d/client.exit" || { echo "  run dir r$n: client.exit is not an integer"; return 1; }
    [ ! -e "$d/client.timeout" ] \
      || { echo "  run dir r$n carries the timeout marker although no deadline fired"; return 1; }
    [ "$(wc -l < "$d/collect.kv" | tr -d ' ')" = 13 ] \
      || { echo "  run dir r$n: collect.kv does not hold the 13 collect keys"; return 1; }
    # each record identifies its repetition (and thereby its own run dir)
    [ "$(rec_val "$t/ok.jsonl" "$n" repetition)" = "$n" ] \
      && [ "$(rec_val "$t/ok.jsonl" "$n" run_id)" = "$stamp-dryrun-r$n" ] \
      || { echo "  record $n does not identify this run dir's repetition"; return 1; }
    # the disjointness witness: each repetition's client ran in its own cwd
    grep -q "^dryrun client: cwd=" "$d/client.stdout" \
      || { echo "  run dir r$n: client.stdout is not this repetition's raw output"; return 1; }
  done
  cwds=$(find "$t/co/bench/results/runs" -name client.stdout -exec sed -n 's/^dryrun client: cwd=//p' {} \; | LC_ALL=C sort -u | grep -c .)
  [ "$cwds" = 2 ] || { echo "  the two repetitions' run dirs do not hold two distinct client worlds"; return 1; }

  # the deadline case: the marker appears exactly because the deadline
  # fired, beside every other artifact of the repetition
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --dryrun-outcome timeout \
    --timeout 1 --jsonl "$t/to.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the timeout run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  rid=$(rec_val "$t/to.jsonl" 1 run_id)
  d="$t/co/bench/results/runs/${rid%-dryrun-r*}/dryrun-r1"
  [ -d "$d" ] || { echo "  no run dir for the timed-out repetition: $d"; return 1; }
  for art in request.txt client.stdout client.stderr client.exit collect.kv; do
    [ -f "$d/$art" ] || { echo "  timed-out run dir lacks $art"; return 1; }
  done
  [ -f "$d/client.timeout" ] \
    || { echo "  the timed-out run dir lacks the timeout marker"; return 1; }
  [ "$(wc -l < "$d/collect.kv" | tr -d ' ')" = 13 ] \
    || { echo "  the timed-out collect.kv must still hold the 13 pinned keys (nulls)"; return 1; }

  # a run whose deadline never fires must NOT carry the marker
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --dryrun-outcome error \
    --jsonl "$t/e.jsonl" > "$t/out" 2> "$t/err" \
    || { echo "  the error run exited non-zero:"; sed 's/^/    /' "$t/err"; return 1; }
  rid=$(rec_val "$t/e.jsonl" 1 run_id)
  d="$t/co/bench/results/runs/${rid%-dryrun-r*}/dryrun-r1"
  [ -d "$d" ] || { echo "  no run dir for the error repetition: $d"; return 1; }
  [ ! -e "$d/client.timeout" ] \
    || { echo "  the timeout marker exists although the deadline never fired"; return 1; }
  [ "$(cat "$d/client.exit")" = 3 ] \
    || { echo "  client.exit does not carry the client's own exit code"; return 1; }
  return 0
}

test_runner_05_run_dirs_disjoint_across_invocations() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun > "$t/out1" 2> "$t/err1" \
    || { echo "  first invocation failed:"; sed 's/^/    /' "$t/err1"; return 1; }
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun > "$t/out2" 2> "$t/err2" \
    || { echo "  second invocation failed:"; sed 's/^/    /' "$t/err2"; return 1; }
  # two fresh default JSONLs, never each other
  nfiles=$(find "$t/co/bench/results" -maxdepth 1 -type f -name 'bench-*.jsonl' | wc -l | tr -d ' ')
  [ "$nfiles" = 2 ] || { echo "  expected 2 default result files, found $nfiles"; return 1; }
  # disjoint run dirs: one stamp dir per invocation
  ndirs=$(find "$t/co/bench/results/runs" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$ndirs" = 2 ] || { echo "  expected 2 disjoint run-stamp dirs, found $ndirs"; return 1; }
  rid1=$(rec_val "$(find "$t/co/bench/results" -maxdepth 1 -name 'bench-*.jsonl' | LC_ALL=C sort | head -n 1)" 1 run_id)
  rid2=$(rec_val "$(find "$t/co/bench/results" -maxdepth 1 -name 'bench-*.jsonl' | LC_ALL=C sort | tail -n 1)" 1 run_id)
  [ "$rid1" != "$rid2" ] || { echo "  both invocations wrote the same run_id"; return 1; }
  return 0
}

run_test "runner-05: each repetition leaves a run dir under the results area holding request.txt (the fixture bytes), client.stdout / client.stderr / client.exit, the 13 collect keys, and the timeout marker exactly when the deadline fired, with each record's run_id identifying its repetition's dir" test_runner_05_run_dirs_are_auditable
run_test "runner-05: run dirs are disjoint across repetitions and across separate invocations (fresh result file and fresh run-stamp dir per invocation)" test_runner_05_run_dirs_disjoint_across_invocations

# ---- runner-04 ----------------------------------------------------------------
# Outputs and the exit contract: records written to the --jsonl path
# defaulting to a fresh bench/results/bench-<UTC timestamp>.jsonl (directory
# created on demand); the aggregate report printed to stdout at the end of
# the run; exit 0 exactly when every repetition produced a record (outcome
# error/timeout runs are measurements -- they still exit 0); harness-internal
# failures exit non-zero before any record is written; and the standalone
# report mode launches no client and writes nothing.

test_runner_04_default_jsonl_and_end_report() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  rm -rf "$t/co/bench/results"   # the results directory is created on demand
  runner_farm || return 1; farm=$RUNNER_FARM
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --repetitions 2 \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the default-output run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ -d "$t/co/bench/results" ] || { echo "  the results directory was not created on demand"; return 1; }
  nfiles=$(find "$t/co/bench/results" -maxdepth 1 -type f | wc -l | tr -d ' ')
  [ "$nfiles" = 1 ] || { echo "  expected exactly one default output file, found $nfiles"; return 1; }
  f=$(find "$t/co/bench/results" -maxdepth 1 -type f | head -n 1)
  base=$(basename -- "$f")
  printf '%s\n' "$base" | grep -Eq '^bench-[0-9]{8}T[0-9]{6}([0-9]{3})?Z(-[0-9]+)?\.jsonl$' \
    || { echo "  the default results file is not bench-<UTC timestamp>.jsonl: $base"; return 1; }
  [ "$(rec_count "$f")" = 2 ] || { echo "  the default JSONL does not hold the run's records"; return 1; }
  # the aggregate report prints to stdout at the end of the run: it names
  # the client group and reads as a report -- the 06-report sub-spec owns
  # its exact statistical shape, so only its presence and subject pin here
  [ -s "$t/out" ] || { echo "  nothing printed to stdout at the end of the run"; return 1; }
  grep -qi 'report' "$t/out" || { echo "  stdout does not carry an aggregate report:"; sed 's/^/    /' "$t/out"; return 1; }
  grep -q 'dryrun' "$t/out" || { echo "  the report names no client:"; sed 's/^/    /' "$t/out"; return 1; }
  grep -q '"run_id"' "$t/out" \
    && { echo "  records printed to stdout instead of the JSONL"; return 1; }
  # --model records the pin in every produced record (the forwarding half
  # is pinned by clients-08)
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --model stub/pin \
    --jsonl "$t/pin.jsonl" > "$t/out" 2> "$t/err" \
    || { echo "  the pinned run failed:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_val "$t/pin.jsonl" 1 model_pinned)" = stub/pin ] \
    || { echo "  --model did not reach the record as model_pinned"; return 1; }
  [ "$(rec_val "$t/pin.jsonl" 1 client)" = dryrun ] || return 1
  return 0
}

test_runner_04_outcomes_are_data_not_failures() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --dryrun-outcome error \
    --jsonl "$t/e.jsonl" > "$t/out" 2> "$t/err"
  [ $? -eq 0 ] || { echo "  a run whose only outcome was error exited non-zero"; return 1; }
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --dryrun-outcome timeout \
    --timeout 1 --jsonl "$t/t.jsonl" > "$t/out" 2> "$t/err"
  [ $? -eq 0 ] || { echo "  a run whose only outcome was timeout exited non-zero"; return 1; }
  [ "$(rec_val "$t/t.jsonl" 1 outcome)" = timeout ] || return 1
  return 0
}

test_runner_04_internal_failures_exit_before_records() {
  t=$(new_tmp_dir)
  runner_farm || return 1; farm=$RUNNER_FARM
  mkdir -p "$t/emptyhome"

  # (a) a FORCED client whose adapter does not detect as usable (no claude
  # anywhere on this PATH) -- refused before any record
  stage_runner_checkout "$t/co1" || return 1
  bench_cli "$t/co1" "$t/emptyhome" "$farm" --client claude --repetitions 2 \
    --jsonl "$t/a.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -ne 0 ] || { echo "  a forced unusable client was accepted"; return 1; }
  [ ! -s "$t/a.jsonl" ] || { echo "  the unusable-forced run wrote records"; return 1; }
  require "$t/err" 'claude' || { echo "    (the refusal should name the client)"; return 1; }

  # (b) a forced client with no adapter at all
  bench_cli "$t/co1" "$t/emptyhome" "$farm" --client gemini --jsonl "$t/b.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -ne 0 ] || { echo "  an adapter-less forced client was accepted"; return 1; }
  [ ! -s "$t/b.jsonl" ] || { echo "  the no-adapter run wrote records"; return 1; }

  # (c) an unmaterializable fixture (the staged checkout's fixture repo is gone)
  stage_runner_checkout "$t/co2" || return 1
  rm -rf "$t/co2/bench/fixture/repo"
  bench_cli "$t/co2" "$t/emptyhome" "$farm" --client dryrun --repetitions 2 \
    --jsonl "$t/c.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -ne 0 ] || { echo "  an unmaterializable fixture was accepted"; return 1; }
  [ ! -s "$t/c.jsonl" ] || { echo "  the broken-fixture run wrote records"; return 1; }

  # (d) an unwritable output path
  stage_runner_checkout "$t/co3" || return 1
  mkdir -p "$t/ro/x" && chmod 500 "$t/ro"
  bench_cli "$t/co3" "$t/emptyhome" "$farm" --client dryrun --jsonl "$t/ro/x.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  chmod 700 "$t/ro"   # so the harness cleanup can always remove the tree
  [ "$rc" -ne 0 ] || { echo "  an unwritable results path was accepted"; return 1; }
  [ ! -s "$t/out" ] || { echo "  a failed invocation printed a report:"; sed 's/^/    /' "$t/out"; return 1; }
  return 0
}

test_runner_04_report_mode_launches_no_client_and_writes_nothing() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  # a conforming JSONL to report, produced by a real (dry-run) invocation
  bench_cli "$t/co" "$t/home" "$farm" --client dryrun --repetitions 2 \
    --jsonl "$t/res.jsonl" > "$t/out" 2> "$t/err" \
    || { echo "  the seeding run failed:"; sed 's/^/    /' "$t/err"; return 1; }
  cp "$t/res.jsonl" "$t/res.before"
  cp "$t/res.jsonl" "$t/base.jsonl"
  cp "$t/base.jsonl" "$t/base.before"

  # the host looks fully usable for BOTH real clients -- tripwire stubs
  # record any launch attempt on their first byte of contact
  mkdir -p "$t/hosthome/.claude" "$t/hosthome/.config/opencode"
  make_runner_claude_stub "$t/bin" "$t/claude-launched" || return 1
  make_runner_opencode_stub "$t/bin" "$t/opencode-launched" || return 1
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" report --jsonl "$t/res.jsonl" \
    --baseline "$t/base.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  report mode exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ -s "$t/out" ] || { echo "  report mode printed no report to stdout"; return 1; }
  grep -qi 'report' "$t/out" || { echo "  stdout is not a report:"; sed 's/^/    /' "$t/out"; return 1; }
  grep -q 'dryrun' "$t/out" || { echo "  the report names no client"; return 1; }
  [ ! -e "$t/claude-launched" ] && [ ! -e "$t/opencode-launched" ] \
    || { echo "  report mode launched a client"; return 1; }
  cmp -s "$t/res.before" "$t/res.jsonl" || { echo "  report mode wrote to its --jsonl input"; return 1; }
  cmp -s "$t/base.before" "$t/base.jsonl" || { echo "  report mode wrote to its --baseline input"; return 1; }
  return 0
}

run_test "runner-04: with no --jsonl the records land in a fresh bench/results/bench-<UTC timestamp>.jsonl (directory created on demand), the aggregate report prints to stdout at the end of the run, and --model records the pin in every record" test_runner_04_default_jsonl_and_end_report
run_test "runner-04: a run whose repetitions all ended in outcome error or timeout still exits 0 -- outcomes are measurements, not failures" test_runner_04_outcomes_are_data_not_failures
run_test "runner-04: harness-internal failures (forced client not usable, no adapter at all, an unmaterializable fixture, an unwritable results path) exit non-zero before any record is written and print no report" test_runner_04_internal_failures_exit_before_records
run_test "runner-04: the standalone report mode exits 0, prints the report, launches no client even on a fully-detected host (tripwired stubs untouched), and writes nothing" test_runner_04_report_mode_launches_no_client_and_writes_nothing

# ---- runner-06 ----------------------------------------------------------------
# The real bench never runs under the test suite: the owning suite is
# discovered by the mechanical tests/*_test.sh glob with no runner edit, it
# stays hermetic (dry-run client, report mode, recording stubs only -- the
# runner invocation is funneled through one helper that pins HOME and PATH,
# and nothing in the bench tree or the suite reaches for a network tool),
# and the full CLI path provably works on a host with no client CLIs, no
# config, and no credentials.

test_runner_06_discovery_is_mechanical() {
  # the runner's own discovery (the find -name '*_test.sh' glob documented
  # and used by tests/run_all.sh) picks this suite up...
  found=$(find "$HARNESS_REPO/tests" -maxdepth 1 -type f -name '*_test.sh' \
    | LC_ALL=C sort | grep -c '/bench-harness_test.sh$')
  [ "$found" = 1 ] || { echo "  the owning suite does not match the mechanical suite glob"; return 1; }
  # ...and the runner needed no edit for it: run_all.sh names no suite
  refuse "$HARNESS_REPO/tests/run_all.sh" 'bench-harness' \
    || { echo "    (a discovered suite must not be hardcoded into run_all.sh)"; return 1; }
  return 0
}

test_runner_06_suite_is_hermetic_by_construction() {
  # this file, resolved from its own invocation path (naming a sibling
  # suite's filename here would be the very coupling this scan polices)
  suite=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/$(basename -- "$0")
  [ -f "$suite" ] || { echo "  cannot locate this suite for the scan"; return 1; }
  # (1) every runner invocation goes through the single funnel (bench_cli):
  # outside comments the literal runner filename may appear nowhere but
  # that one invocation line
  n=$(sed -e 's/#.*//' "$suite" | grep -c 'antz-bench\.sh')
  [ "$n" = 1 ] \
    || { echo "  the runner is invoked at $n code sites -- expected exactly the bench_cli funnel"; return 1; }
  sed -e 's/#.*//' "$suite" | grep -F 'antz-bench.sh' | grep -qF 'env -i HOME=' \
    || { echo "  the runner funnel does not pin HOME and PATH via env -i"; return 1; }
  # (2) no network tool in the bench tree or in the suite's own code.
  # Comments and grep-pattern lines are scan material, not invocations --
  # what must never appear is a line that could EXECUTE a network tool.
  for f in "$HARNESS_REPO"/bench/*.sh "$suite"; do
    if sed -e 's/#.*//' -e '/[ /]grep[ (]/d' "$f" | grep -Eqi '\b(curl|wget|nc|ncat|telnet|ssh|scp|ftp)\b|https?://'; then
      echo "  a network tool appears in code: $f"
      sed -e 's/#.*//' -e '/[ /]grep[ (]/d' "$f" \
        | grep -Ei '\b(curl|wget|nc|ncat|telnet|ssh|scp|ftp)\b|https?://' | sed 's/^/    /'
      return 1
    fi
  done
  # (3) the runner-facing tests never point anything at the user's real
  # credentials: within the runner section, no line (comments and
  # grep-pattern lines filtered as above) may name a credential path under
  # a HOME. The clients section's credential handling is pinned hermetically
  # by sub-spec 04 itself (staged $real files and a sandbox whose HOME is
  # temp space), so only the runner-facing code -- where a real HOME would
  # reach a real client -- is held to the literal ban here. (1) already pins
  # that every runner process gets only a temp HOME.
  runner_code=$(awk '/^# ---- runner test helpers/{seen=1} seen' "$suite" \
    | sed -e 's/#.*//' -e '/[ /]grep[ (]/d')
  if printf '%s\n' "$runner_code" | grep -Eq 'HOME/\.claude/\.credentials|HOME/\.config/opencode/auth'; then
    echo "  a runner-facing suite line references a real credential location"
    return 1
  fi
  return 0
}

test_runner_06_full_cli_works_without_any_client_host() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  mkdir -p "$t/nohome"
  # env -i HOME=<no config> PATH=<no client CLIs>: no credentials to read
  # and nothing to detect -- the dry-run client and report mode carry the
  # whole suite path on such a machine
  bench_cli "$t/co" "$t/nohome" "$farm" --client dryrun --jsonl "$t/r.jsonl" \
    > "$t/out" 2> "$t/err" \
    || { echo "  the no-client-host dry-run invocation failed:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/r.jsonl")" = 1 ] || { echo "  no record on the no-client host"; return 1; }
  bench_cli "$t/co" "$t/nohome" "$farm" report --jsonl "$t/r.jsonl" > "$t/out" 2> "$t/err" \
    || { echo "  report mode failed on the no-client host:"; sed 's/^/    /' "$t/err"; return 1; }
  grep -qi 'report' "$t/out" || { echo "  report mode printed no report"; return 1; }
  # and the same clean host makes auto-detection refuse loudly (never a
  # silent fallback to some client)
  if bench_cli "$t/co" "$t/nohome" "$farm" --jsonl "$t/none.jsonl" > /dev/null 2>&1; then
    echo "  auto-detection did not refuse on a no-client host"
    return 1
  fi
  return 0
}

run_test "runner-06: the owning suite matches tests/run_all.sh's mechanical *_test.sh glob and run_all.sh names no suite (a new suite needs no runner edit)" test_runner_06_discovery_is_mechanical
run_test "runner-06: the suite is hermetic by construction -- every runner invocation goes through the single env -i funnel, no network tool appears in the bench tree or the suite's code, and no real credential path is referenced" test_runner_06_suite_is_hermetic_by_construction
run_test "runner-06: the whole runner CLI (dry-run repetition + report mode) succeeds under env -i on a host with no client CLIs, no config directories, and no credentials, while auto-detection refuses there" test_runner_06_full_cli_works_without_any_client_host

# ---- clientconfig-01 --------------------------------------------------------------
# The OpenCode credential is sourced from the host's REAL data dir --
# "${XDG_DATA_HOME:-$HOME/.local/share}/opencode/auth.json", where the client
# actually reads it -- and lands at the sandbox's data-dir location. A
# credential at the pre-fix config-dir path is a decoy: never copied. Both
# host files keep their bytes and location after the run.

test_clientconfig_01_credential_from_the_data_dir() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  make_recording_opencode_stub "$t/bin" || return 1
  mkdir -p "$t/hosthome/.local/share/opencode" "$t/hosthome/.config/opencode" || return 1
  printf 'CRED-FROM-DATA-DIR\n' > "$t/hosthome/.local/share/opencode/auth.json" || return 1
  printf 'CRED-FROM-CONFIG-DIR-DECOY\n' > "$t/hosthome/.config/opencode/auth.json" || return 1
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" --client opencode --repetitions 1 \
    --jsonl "$t/res.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the forced opencode repetition exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/res.jsonl")" = 1 ] \
    || { echo "  the repetition yielded $(rec_count "$t/res.jsonl") records, expected 1"; return 1; }
  sd="$t/bin/oc-record.d"
  [ -f "$sd/seen.1" ] || { echo "  the stub saw no run invocation"; cat "$t/err"; return 1; }
  grep -qx 'cred_data=exists' "$sd/seen.1" \
    || { echo "  no credential at the sandbox's data-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  cmp -s "$t/hosthome/.local/share/opencode/auth.json" "$sd/captured.1.cred_data" \
    || { echo "  the carried credential is not the data-dir file's bytes"; return 1; }
  grep -qx 'cred_config=absent' "$sd/seen.1" \
    || { echo "  a credential sits at the sandbox's config-dir location -- the decoy was copied:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  # both host files keep their bytes and location after the run
  printf 'CRED-FROM-DATA-DIR\n' | cmp -s - "$t/hosthome/.local/share/opencode/auth.json" \
    || { echo "  the host data-dir credential's bytes changed"; return 1; }
  printf 'CRED-FROM-CONFIG-DIR-DECOY\n' | cmp -s - "$t/hosthome/.config/opencode/auth.json" \
    || { echo "  the host config-dir decoy's bytes changed"; return 1; }
  return 0
}

run_test "clientconfig-01: the OpenCode credential is carried from the host's real data dir to the sandbox's data-dir location byte-faithfully, while a decoy at the pre-fix config-dir path is never copied and both host files keep their bytes and location" test_clientconfig_01_credential_from_the_data_dir

# ---- clientconfig-02 --------------------------------------------------------------
# The host's OpenCode provider config -- "${XDG_CONFIG_HOME:-$HOME/.config}/
# opencode/opencode.json", declaring a custom provider -- reaches the
# sandbox's config-dir location byte-identically and non-writable; the host
# file keeps its bytes and location after the run.

test_clientconfig_02_provider_config_carried_read_only() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  make_recording_opencode_stub "$t/bin" || return 1
  mkdir -p "$t/hosthome/.config/opencode" || return 1
  cat > "$t/hosthome/.config/opencode/opencode.json" <<'EOC' || return 1
{
  "provider": {
    "nan": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "local-nan-endpoint" },
      "models": { "stub-model": {} }
    }
  }
}
EOC
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" --client opencode --repetitions 1 \
    --jsonl "$t/res.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the forced opencode repetition exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  sd="$t/bin/oc-record.d"
  [ -f "$sd/seen.1" ] || { echo "  the stub saw no run invocation"; cat "$t/err"; return 1; }
  grep -qx 'provider_config=exists' "$sd/seen.1" \
    || { echo "  no provider config at the sandbox's config-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  cmp -s "$t/hosthome/.config/opencode/opencode.json" "$sd/captured.1.provider_config" \
    || { echo "  the carried provider config is not byte-identical to the host file"; return 1; }
  grep -qx 'provider_config.writable=no' "$sd/seen.1" \
    || { echo "  the carried provider config is writable by the client:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  case "$(grep '^provider_config\.mode=' "$sd/seen.1")" in
    *w*) echo "  the carried provider config keeps a write bit: $(grep '^provider_config\.mode=' "$sd/seen.1")"; return 1 ;;
  esac
  # the host file keeps its bytes and location after the run
  cmp -s "$t/hosthome/.config/opencode/opencode.json" "$sd/captured.1.provider_config" \
    || { echo "  the host provider config changed during the run"; return 1; }
  [ -w "$t/hosthome/.config/opencode/opencode.json" ] \
    || { echo "  the host provider config lost its write permission"; return 1; }
  return 0
}

run_test "clientconfig-02: the host's OpenCode provider config reaches the sandbox's config-dir location byte-identically and non-writable, and the host file keeps its bytes and location after the run" test_clientconfig_02_provider_config_carried_read_only

# ---- clientconfig-03 --------------------------------------------------------------
# Absent host files are skipped, never fabricated: a runner home carrying
# neither an OpenCode credential nor a provider config still yields a run
# that exits 0 with exactly one record, and the sandbox the client ran in
# holds neither file.

test_clientconfig_03_absent_files_skipped_not_fabricated() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  make_recording_opencode_stub "$t/bin" || return 1
  # the default controlled runner home: no client state of any kind
  mkdir -p "$t/hosthome" || return 1
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" --client opencode --repetitions 1 \
    --jsonl "$t/res.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the credential-less run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/res.jsonl")" = 1 ] \
    || { echo "  expected exactly one record, got $(rec_count "$t/res.jsonl")"; return 1; }
  sd="$t/bin/oc-record.d"
  [ -f "$sd/seen.1" ] || { echo "  the stub saw no run invocation"; cat "$t/err"; return 1; }
  grep -qx 'cred_data=absent' "$sd/seen.1" \
    || { echo "  a credential was FABRICATED at the sandbox's data-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  grep -qx 'cred_config=absent' "$sd/seen.1" \
    || { echo "  a credential was FABRICATED at the sandbox's config-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  grep -qx 'provider_config=absent' "$sd/seen.1" \
    || { echo "  a provider config was FABRICATED at the sandbox's config-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  [ ! -e "$sd/captured.1.cred_data" ] && [ ! -e "$sd/captured.1.cred_config" ] && [ ! -e "$sd/captured.1.provider_config" ] \
    || { echo "  the stub captured bytes for a file that was absent"; return 1; }
  return 0
}

run_test "clientconfig-03: a host with neither credential nor provider config yields a run that exits 0 with exactly one record and a sandbox carrying neither file -- nothing is fabricated" test_clientconfig_03_absent_files_skipped_not_fabricated

# ---- clientconfig-04 --------------------------------------------------------------
# The sourcing follows the REAL dirs: when the runner's environment sets
# XDG_DATA_HOME and XDG_CONFIG_HOME, both files are sourced from those
# relocated dirs (the HOME-default locations exist and hold nothing, so any
# default-path sourcing shows up as absence).

test_clientconfig_04_xdg_relocated_runner_env_honored() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  make_recording_opencode_stub "$t/bin" || return 1
  mkdir -p "$t/xdgdata/opencode" "$t/xdgconf/opencode" \
    "$t/hosthome/.local/share/opencode" "$t/hosthome/.config/opencode" || return 1
  printf 'CRED-IN-RELOCATED-DATA\n' > "$t/xdgdata/opencode/auth.json" || return 1
  printf 'PROVIDER-IN-RELOCATED-CONFIG\n' > "$t/xdgconf/opencode/opencode.json" || return 1
  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" \
    XDG_DATA_HOME="$t/xdgdata" XDG_CONFIG_HOME="$t/xdgconf" \
    --client opencode --repetitions 1 --jsonl "$t/res.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the XDG-relocated run exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  [ "$(rec_count "$t/res.jsonl")" = 1 ] \
    || { echo "  expected exactly one record, got $(rec_count "$t/res.jsonl")"; return 1; }
  sd="$t/bin/oc-record.d"
  [ -f "$sd/seen.1" ] || { echo "  the stub saw no run invocation"; cat "$t/err"; return 1; }
  grep -qx 'cred_data=exists' "$sd/seen.1" \
    || { echo "  no credential at the sandbox's data-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  cmp -s "$t/xdgdata/opencode/auth.json" "$sd/captured.1.cred_data" \
    || { echo "  the carried credential is not the XDG-relocated data dir file's bytes"; return 1; }
  grep -qx 'provider_config=exists' "$sd/seen.1" \
    || { echo "  no provider config at the sandbox's config-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  cmp -s "$t/xdgconf/opencode/opencode.json" "$sd/captured.1.provider_config" \
    || { echo "  the carried provider config is not the XDG-relocated config dir file's bytes"; return 1; }
  grep -qx 'cred_config=absent' "$sd/seen.1" \
    || { echo "  a credential reached the sandbox's config-dir location:"; sed 's/^/    /' "$sd/seen.1"; return 1; }
  # the relocated sources keep their bytes and locations after the run
  printf 'CRED-IN-RELOCATED-DATA\n' | cmp -s - "$t/xdgdata/opencode/auth.json" \
    || { echo "  the relocated credential's bytes changed"; return 1; }
  printf 'PROVIDER-IN-RELOCATED-CONFIG\n' | cmp -s - "$t/xdgconf/opencode/opencode.json" \
    || { echo "  the relocated provider config's bytes changed"; return 1; }
  return 0
}

run_test "clientconfig-04: an XDG-relocated runner environment is honored -- both files are carried with the bytes of the relocated sources, nothing arrives from the empty HOME-default locations, and the sources keep their bytes and location" test_clientconfig_04_xdg_relocated_runner_env_honored

# ---- report test helpers --------------------------------------------------------
# Sub-spec 06 owns the aggregate statistics behind the bench_report seam
# (bench/lib.sh); the suite drives them exclusively through the standalone
# report mode -- "sh bench/antz-bench.sh report --jsonl <f> [--baseline <b>]"
# via the runner funnel -- so the CLI wiring, the seam, and the computation
# are pinned on one path. report-04's "any conforming JSONL" is why some
# inputs below are hand-written or carry foreign client/version/repetition
# values rather than coming from a live dry-run invocation.

# The report's pinned closed metric set, transcribed from the sub-spec's
# report-01 scenario (pinned order). The suite keeps its own copy on
# purpose: a drift in bench_report_metrics must go red here.
REPORT_METRICS="wall_clock_ms client_duration_ms tokens_input tokens_output tokens_reasoning tokens_cache_read tokens_cache_write cost_usd turns tool_calls subagent_delegations"

report_fixture_jsonl() {
  # $1 = destination: the 06-report Background records -- client "dryrun",
  # five repetitions with wall_clock_ms 100, 200, 300, 400, 1000;
  # tokens_input 1000..5000; cost_usd 0.01, 0.02, null, 0.04, 0.05;
  # outcomes approved x3, error x1, timeout x1; model_pinned null, null,
  # m-one, m-one, m-two -- plus one client "stub" record with
  # wall_clock_ms 500 (model_pinned m-two). Every line is emitted through
  # the schema, so the file is conforming JSONL.
  out="$1"
  emit_kv "$out" run_id=dryrun-1 wall_clock_ms=100 tokens_input=1000 cost_usd=0.01 model_pinned=null outcome=approved || return 1
  emit_kv "$out" run_id=dryrun-2 wall_clock_ms=200 tokens_input=2000 cost_usd=0.02 model_pinned=null outcome=approved || return 1
  emit_kv "$out" run_id=dryrun-3 wall_clock_ms=300 tokens_input=3000 cost_usd=null model_pinned=m-one outcome=approved || return 1
  emit_kv "$out" run_id=dryrun-4 wall_clock_ms=400 tokens_input=4000 cost_usd=0.04 model_pinned=m-one outcome=error exit_code=1 error_note="stubbed failure" || return 1
  emit_kv "$out" run_id=dryrun-5 wall_clock_ms=1000 tokens_input=5000 cost_usd=0.05 model_pinned=m-two outcome=timeout exit_code=143 error_note="deadline fired" || return 1
  emit_kv "$out" run_id=stub-1 client=stub wall_clock_ms=500 model_pinned=m-two outcome=approved || return 1
  [ "$(rec_count "$out")" = 6 ] || { echo "  the Background JSONL did not gain 6 records"; return 1; }
  return 0
}

report_baseline_jsonl() {
  # $1 = destination: a second conforming JSONL whose dryrun group has a
  # DIFFERENT wall_clock_ms mean (100, 200 -- mean 150 against the
  # Background's 400), a different client_duration_ms mean (70, 90 against
  # 50), values for tokens_reasoning where the Background has none, no
  # cost_usd values where the Background has four, and one client "zed"
  # record that appears on no other side.
  out="$1"
  emit_kv "$out" run_id=base-1 wall_clock_ms=100 client_duration_ms=70 cost_usd=null tokens_reasoning=1 || return 1
  emit_kv "$out" run_id=base-2 wall_clock_ms=200 client_duration_ms=90 cost_usd=null tokens_reasoning=2 || return 1
  emit_kv "$out" run_id=base-zed client=zed wall_clock_ms=7 || return 1
  [ "$(rec_count "$out")" = 3 ] || { echo "  the baseline JSONL did not gain 3 records"; return 1; }
  return 0
}

report_group_block() {
  # $1 = report text, $2 = client name: the group's indented lines from its
  # "client <name>:" header through the next group header, baseline section,
  # or EOF (the header itself excluded).
  printf '%s\n' "$1" | awk -v c="$2" '
    index($0, "client " c ":") == 1 { f = 1; next }
    index($0, "client ") == 1 { f = 0 }
    index($0, "baseline comparison") == 1 { f = 0 }
    f { print }
  '
}

report_baseline_block() {
  # $1 = report text: the baseline comparison section below its header.
  printf '%s\n' "$1" | awk '
    index($0, "baseline comparison") == 1 { f = 1; next }
    f { print }
  '
}

# ---- report-01 ----------------------------------------------------------------
# The report groups by client and prints each group whole: record count,
# the distinct model_pinned values seen, the outcome distribution, and for
# every metric of the pinned report set the statistics n, mean, median,
# min, max, p95 -- nulls excluded and never crashing the report: an
# all-null metric prints null statistics, and a metric no record of the
# group carries at all is reported absent without failing the report. The
# total record count across groups prints too.

test_report_01_groups_and_shapes() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM

  # the metric list is the pinned closed set from the schema domain
  got=$(bench_report_metrics | tr '\n' ' ' | sed 's/ *$//')
  [ "$got" = "$REPORT_METRICS" ] \
    || { echo "  bench_report_metrics drifts from the pinned report metric set: [$got]"; return 1; }

  report_fixture_jsonl "$t/res.jsonl" || { echo "  the Background JSONL could not be built"; return 1; }
  bench_cli "$t/co" "$t/home" "$farm" report --jsonl "$t/res.jsonl" > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  report mode exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  grep -q '^antz-bench report: total records: 6$' "$t/out" \
    || { echo "  the total record count across groups is missing or wrong:"; sed 's/^/    /' "$t/out"; return 1; }

  # one group per client, with count and the distinct pinned models seen
  grep -q '^client dryrun: records=5 models=m-one,m-two$' "$t/out" \
    || { echo "  no dryrun group with records=5 and the distinct model_pinned values:"; sed 's/^/    /' "$t/out"; return 1; }
  grep -q '^client stub: records=1 models=m-two$' "$t/out" \
    || { echo "  no stub group with records=1 and its model:"; sed 's/^/    /' "$t/out"; return 1; }
  rep=$(cat "$t/out")
  dry=$(report_group_block "$rep" dryrun)
  printf '%s\n' "$dry" | grep -qxF '  outcomes: approved=3 error=1 timeout=1' \
    || { echo "  the dryrun outcome distribution is not each outcome with its count:"; printf '%s\n' "$dry" | sed 's/^/    /'; return 1; }
  printf '%s\n' "$(report_group_block "$rep" stub)" | grep -qxF '  outcomes: approved=1' \
    || { echo "  the stub outcome distribution is wrong"; return 1; }

  # every pinned metric carries exactly one line with all six statistics
  for mname in $REPORT_METRICS; do
    n=$(printf '%s\n' "$dry" | grep -c "^  $mname: ")
    [ "$n" = 1 ] || { echo "  the dryrun group prints $n lines for $mname, expected 1"; return 1; }
    printf '%s\n' "$dry" | grep -qE "^  $mname: n=[0-9]+ mean=[^ ]+ median=[^ ]+ min=[^ ]+ max=[^ ]+ p95=[^ ]+$" \
      || { echo "  $mname lacks the n/mean/median/min/max/p95 shape:"; printf '%s\n' "$dry" | grep "  $mname" | sed 's/^/    /'; return 1; }
  done

  # an all-null metric prints null statistics, never fabricated zeros
  printf '%s\n' "$dry" | grep -qxF '  tokens_reasoning: n=0 mean=null median=null min=null max=null p95=null' \
    || { echo "  the all-null tokens_reasoning did not print null statistics"; return 1; }
  printf '%s\n' "$dry" | grep -qxF '  tokens_cache_write: n=0 mean=null median=null min=null max=null p95=null' \
    || { echo "  the all-null tokens_cache_write did not print null statistics"; return 1; }
  printf '%s\n' "$dry" | grep -qE '(mean|median|min|max|p95)=0( |$)' \
    && { echo "  an all-null metric printed a zero statistic"; return 1; }

  # a metric no record carries at all is reported absent -- the report
  # does not fail over it (a hand-written old-version line)
  printf '%s\n' '{"client":"legacy","outcome":"approved","wall_clock_ms":42}' > "$t/old.jsonl"
  bench_cli "$t/co" "$t/home" "$farm" report --jsonl "$t/old.jsonl" > "$t/out2" 2> "$t/err2"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the report failed over a JSONL with absent metrics:"; sed 's/^/    /' "$t/err2"; return 1; }
  leg=$(report_group_block "$(cat "$t/out2")" legacy)
  printf '%s\n' "$leg" | grep -qxF '  wall_clock_ms: n=1 mean=42 median=42 min=42 max=42 p95=42' \
    || { echo "  the legacy group's present metric is wrong:"; printf '%s\n' "$leg" | sed 's/^/    /'; return 1; }
  nabsent=$(printf '%s\n' "$leg" | grep -c ': absent$')
  [ "$nabsent" = 10 ] \
    || { echo "  the legacy group reported $nabsent absent metrics, expected the other 10"; return 1; }
  return 0
}

# ---- report-02 ----------------------------------------------------------------
# The statistic definitions are pinned and deterministic: over the known
# Background values the report reads exactly n=5 mean=400 median=300
# min=100 max=1000 p95=1000 for wall_clock_ms (nearest-rank p95),
# mean=3000 median=3000 for tokens_input, n=4 mean=0.03 median=0.03
# p95=0.05 for cost_usd (the null excluded, the standard median over the
# two middle sorted values), n=1 with every statistic 500 for the stub
# group -- and the same input file always produces the same report text.

test_report_02_pinned_values() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  report_fixture_jsonl "$t/res.jsonl" || { echo "  the Background JSONL could not be built"; return 1; }

  bench_cli "$t/co" "$t/home" "$farm" report --jsonl "$t/res.jsonl" > "$t/out1" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  report mode exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  dry=$(report_group_block "$(cat "$t/out1")" dryrun)
  for line in \
    '  wall_clock_ms: n=5 mean=400 median=300 min=100 max=1000 p95=1000' \
    '  tokens_input: n=5 mean=3000 median=3000 min=1000 max=5000 p95=5000' \
    '  cost_usd: n=4 mean=0.03 median=0.03 min=0.01 max=0.05 p95=0.05'; do
    printf '%s\n' "$dry" | grep -qxF "$line" \
      || { echo "  the dryrun group is missing the pinned statistics line [$line]:"; printf '%s\n' "$dry" | sed 's/^/    /'; return 1; }
  done
  st=$(report_group_block "$(cat "$t/out1")" stub)
  printf '%s\n' "$st" | grep -qxF '  wall_clock_ms: n=1 mean=500 median=500 min=500 max=500 p95=500' \
    || { echo "  the stub group's single-record statistics are wrong:"; printf '%s\n' "$st" | sed 's/^/    /'; return 1; }

  # the same input file always produces the same report text
  bench_cli "$t/co" "$t/home" "$farm" report --jsonl "$t/res.jsonl" > "$t/out2" 2> "$t/err2" \
    || { echo "  the second report run failed:"; sed 's/^/    /' "$t/err2"; return 1; }
  cmp -s "$t/out1" "$t/out2" \
    || { echo "  the same input produced two different report texts:"; diff "$t/out1" "$t/out2" | sed 's/^/    /'; return 1; }

  # the Background's groups make p95 coincide with max (rank = n at n<=5)
  # and never have an even n, so a second file pins the definitions apart
  # from wrong-but-similar rules: 20 records with wall_clock_ms 1..20
  # demand nearest-rank p95 (the ceil(0.95*20) = 19th sorted value, NOT
  # the max) and the standard even-n median ((10+11)/2 = 10.5, NOT
  # either middle value on its own)
  rep=1
  while [ "$rep" -le 20 ]; do
    emit_kv "$t/twenty.jsonl" run_id="twenty-$rep" repetition="$rep" wall_clock_ms="$rep" >/dev/null \
      || { echo "  the 20-record file could not be emitted"; return 1; }
    rep=$((rep + 1))
  done
  bench_cli "$t/co" "$t/home" "$farm" report --jsonl "$t/twenty.jsonl" > "$t/out3" 2> "$t/err3" \
    || { echo "  report mode failed on the 20-record file:"; sed 's/^/    /' "$t/err3"; return 1; }
  twenty=$(report_group_block "$(cat "$t/out3")" dryrun)
  printf '%s\n' "$twenty" | grep -qxF '  wall_clock_ms: n=20 mean=10.5 median=10.5 min=1 max=20 p95=19' \
    || { echo "  the 20-value wall_clock_ms statistics are not nearest-rank p95 / standard median:"; printf '%s\n' "$twenty" | grep wall_clock_ms | sed 's/^/    /'; return 1; }
  return 0
}

# ---- report-03 ----------------------------------------------------------------
# The baseline comparison prints, for each client and metric present on
# both sides, the baseline mean and median beside the current ones with a
# signed delta (current minus baseline, printed with its sign); a client
# or metric that exists on only one side is named absent on the other --
# never a zero or null delta. The baseline file is only ever read.

test_report_03_baseline_deltas() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  report_fixture_jsonl "$t/res.jsonl" || return 1
  report_baseline_jsonl "$t/base.jsonl" || return 1
  cp "$t/base.jsonl" "$t/base.before" || return 1

  bench_cli "$t/co" "$t/home" "$farm" report --jsonl "$t/res.jsonl" --baseline "$t/base.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  the baseline report exited $rc:"; sed 's/^/    /' "$t/err"; return 1; }
  grep -q '^baseline comparison' "$t/out" \
    || { echo "  the report carries no baseline comparison section:"; sed 's/^/    /' "$t/out"; return 1; }
  cmpb=$(report_baseline_block "$(cat "$t/out")")
  printf '%s\n' "$cmpb" | grep -qxF '  client dryrun:' \
    || { echo "  the comparison names no dryrun client:"; printf '%s\n' "$cmpb" | sed 's/^/    /'; return 1; }

  # both sides present: baseline mean and median beside the current ones,
  # signed both ways (current 400 vs baseline 150 is +250; current 50 vs
  # baseline 80 is -30)
  printf '%s\n' "$cmpb" | grep -qxF \
    '    wall_clock_ms: current mean=400 median=300 baseline mean=150 median=150 delta=+250' \
    || { echo "  the wall_clock_ms comparison line is wrong (current mean/median, baseline mean/median, signed delta):"; printf '%s\n' "$cmpb" | grep wall_clock_ms | sed 's/^/    /'; return 1; }
  printf '%s\n' "$cmpb" | grep -qxF \
    '    client_duration_ms: current mean=50 median=50 baseline mean=80 median=80 delta=-30' \
    || { echo "  the client_duration_ms comparison line (negative delta) is wrong:"; printf '%s\n' "$cmpb" | grep client_duration_ms | sed 's/^/    /'; return 1; }

  # one-sided metrics are named gaps, never deltas
  printf '%s\n' "$cmpb" | grep -qxF '    cost_usd: absent in baseline' \
    || { echo "  a metric with values only in the results was not named absent in baseline"; return 1; }
  printf '%s\n' "$cmpb" | grep -qxF '    tokens_reasoning: absent in results' \
    || { echo "  a metric with values only in the baseline was not named absent in results"; return 1; }
  printf '%s\n' "$cmpb" | grep ': absent' | grep -q 'delta=' \
    && { echo "  an absent one-sided metric still carried a delta"; return 1; }
  printf '%s\n' "$cmpb" | grep -qE 'delta=(null|0( |$))' \
    && { echo "  a bare zero or null delta was invented"; return 1; }

  # one-sided clients are named too
  printf '%s\n' "$cmpb" | grep -qxF '  client stub: absent in baseline (no comparison)' \
    || { echo "  the stub client (results side only) was not named absent in baseline"; return 1; }
  printf '%s\n' "$cmpb" | grep -qxF '  client zed: absent in results (no comparison)' \
    || { echo "  the zed client (baseline side only) was not named absent in results"; return 1; }

  # the baseline file is only read: bytes unchanged, still in place,
  # never appended to or moved
  cmp -s "$t/base.before" "$t/base.jsonl" \
    || { echo "  the report wrote to its baseline input"; return 1; }
  [ "$(rec_count "$t/base.jsonl")" = 3 ] \
    || { echo "  the baseline file changed shape"; return 1; }
  return 0
}

# ---- report-04 ----------------------------------------------------------------
# Report mode is standalone: on a host that merely LOOKS cliented (config
# directories and a tripwired claude stub on PATH) it exits 0, launches no
# client and no adapter, materializes no fixture (no results area appears),
# writes nothing except its stdout, and accepts any conforming JSONL
# regardless of which antz version, client mix, or repetition count
# produced it -- including a baseline recorded on another machine.

test_report_04_standalone_any_input() {
  t=$(new_tmp_dir)
  stage_runner_checkout "$t/co" || { echo "  staging the runner checkout failed"; return 1; }
  runner_farm || return 1; farm=$RUNNER_FARM
  mkdir -p "$t/hosthome/.claude" "$t/hosthome/.config/opencode"
  make_runner_claude_stub "$t/bin" "$t/claude-launched" || return 1

  # an "other machine" input: foreign versions, client mix, repetition
  # numbers, and one hand-written line whose metric keys are simply absent
  emit_kv "$t/a.jsonl" run_id=other-1 client=claude antz_version=9.9.9 repetition=7 model_pinned=stub/model-x wall_clock_ms=123 outcome=approved || return 1
  emit_kv "$t/a.jsonl" run_id=other-2 client=opencode antz_version=1.2.3 repetition=3 model_pinned=null wall_clock_ms=456 outcome=rejected || return 1
  printf '%s\n' '{"client":"legacy","outcome":"approved","wall_clock_ms":42}' >> "$t/a.jsonl"
  # a baseline from a THIRD mix (the dryrun + zed fixture)
  report_baseline_jsonl "$t/b.jsonl" || return 1
  cp "$t/a.jsonl" "$t/a.before" || return 1
  cp "$t/b.jsonl" "$t/b.before" || return 1

  bench_cli "$t/co" "$t/hosthome" "$t/bin:$farm" report --jsonl "$t/a.jsonl" --baseline "$t/b.jsonl" \
    > "$t/out" 2> "$t/err"
  rc=$?
  [ "$rc" -eq 0 ] || { echo "  report mode exited $rc on foreign inputs:"; sed 's/^/    /' "$t/err"; return 1; }
  grep -q '^antz-bench report: total records: 3$' "$t/out" \
    || { echo "  the foreign-mix input was not aggregated whole:"; sed 's/^/    /' "$t/out"; return 1; }
  for c in claude opencode legacy; do
    grep -q "^client $c: records=" "$t/out" \
      || { echo "  no group for the input's client $c:"; sed 's/^/    /' "$t/out"; return 1; }
  done
  cmpb=$(report_baseline_block "$(cat "$t/out")")
  printf '%s\n' "$cmpb" | grep -qxF '  client dryrun: absent in results (no comparison)' \
    || { echo "  the other-machine baseline's own client does not appear in the comparison"; return 1; }
  printf '%s\n' "$cmpb" | grep -qxF '  client claude: absent in baseline (no comparison)' \
    || { echo "  the results-only client was not named absent in baseline"; return 1; }

  # standalone: nothing launched, nothing written outside stdout
  [ ! -e "$t/claude-launched" ] \
    || { echo "  report mode launched a client"; return 1; }
  [ ! -e "$t/co/bench/results" ] \
    || { echo "  report mode created the results area -- it materializes no fixture and runs no repetition"; return 1; }
  [ ! -s "$t/err" ] || { echo "  report mode wrote beyond its report output:"; sed 's/^/    /' "$t/err"; return 1; }
  cmp -s "$t/a.before" "$t/a.jsonl" || { echo "  report mode wrote to its --jsonl input"; return 1; }
  cmp -s "$t/b.before" "$t/b.jsonl" || { echo "  report mode wrote to its --baseline input"; return 1; }
  return 0
}

run_test "report-01: the report groups by client and prints each group's record count, distinct model_pinned values, outcome distribution, and n/mean/median/min/max/p95 for every pinned metric -- all-null metrics print null statistics, an absent metric is reported absent without failing the report, and the total record count across groups prints" test_report_01_groups_and_shapes
run_test "report-02: the statistics are exactly the pinned ones -- nearest-rank p95, standard median, null-excluding arithmetic mean over the known Background values (n=5 mean=400 median=300 min=100 max=1000 p95=1000; cost n=4 mean=0.03 median=0.03 p95=0.05; stub n=1 all 500) -- and the same input always yields the same report text" test_report_02_pinned_values
run_test "report-03: the baseline comparison prints baseline mean and median beside the current ones with a signed delta for metrics present on both sides, names one-sided clients and metrics absent instead of inventing deltas, and only ever reads the baseline file" test_report_03_baseline_deltas
run_test "report-04: report mode is standalone -- it exits 0 on any conforming JSONL regardless of antz version, client mix, or repetition count (a baseline from another machine included), launches no client and no adapter, materializes no fixture, and writes nothing except its report output" test_report_04_standalone_any_input

finish_suite

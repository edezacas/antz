#!/usr/bin/env bash
#
# eval/rejudge.sh — re-make the verdicts from the traces already on disk, for free.
#
# A verdict is a pure function of the session and the end state, so a change to the
# judge — or a bug found in it — costs nothing to re-check: this points `judge.mjs` at
# every session in `out/` and at the compact snapshot the run kept beside it, and writes
# `out/rejudged.tsv`. Seconds, not a batch, and no model is called.
#
#   ./rejudge.sh          # every trace, then a diff against results.tsv
#   ./rejudge.sh S        # only that scenario
#
# It never overwrites `results.tsv`. That is the record of what was paid for, judged the
# way it was judged at the time, and rows deliberately kept there under a rule the design
# no longer holds stay readable — the point is to see what the current judge would say
# instead, not to rewrite history.
#
# A trace whose snapshot is gone is judged on what the session alone can settle: the
# trace-level checks, which is where the counting bugs lived. The verdict comes back
# UNKNOWN when the end state was needed, never a PASS the session cannot support. The
# `state` column says which of the three it was: `snapshot`, `sandbox`, `trace-only`.

set -uo pipefail

[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { sed -n '3,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out"
# Older runs left their sandbox under this root; a snapshot in `out/` is preferred
# because it survives the cleanup the README suggests.
SANDBOX="${ANTZ_EVAL_SANDBOX:-${TMPDIR:-/tmp}/antz-eval}"
filter="${1:-}"

command -v node >/dev/null 2>&1 || {
  echo "node is required: the verdict is computed by judge.mjs" >&2
  exit 1
}
[ -d "$OUT" ] || { echo "no $OUT: nothing has been run yet" >&2; exit 1; }

REJUDGED="$OUT/rejudged.tsv"
printf 'scenario\trun\tverdict\tsequence\tdetail\tstate\n' >"$REJUDGED"

# The last paid row for a run is the one its session file belongs to: a re-run overwrites
# the trace, so an older row for the same key describes a session that no longer exists.
paid_seconds() {
  awk -F'\t' -v s="$1" -v r="$2" '$1==s && $2==r { seconds=$6 } END { print seconds }' "$OUT/results.tsv" 2>/dev/null
}

for session in "$OUT"/*.session.jsonl; do
  [ -f "$session" ] || continue
  base="$(basename "$session" .session.jsonl)"
  scenario="${base%%-*}"
  run="${base##*-}"
  case "$scenario" in A|B|C|D|S|M|N|H) ;; *) echo "skip $base: no contract in judge.mjs for '$scenario'" >&2; continue ;; esac
  [ -n "$filter" ] && [ "$filter" != "$scenario" ] && continue

  state="$OUT/$base.state"
  where=snapshot
  if [ ! -d "$state" ] && [ -d "$SANDBOX/$base" ]; then
    state="$SANDBOX/$base"
    where=sandbox
  elif [ ! -d "$state" ]; then
    state=""
    where=trace-only
  fi

  # Seconds decide S's timeout check, and the timeout was a property of the run, so both
  # come from what the run recorded — the snapshot's run.json, else the paid row.
  seconds=""; timeout=1800
  if [ -f "${state:-/nonexistent}/run.json" ]; then
    seconds="$(jq -r '.seconds // empty' "$state/run.json")"
    timeout="$(jq -r '.timeout // 1800' "$state/run.json")"
  else
    seconds="$(paid_seconds "$scenario" "$run")"
  fi

  args=(--scenario "$scenario" --session "$session" --timeout "$timeout")
  [ -n "$state" ] && args+=(--state "$state")
  [ -n "$seconds" ] && args+=(--seconds "$seconds")
  out="$(node "$HERE/judge.mjs" "${args[@]}" 2>/dev/null)"
  IFS=$'\t' read -r verdict reason trace _ <<<"$out"
  [ -n "${verdict:-}" ] || { verdict=FAIL; reason="judge.mjs produced no verdict"; trace="(no dispatches)"; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$scenario" "$run" "$verdict" "$trace" "$reason" "$where" >>"$REJUDGED"
  printf '%s  %s/%s  [%s]  (%s)\n    %s\n' "$verdict" "$scenario" "$run" "$trace" "$where" "$reason"
done

echo
echo "== what the current judge says against what was paid for"
awk -F'\t' -v file="$REJUDGED" '
  FNR == NR { if (FNR > 1) { was[$1"/"$2] = $3 } next }
  FNR > 1 {
    key = $1"/"$2
    if (!(key in was)) { printf "  %s: %s (no paid row to compare)\n", key, $3; next }
    if (was[key] != $3) { changed++; printf "  %s: %s -> %s  (%s)\n", key, was[key], $3, $6 }
  }
  END { printf "  %d row(s) changed; written to %s\n", changed + 0, file }
' "$OUT/results.tsv" "$REJUDGED"

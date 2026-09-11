#!/bin/sh
set -eu

: "${CHANGE_DIR:?CHANGE_DIR must be set to the spdd/changes/<slug> path}"

if [ ! -d "$CHANGE_DIR" ]; then
  echo "change_dir=missing"
  exit 1
fi

if [ -f "$CHANGE_DIR/OPEN_QUESTIONS.md" ]; then
  echo "open_questions=yes"
  exit 0
fi
echo "open_questions=no"

rejected_count=0
if [ -f "$CHANGE_DIR/REJECTED.md" ]; then
  rejected_count=$(grep -c '^## Rejection [0-9][0-9]*[[:space:]]*$' "$CHANGE_DIR/REJECTED.md" || true)
fi
echo "rejected_count=$rejected_count"

# Counts the declared ids in a comma-separated ids string ("" counts 0).
declared_count() {
  awk -v dids="$1" 'BEGIN { m = split(dids, a, ","); c = 0; for (i = 1; i <= m; i++) if (a[i] != "") c++; print c }'
}

# Classifies one sub-spec's result receipt. $1 = receipt path (may not
# exist), $2 = the sub-spec's declared ids (comma-separated). Prints
# "receipt=<basename|missing> covered=<n>/<N> complete=<yes|no> class=<...>"
# with no trailing newline; the subspec= line composes it after ids=.
#
# The receipt grammar (one test_command= line with a non-empty value, then
# one "id=<id> result=<green|skip|blocked> reason=<text>" line per declared
# id) is checked mechanically:
#   complete=yes requires the receipt to exist, carry exactly one non-empty
#   test_command= line, and name exactly the declared id set -- a foreign
#   id, a duplicate id, an uncovered declared id, an id line with an empty
#   reason or an unknown result value are all mismatches (complete=no), and
#   a sub-spec with no declared ids is never vacuously done (complete=no).
#   class= applies the mapping: any result=blocked line -> blocked (checked
#   first, regardless of coverage); else complete=yes -> done (all results
#   are then green or ordinary-skip by construction); else in_progress.
# The probe runs no tests and no git: the receipt is read as a file, like
# OPEN_QUESTIONS.md and REJECTED.md before it.
classify_receipt() {
  receipt="$1"
  dids="$2"
  if [ ! -f "$receipt" ]; then
    printf 'receipt=missing covered=0/%s complete=no class=in_progress' "$(declared_count "$dids")"
    return 0
  fi
  awk -v dids="$dids" -v rname="$(basename "$receipt")" '
    BEGIN {
      ndecl = 0
      m = split(dids, a, ",")
      for (i = 1; i <= m; i++) if (a[i] != "") { ndecl++; declared[ndecl] = a[i]; declaredset[a[i]] = 1 }
      tcmd = 0; tcmd_ne = 0; blocked = 0; malformed = 0; dup = 0; foreign = 0
      nseen = 0
    }
    /^test_command=/ {
      tcmd++
      if (substr($0, 14) != "") tcmd_ne++
      next
    }
    /^id=/ {
      n = split($0, w, " ")
      id = substr(w[1], 4)
      if (id in seen) dup = 1
      seen[id] = 1
      order[++nseen] = id
      if (!(id in declaredset)) foreign = 1
      res = ""
      if (n >= 2 && w[2] ~ /^result=/) res = substr(w[2], 8)
      ok = 0
      if (res == "blocked") blocked = 1
      if (res == "green" || res == "skip" || res == "blocked") {
        if (n >= 3 && w[3] ~ /^reason=./) ok = 1
      }
      if (!ok) malformed = 1
      next
    }
    END {
      covered = 0
      missing = 0
      for (i = 1; i <= ndecl; i++) {
        if (declared[i] in seen) covered++
        else missing = 1
      }
      for (i = 1; i <= nseen; i++) if (!(order[i] in declaredset)) foreign = 1
      complete = 1
      if (tcmd != 1 || tcmd_ne != 1) complete = 0
      if (malformed || dup || foreign || missing || ndecl == 0) complete = 0
      cls = "in_progress"
      if (blocked) cls = "blocked"
      else if (complete) cls = "done"
      printf "receipt=%s covered=%d/%d complete=%s class=%s", rname, covered, ndecl, (complete ? "yes" : "no"), cls
    }
  ' "$receipt"
}

for f in "$CHANGE_DIR"/[0-9][0-9]-*.feature; do
  [ -e "$f" ] || continue
  ids=$(awk '/^[[:space:]]*#/ { if (buf == "") first = $0; buf = buf $0 "\n"; next }
             /^[[:space:]]*Scenario([[:space:]]+Outline)?:/ { print first }
             { buf = ""; first = "" }' "$f" | grep -oE '[A-Za-z][A-Za-z0-9_-]*-[0-9]+' | sort -u | tr '\n' ',' | sed 's/,$//')
  printf 'subspec=%s ids=%s %s\n' "$(basename "$f")" "$ids" "$(classify_receipt "${f%.feature}.result" "$ids")"
done

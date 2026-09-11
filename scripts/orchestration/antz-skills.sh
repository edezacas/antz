#!/bin/sh
# antz-skills.sh — derive one delegation's "## Skills to load before work"
# listing from disk, statelessly, at delegation time. Nothing is written:
# no registry, no cache — derive it fresh for every delegation. usage:
#   sh <tempfile> <working-root> <match keyword> [<match keyword> ...]
# Prints at most five lines
#   skill=<name> path=<absolute SKILL.md path> matched=<kw,kw,...>
# (best match first, alphabetical-by-name tie-break) or, when nothing
# matches or no skills directory exists, exactly one line:
#   Skills: none matched
set -eu

root=${1:-}
[ -n "$root" ] || { echo 'usage: antz-skills.sh <working-root> <keyword>...'; exit 1; }
lc() { tr '[:upper:]' '[:lower:]'; }
LC_ALL=C
export LC_ALL

res_list=""
seen_names=""

for base in "$root/.agents" "$root/.claude" "$root/.opencode" \
   "$HOME/.agents" "$HOME/.claude" "$HOME/.config/opencode"; do
 base="$base/skills"
 [ -d "$base" ] || continue
 for m in "$base"/*; do
   [ -d "$m" ] || continue
   [ -f "$m/SKILL.md" ] || continue
   fm=$(awk '
     NR == 1 && /^---[[:space:]]*$/ { fm = 1; next }
     fm && /^---[[:space:]]*$/ { exit }
     fm { print }
   ' "$m/SKILL.md")
   nm=$(printf '%s\n' "$fm" | awk '/^[Nn]ame:/ { sub(/^[Nn]ame:[[:space:]]*/, ""); print; exit }')
   if [ -z "$nm" ]; then nm=$(basename "$m"); fi
   case "$nm" in *'|'*) continue ;; esac
   case "$seen_names" in *"|$nm|"*) continue ;; esac
   # Matching text: the description field's content only -- a plain
   # single-line value, or a folded ('>' / '>-') block scalar with its
   # indented continuation lines accumulated until the next top-level
   # key or the end of the frontmatter. The name, license, metadata,
   # and the skill body below the '---' fence are never matched.
   desc=$(printf '%s\n' "$fm" | awk '
     seen { next }
     /^[Dd]escription:/ {
       sub(/^[Dd]escription:[[:space:]]*/, "")
       if ($0 ~ /^[>|][0-9+-]*[[:space:]]*$/) { block = 1; next }
       print
       seen = 1
       next
     }
     block && /^[[:space:]]/ { sub(/^[[:space:]]+/, ""); print; next }
     block && /^[[:space:]]*$/ { next }
     block { seen = 1 }
   ')
   desc_l=$(printf '%s\n' "$desc" | lc)
   score=0
   reason=""
   for kw in "$@"; do
     kw=$(printf '%s' "$kw" | lc)
     case "$kw" in '') continue ;; esac
     case "$desc_l" in
       *"$kw"*) score=$((score + 1)); reason="$reason,$kw" ;;
     esac
   done
   [ "$score" -gt 0 ] || continue
   abs=$(cd "$m" && pwd)
   seen_names="$seen_names|$nm|"
   res_list="$res_list$nm|$score|$abs/SKILL.md|${reason#,}
"
 done
  done

if [ -z "$res_list" ]; then
  echo 'Skills: none matched'
  exit 0
fi
chosen=$(printf '%s\n' "$res_list" | sort -t'|' -k2,2nr -k1,1 | head -n 5)
while IFS='|' read -r nm score path reason; do
  [ -n "$nm" ] || continue
  printf 'skill=%s path=%s matched=%s\n' "$nm" "$path" "$reason"
done <<EOF_TOP
$chosen
EOF_TOP

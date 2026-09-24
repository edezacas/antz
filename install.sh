#!/usr/bin/env bash
# Installs antz's pi artifacts: five subagents, the /antz prompt and the extension
# that dispatches them. The three skills are a separate, global install shared by
# every agent-skills client (see README), so this script neither writes nor
# verifies them.
#
#   curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --ref v1.0.0
#   ./install.sh                       # from a checkout: copies the working tree
#   ./install.sh --uninstall
#
# Nothing is ever read from stdin: under `curl | bash` stdin is this script.
#
# Nothing is built and nothing is fetched but the source tree. Only antz's own
# paths are touched, so a reinstall is an upgrade and unrelated files in pi's
# agent dir survive both directions. The one thing a plain copy would otherwise
# clobber is the `model:` line the user pinned in an agent file, so that line
# survives a reinstall.

set -euo pipefail

REPO="edezacas/antz"
REF="master"

# pi's config dir. PI_CODING_AGENT_DIR is the variable getAgentDir() honours, so
# ignoring it would install where the extension never looks. The skills are not
# affected: they live outside this tree, in the shared ~/.agents/skills.
DEST="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

# What antz owns. Anything else in these directories belongs to someone else.
AGENTS=(antz-scout antz-planner antz-tester antz-implementer antz-verifier)
SKILLS=(antz-clarify antz-tdd antz-architecture)
PROMPT="antz"
EXTENSION="antz-subagent.ts"

UNINSTALL=0
SOURCE=""
TMP=""

if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); GREEN=$(printf '\033[32m'); RED=$(printf '\033[31m'); OFF=$(printf '\033[0m')
else
  BOLD=""; DIM=""; GREEN=""; RED=""; OFF=""
fi

say()  { printf '%s\n' "$1"; }
step() { printf '\n%s%s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '  %s+%s %s\n' "$GREEN" "$OFF" "$1"; }
gone() { printf '  %s-%s %s\n' "$RED" "$OFF" "$1"; }
note() { printf '  %s%s%s\n' "$DIM" "$1" "$OFF"; }
fail() { printf '\n%sERROR:%s %s\n' "$RED" "$OFF" "$1" >&2; exit 1; }

usage() {
  cat <<EOF
antz installer

Usage: install.sh [options]

  --ref <ref>    git branch, tag or commit to install (default: $REF)
  --dir <path>   target agent dir (default: \$PI_CODING_AGENT_DIR or ~/.pi/agent)
  --uninstall    remove antz's files from the target and exit
  -h, --help     this text

Running from a checkout of $REPO copies that working tree; running the file on
its own (the curl one-liner) clones $REPO@<ref> to a temporary directory.
EOF
}

cleanup() {
  [ -n "$TMP" ] && rm -rf "$TMP"
  return 0
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    --ref)       [ $# -ge 2 ] || fail "--ref needs a value"; REF="$2"; shift 2 ;;
    --dir)       [ $# -ge 2 ] || fail "--dir needs a value"; DEST="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; fail "unknown option: $1" ;;
  esac
done

# Where this script's own tree is. Empty when piped into bash, which is exactly
# when the clone is needed.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

# The local checkout wins when there is one: installing a working tree is what
# makes an installer change testable before it is pushed.
resolve_source() {
  if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/agents" ] && [ -d "$SCRIPT_DIR/extensions" ]; then
    SOURCE="$SCRIPT_DIR"
    note "source: $SOURCE (working tree)"
    return
  fi
  command -v git >/dev/null 2>&1 || fail "git is required to fetch $REPO"
  TMP=$(mktemp -d)
  SOURCE="$TMP/src"
  note "source: https://github.com/$REPO @ $REF"
  mkdir -p "$SOURCE"
  # init+fetch+checkout instead of clone --branch: a branch, a tag and a bare
  # commit all resolve the same way.
  git -C "$SOURCE" init -q &&
    git -C "$SOURCE" remote add origin "https://github.com/$REPO.git" &&
    git -C "$SOURCE" fetch -q --depth 1 origin "$REF" &&
    git -C "$SOURCE" checkout -q FETCH_HEAD ||
    fail "could not fetch $REPO@$REF (check the ref and your network)"
}

# The `model:` line is the one thing the README tells the user to edit by hand,
# so it is the one thing a reinstall must not take away: upstream's file wins,
# the pin in it does not. The pin is read from the file that is about to be
# overwritten and put back afterwards — no state file, nothing to keep in sync.
local_pins() {
  local name file line
  for name in "${AGENTS[@]}"; do
    file="$DEST/agents/$name.md"
    [ -f "$file" ] || continue
    line=$(sed -n 's/^model:[[:space:]]*//p' "$file" | head -n 1)
    if [ -n "$line" ]; then
      printf '%s\t%s\n' "$name" "$line"
    fi
  done
  return 0
}

restore_pins() {
  local name model file
  while IFS=$'\t' read -r name model; do
    [ -n "$name" ] || continue
    file="$DEST/agents/$name.md"
    [ -f "$file" ] || continue
    awk -v pin="model: $model" '
      /^model:/ { if (!kept) { print pin; kept = 1 } next }
      { print }
      /^name:/  { if (!kept) { print pin; kept = 1 } }
    ' "$file" > "$file.antz-tmp" && mv "$file.antz-tmp" "$file" || {
      rm -f "$file.antz-tmp"
      fail "could not keep model: on agents/$name.md"
    }
    grep -q '^model:' "$file" || fail "model: did not survive on agents/$name.md"
    note "agents/$name.md keeps model: $model"
  done <<< "${1:-}"
}

install_antz() {
  command -v pi >/dev/null 2>&1 || fail "pi is not on PATH; antz is a pi workflow, install pi first"
  resolve_source

  step "Installing into $DEST"
  # mkdir -p first: ~/.pi/agent/agents/ does not exist by default and cp into a
  # missing directory fails.
  mkdir -p "$DEST/agents" "$DEST/extensions" "$DEST/prompts"
  local pins
  pins=$(local_pins)
  for dir in agents extensions prompts; do
    cp -R "$SOURCE/$dir/." "$DEST/$dir/"
    ok "$dir/"
  done
  restore_pins "$pins"

  step "Verifying"
  local missing=()
  local name
  for name in "${AGENTS[@]}"; do
    [ -f "$DEST/agents/$name.md" ] || missing+=("agents/$name.md")
  done
  [ -f "$DEST/prompts/$PROMPT.md" ] || missing+=("prompts/$PROMPT.md")
  [ -f "$DEST/extensions/$EXTENSION" ] || missing+=("extensions/$EXTENSION")

  if [ "${#missing[@]}" -ne 0 ]; then
    printf '%sERROR:%s install incomplete, missing:\n' "$RED" "$OFF" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi
  ok "${#AGENTS[@]} agents, $PROMPT.md, $EXTENSION"
  if [ -n "$pins" ]; then
    note "The rest of each agent file comes from $REPO. Drop a model: line and reinstall to reset it."
  fi

  step "Done"
  say "  Reload pi (${BOLD}/reload${OFF}) or restart it, then from inside any repo:"
  say "    ${BOLD}/antz \"what you want built\"${OFF}"
  if [ ! -f "$HOME/.agents/skills/${SKILLS[0]}/SKILL.md" ] && [ ! -f "$DEST/skills/${SKILLS[0]}/SKILL.md" ]; then
    note "The three skills are not part of this install; they are global and shared:"
    note "  npx skills add $REPO -g"
  fi
  note "The only thing antz writes outside .antz/ is docs/decisions/<slug>.md."
}

uninstall_antz() {
  step "Removing antz from $DEST"
  local name
  local removed=0
  for name in "${AGENTS[@]}"; do
    if [ -f "$DEST/agents/$name.md" ]; then
      rm -f "$DEST/agents/$name.md"; gone "agents/$name.md"; removed=1
    fi
  done
  for name in "${SKILLS[@]}"; do
    if [ -d "$DEST/skills/$name" ]; then
      rm -rf "$DEST/skills/$name"; gone "skills/$name/"; removed=1
    fi
  done
  for path in "prompts/$PROMPT.md" "extensions/$EXTENSION"; do
    if [ -f "$DEST/$path" ]; then
      rm -f "$DEST/$path"; gone "$path"; removed=1
    fi
  done

  step "Done"
  if [ "$removed" -eq 0 ]; then
    say "  Nothing of antz's was there."
  else
    say "  Reload pi (${BOLD}/reload${OFF}) to drop the tool and the /antz command."
    note "Left alone: anything else in $DEST, the shared skills in ~/.agents/skills, and every .antz/ and docs/decisions/ in your repos."
  fi
}

if [ "$UNINSTALL" -eq 1 ]; then
  uninstall_antz
else
  install_antz
fi

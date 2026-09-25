#!/usr/bin/env bash
# antz's installer engine: one implementation of fetch, splice, verify and
# uninstall for the three clients. Users never run this file; they run the
# wrapper next to an adapter's README, which calls it with its client name:
#
#   curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/adapters/pi/install.sh | bash
#   curl -fsSL .../adapters/claude/install.sh | bash
#   curl -fsSL .../adapters/opencode/install.sh | bash
#
# Nothing is read from stdin: under `curl | bash` stdin is the script.
#
# Nothing is built and nothing but the source tree is fetched. Only antz's own
# paths are written, so a reinstall is an upgrade and whatever else sits in the
# client's config dir survives both directions. The one thing a copy would
# otherwise clobber is the `model:` line the READMEs tell the user to pin by hand,
# so it is read from the file about to be overwritten and written back afterwards —
# no state file, nothing to keep in sync.
#
#   install.sh <pi|claude|opencode> [options]

set -euo pipefail

REPO="edezacas/antz"
REF="master"
NAME="install.sh"

# What antz owns. Anything else in these directories belongs to someone else.
AGENTS=(antz-scout antz-planner antz-tester antz-implementer antz-verifier)
SKILLS=(antz-clarify antz-tdd antz-architecture)
PROMPT="antz"
EXTENSION="antz-subagent.ts"

CLIENT=""
DEST=""
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
antz installer — client: ${CLIENT:-pi, claude or opencode}

Usage: $NAME <client> [options]

  --uninstall    remove antz's files from the client and exit
  -h, --help     this text

Each adapters/<client>/install.sh wrapper calls this with its own client name,
so <client> is normally already set.
EOF
  if [ "$CLIENT" = "pi" ]; then
    cat <<EOF

pi only:
  --ref <ref>    git branch, tag or commit to install (default: $REF)
  --dir <path>   target agent dir (default: \$PI_CODING_AGENT_DIR or ~/.pi/agent)
EOF
  fi
  cat <<EOF

Each client's target is the one it resolves itself: \$PI_CODING_AGENT_DIR or
~/.pi/agent, \$CLAUDE_CONFIG_DIR or ~/.claude, \$XDG_CONFIG_HOME/opencode.
Running from a checkout copies that working tree; running the file on its own
(the curl one-liner) clones $REPO@$REF to a temporary directory.

Each adapter's README, next to its wrapper, is the guide for that client.
EOF
}

cleanup() {
  [ -n "$TMP" ] && rm -rf "$TMP"
  return 0
}
trap cleanup EXIT

while [ $# -gt 0 ]; do
  case "$1" in
    pi|claude|opencode) [ -z "$CLIENT" ] || fail "client named twice: $1"; CLIENT="$1"; shift ;;
    --ref)       [ $# -ge 2 ] || fail "--ref needs a value"; REF="$2"; shift 2 ;;
    --dir)       [ $# -ge 2 ] || fail "--dir needs a value"; DEST="$2"; shift 2 ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; fail "unknown option: $1" ;;
  esac
done

[ -n "$CLIENT" ] || { usage >&2; fail "which client? pi, claude or opencode"; }

# --ref and --dir are pi's — the only client whose README documents a target and
# a ref. The other two resolve their own config dir from their own environment
# variable and install master.
if [ "$CLIENT" != "pi" ]; then
  [ "$REF" = "master" ] || fail "--ref is pi-only"
  [ -z "$DEST" ] || fail "--dir is pi-only; set \$CLAUDE_CONFIG_DIR or \$XDG_CONFIG_HOME instead"
fi

# The client's own config dir, the way that client resolves it — pi's setting
# would install where the extension never looks, and the same goes for the
# other two. The skills are not affected: they live in the shared ~/.agents/skills.
if [ -z "$DEST" ]; then
  case "$CLIENT" in
    pi)       DEST="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}" ;;
    claude)   DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" ;;
    opencode) DEST="${XDG_CONFIG_HOME:-$HOME/.config}/opencode" ;;
  esac
fi

# Where this script's own tree is. Empty when piped into bash, which is exactly
# when the clone is needed.
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

# The clashing case is a user who pinned a model by hand: the file is antz's,
# that line is theirs. It is read from the file about to be overwritten.
collect_pins() {
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

# Written back inside the frontmatter, wherever the client's block puts its
# last key, and replaced in place if the file already carried one.
restore_pins() {
  local name model file
  while IFS=$'\t' read -r name model; do
    [ -n "$name" ] || continue
    file="$DEST/agents/$name.md"
    [ -f "$file" ] || continue
    awk -v pin="model: $model" '
      NR == 1 && $0 == "---" { fm = 1 }
      fm && NR > 1 && $0 == "---" && !done { print pin; done = 1; fm = 0 }
      /^model:/ { if (!done) { print pin; done = 1 }; next }
      { print }
      END { if (!done) print pin }
    ' "$file" > "$file.antz-tmp" && mv "$file.antz-tmp" "$file" || {
      rm -f "$file.antz-tmp"
      fail "could not keep model: on agents/$name.md"
    }
    grep -q '^model:' "$file" || fail "model: did not survive on agents/$name.md"
    note "agents/$name.md keeps model: $model"
  done <<< "${1:-}"
}

# Everything after the second `---`, whatever the client's frontmatter grew to.
# The source files carry pi's block; the client's own comes from its adapter.
body() { awk 'n<2 && /^---$/ {n++; next} n>=2' "$1"; }

command_file() {
  if [ "$CLIENT" = "pi" ]; then
    printf '%s/prompts/%s.md' "$DEST" "$PROMPT"
  else
    printf '%s/commands/%s.md' "$DEST" "$PROMPT"
  fi
}

# The local checkout wins when there is one: installing a working tree is what
# makes an installer change testable before it is pushed.
resolve_source() {
  local root
  if [ -n "$SCRIPT_DIR" ]; then
    for root in "$SCRIPT_DIR" "$SCRIPT_DIR/.."; do
      if [ -d "$root/agents" ] && [ -f "$root/prompts/$PROMPT.md" ]; then
        SOURCE=$(cd "$root" && pwd)
        note "source: $SOURCE (working tree)"
        return
      fi
    done
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

write_agent() {
  local name="$1"
  {
    cat "$SOURCE/adapters/$CLIENT/frontmatter/$name.yaml"
    body "$SOURCE/agents/$name.md"
  } > "$DEST/agents/$name.md"
}

write_command() {
  local file
  file=$(command_file)
  case "$CLIENT" in
    claude)   cp "$SOURCE/prompts/$PROMPT.md" "$file" ;;
    opencode) grep -v '^argument-hint:' "$SOURCE/prompts/$PROMPT.md" > "$file" ;;
  esac
}

verify() {
  step "Verifying"
  local missing=()
  local name file
  for name in "${AGENTS[@]}"; do
    file="$DEST/agents/$name.md"
    if [ ! -f "$file" ]; then
      missing+=("agents/$name.md")
      continue
    fi
    # The body arrives byte for byte; only the frontmatter is the client's.
    diff -q <(body "$file") <(body "$SOURCE/agents/$name.md") >/dev/null \
      || missing+=("agents/$name.md (body differs)")
    case "$CLIENT" in
      claude)   grep -q "^name:[[:space:]]*$name\$" "$file" || missing+=("agents/$name.md (name: must match the filename)") ;;
      opencode) grep -q '^mode:[[:space:]]*subagent' "$file" || missing+=("agents/$name.md (mode: subagent)") ;;
    esac
  done

  file=$(command_file)
  if [ ! -f "$file" ]; then
    missing+=("${file#"$DEST/"}")
  elif [ "$CLIENT" = "claude" ]; then
    cmp -s "$SOURCE/prompts/$PROMPT.md" "$file" || missing+=("commands/$PROMPT.md (differs)")
  else
    diff -q <(body "$file") <(body "$SOURCE/prompts/$PROMPT.md") >/dev/null || missing+=("${file#"$DEST/"} (body differs)")
  fi

  if [ "$CLIENT" = "pi" ] && [ ! -f "$DEST/extensions/$EXTENSION" ]; then
    missing+=("extensions/$EXTENSION")
  fi

  if [ "${#missing[@]}" -ne 0 ]; then
    printf '%sERROR:%s install incomplete, missing:\n' "$RED" "$OFF" >&2
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
  fi
  ok "${#AGENTS[@]} agents, $PROMPT$( [ "$CLIENT" = "pi" ] && printf ', %s' "$EXTENSION" )"
}

install_antz() {
  if [ "$CLIENT" = "pi" ]; then
    command -v pi >/dev/null 2>&1 || fail "pi is not on PATH; antz is a pi workflow, install pi first"
  fi
  resolve_source

  step "Installing $CLIENT into $DEST"
  local pins
  pins=$(collect_pins)
  # mkdir -p first: none of these directories exists by default and cp into a
  # missing directory fails.
  mkdir -p "$DEST/agents"
  if [ "$CLIENT" = "pi" ]; then
    mkdir -p "$DEST/prompts" "$DEST/extensions"
    local dir
    for dir in agents prompts extensions; do
      cp -R "$SOURCE/$dir/." "$DEST/$dir/"
      ok "$dir/"
    done
  else
    mkdir -p "$DEST/commands"
    local name
    for name in "${AGENTS[@]}"; do
      write_agent "$name"
      ok "agents/$name.md"
    done
    write_command
    ok "commands/$PROMPT.md"
  fi
  restore_pins "$pins"

  verify

  step "Done"
  case "$CLIENT" in
    pi) say "  Reload pi (${BOLD}/reload${OFF}) or restart it, then from inside any repo:" ;;
    *)  say "  Start a new ${CLIENT} session, then from inside any repo:" ;;
  esac
  say "    ${BOLD}/antz \"what you want built\"${OFF}"
  if [ "$CLIENT" = "pi" ]; then
    note "Keep extensions/$EXTENSION: it is what makes the five agents dispatchable."
  fi
  if [ -n "$pins" ]; then
    note "The rest of each agent file comes from $REPO. Drop a model: line and reinstall to reset it."
  fi
  if [ ! -f "$HOME/.agents/skills/${SKILLS[0]}/SKILL.md" ] && [ ! -f "$DEST/skills/${SKILLS[0]}/SKILL.md" ]; then
    note "The three skills are not part of this install; they are global and shared:"
    note "  npx skills add $REPO -g"
  fi
  if [ "$CLIENT" = "pi" ]; then
    note "The only thing antz writes outside .antz/ is docs/decisions/<slug>.md."
  fi
}

uninstall_antz() {
  step "Removing $CLIENT from $DEST"
  local name path
  local removed=0
  for name in "${AGENTS[@]}"; do
    if [ -f "$DEST/agents/$name.md" ]; then
      rm -f "$DEST/agents/$name.md"; gone "agents/$name.md"; removed=1
    fi
  done
  if [ "$CLIENT" = "pi" ]; then
    # Legacy: the installer used to copy the skills here. They are global now,
    # so this only sweeps up what an older antz left behind.
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
  else
    path="commands/$PROMPT.md"
    if [ -f "$DEST/$path" ]; then
      rm -f "$DEST/$path"; gone "$path"; removed=1
    fi
  fi

  step "Done"
  if [ "$removed" -eq 0 ]; then
    say "  Nothing of antz's was there."
  else
    case "$CLIENT" in
      pi) say "  Reload pi (${BOLD}/reload${OFF}) to drop the tool and the /antz command." ;;
      *)  say "  Start a new session to drop the /antz command." ;;
    esac
    case "$CLIENT" in
      pi) note "Left alone: anything else in $DEST, the shared skills in ~/.agents/skills, and every .antz/ and docs/decisions/ in your repos." ;;
      *)  note "Left alone: anything else in $DEST, the skills npx skills linked, and every .antz/ and docs/decisions/ in your repos." ;;
    esac
  fi
}

if [ "$UNINSTALL" -eq 1 ]; then
  uninstall_antz
else
  install_antz
fi

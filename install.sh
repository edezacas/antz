#!/bin/sh
# Installs the antz agents (antz-specifier, antz-coder, antz-verifier) as
# native subagents for whichever of Claude Code / OpenCode are detected on
# this machine.
#
# Usage:
#   ./install.sh [--claude] [--opencode] [--all] [--check]
#   curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh
#
# With no flags, each client is installed only if it's detected (its CLI is
# on PATH, or its global config directory already exists). Pass a flag to
# force installing for a specific client regardless of detection. Pass
# --check to only report whether an update is available (and what changed),
# without installing anything.
#
# Source of truth: agents/prompts/<name>.prompt (role instructions, no
# client-specific syntax) + agents/meta/<name>.yaml (name/description/access).
# This script renders those into each client's native frontmatter format and
# writes them under that client's global agents directory.
#
# VERSION + CHANGELOG.md track changes to agents/prompts/ and agents/meta/.
# Each installed file's marker comment embeds the VERSION it was generated
# from, so re-running this script can detect an update and print the
# CHANGELOG.md entries the installed copy is missing.

set -eu

REPO_OWNER="edezacas"
REPO_NAME="antz"
REPO_BRANCH="master"
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$REPO_BRANCH"

AGENTS="specifier coder verifier"
MARKER="antz:generated"

usage() {
  echo "Usage: $0 [--claude] [--opencode] [--all] [--check]" >&2
}

want_claude=0
want_opencode=0
explicit=0
check_only=0

for arg in "$@"; do
  case "$arg" in
    --claude) want_claude=1; explicit=1 ;;
    --opencode) want_opencode=1; explicit=1 ;;
    --all) want_claude=1; want_opencode=1; explicit=1 ;;
    --check) check_only=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage; exit 1 ;;
  esac
done

if [ "$explicit" -eq 0 ]; then
  command -v claude >/dev/null 2>&1 && want_claude=1
  [ -d "$HOME/.claude" ] && want_claude=1
  command -v opencode >/dev/null 2>&1 && want_opencode=1
  [ -d "$HOME/.config/opencode" ] && want_opencode=1
fi

if [ "$want_claude" -eq 0 ] && [ "$want_opencode" -eq 0 ]; then
  echo "Neither Claude Code nor OpenCode detected. Nothing to install." >&2
  echo "Pass --claude, --opencode, or --all to force installation for a specific client." >&2
  exit 1
fi

# Resolve local repo root when running from inside a checkout of this repo,
# so a plain `./install.sh` doesn't need network access. Falls back to
# fetching each file from GitHub (needed for `curl | sh`).
LOCAL_ROOT=""
if [ -n "${0:-}" ] && [ -f "$0" ]; then
  script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || script_dir=""
  if [ -n "$script_dir" ] && [ -d "$script_dir/agents/prompts" ] && [ -d "$script_dir/agents/meta" ]; then
    LOCAL_ROOT="$script_dir"
  fi
fi
if [ -z "$LOCAL_ROOT" ] && [ -d "./agents/prompts" ] && [ -d "./agents/meta" ]; then
  LOCAL_ROOT=$(pwd)
fi

if [ -z "$LOCAL_ROOT" ] && ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to fetch agent definitions remotely (no local checkout found)." >&2
  exit 1
fi

fetch_file() {
  rel="$1"
  if [ -n "$LOCAL_ROOT" ]; then
    cat "$LOCAL_ROOT/$rel" || { echo "Failed to read local file: $LOCAL_ROOT/$rel" >&2; exit 1; }
  else
    curl -fsSL "$RAW_BASE/$rel" || { echo "Failed to fetch: $RAW_BASE/$rel" >&2; exit 1; }
  fi
}

meta_field() {
  # $1 = meta file content, $2 = key
  printf '%s\n' "$1" | sed -n "s/^$2: *//p" | head -n1
}

claude_tools_for_access() {
  case "$1" in
    readonly) printf 'Read, Grep, Glob, Bash' ;;
    readwrite) printf 'Read, Grep, Glob, Bash, Edit, Write' ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

opencode_edit_perm_for_access() {
  case "$1" in
    readonly) printf 'deny' ;;
    readwrite) printf 'allow' ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

render_claude() {
  # $1 name, $2 description, $3 access, $4 body, $5 version
  tools=$(claude_tools_for_access "$3")
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\nname: %s\ndescription: %s\ntools: %s\n---\n\n%s\n' \
    "$MARKER" "$5" "$1" "$2" "$tools" "$4"
}

render_opencode() {
  # $1 name (unused, filename carries it), $2 description, $3 access, $4 body, $5 version
  editperm=$(opencode_edit_perm_for_access "$3")
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: %s\nmode: subagent\npermission:\n  edit: %s\n---\n\n%s\n' \
    "$MARKER" "$5" "$2" "$editperm" "$4"
}

install_file() {
  # $1 destination path, $2 content
  dest="$1"
  content="$2"
  if [ -f "$dest" ] && ! grep -q "$MARKER" "$dest" 2>/dev/null; then
    ts=$(date +%Y%m%d%H%M%S)
    cp "$dest" "$dest.bak.$ts"
    echo "Backed up existing $dest -> $dest.bak.$ts (not antz-managed)"
  fi
  printf '%s' "$content" > "$dest"
  echo "Installed $dest"
}

installed_version_of() {
  # $1 = existing installed file path; prints the version embedded in its
  # marker comment, or nothing if the file doesn't exist or isn't antz-managed.
  f="$1"
  [ -f "$f" ] || return 0
  sed -n "s/.*$MARKER version=\([^ ]*\).*/\1/p" "$f" | head -n1
}

changelog_since() {
  # $1 = previously installed version, $2 = full CHANGELOG.md content.
  # Prints every entry newer than $1 (i.e. everything above its "## [x.y.z]"
  # heading). Prints nothing if that heading isn't found (e.g. old_version
  # predates changelog tracking, or content changed without a version bump).
  old_version="$1"
  content="$2"
  printf '%s\n' "$content" | awk -v old="[$old_version]" '
    /^## \[/ {
      if (index($0, old) > 0) { found = 1; exit }
      printing = 1
    }
    printing { print }
  '
}

# Report + (unless --check) install a single client's copy of one reference
# agent file, used to detect whether an update is available.
report_version() {
  # $1 = label, $2 = path to that client's specifier agent file, $3 = new version, $4 = changelog content
  label="$1"; ref_path="$2"; new_version="$3"; changelog="$4"
  old_version=$(installed_version_of "$ref_path")
  if [ -z "$old_version" ]; then
    echo "$label: fresh install of antz $new_version"
  elif [ "$old_version" = "$new_version" ]; then
    echo "$label: already up to date (antz $new_version)"
  else
    echo "$label: antz $old_version -> $new_version"
    entries=$(changelog_since "$old_version" "$changelog")
    [ -n "$entries" ] && printf '%s\n' "$entries"
  fi
}

version=$(fetch_file "VERSION" | tr -d ' \t\r\n')
changelog=$(fetch_file "CHANGELOG.md")

specifier_meta=$(fetch_file "agents/meta/specifier.yaml")
specifier_name=$(meta_field "$specifier_meta" name)

[ "$want_claude" -eq 1 ] && report_version "Claude Code" "$HOME/.claude/agents/$specifier_name.md" "$version" "$changelog"
[ "$want_opencode" -eq 1 ] && report_version "OpenCode" "$HOME/.config/opencode/agents/$specifier_name.md" "$version" "$changelog"

if [ "$check_only" -eq 1 ]; then
  exit 0
fi

for agent in $AGENTS; do
  meta_content=$(fetch_file "agents/meta/$agent.yaml")
  name=$(meta_field "$meta_content" name)
  description=$(meta_field "$meta_content" description)
  access=$(meta_field "$meta_content" access)
  body=$(fetch_file "agents/prompts/$agent.prompt")

  if [ "$want_claude" -eq 1 ]; then
    mkdir -p "$HOME/.claude/agents"
    content=$(render_claude "$name" "$description" "$access" "$body" "$version")
    install_file "$HOME/.claude/agents/$name.md" "$content"
  fi

  if [ "$want_opencode" -eq 1 ]; then
    mkdir -p "$HOME/.config/opencode/agents"
    content=$(render_opencode "$name" "$description" "$access" "$body" "$version")
    install_file "$HOME/.config/opencode/agents/$name.md" "$content"
  fi
done

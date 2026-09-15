#!/bin/sh
# Installs the antz agents (antz-specifier, antz-coder, antz-verifier, and
# antz-orchestrator) as native subagents for whichever of Claude Code /
# OpenCode / Pi are detected on this machine, along with the /antz command.
#
# Usage:
#   ./install.sh [--claude] [--opencode] [--pi] [--all] [--check]
#   curl -fsSL https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/edezacas/antz/v4.7.0/install.sh | ANTZ_REF=v4.7.0 sh
#
# ANTZ_REF pins the install source ref for remote (curl | sh) installs: to
# install from a tag, fetch install.sh from the tag's raw URL and pass
# ANTZ_REF=<tag> to sh (example above), so every file this script fetches is
# read from that same ref instead of master. The value is used verbatim --
# install.sh neither validates it nor assumes tag syntax, a branch name works
# the same way. Unset or empty, the documented default ref ("master") applies.
# ANTZ_REF governs only the remote fetch path: a local-checkout install reads
# every file from disk and never touches the network, with or without it.
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
# VERSION + CHANGELOG.md track changes to agents/prompts/, agents/meta/, and install.sh.
# Each installed file's marker comment embeds the VERSION it was generated
# from, so re-running this script can detect an update and print the
# CHANGELOG.md entries the installed copy is missing. A file counts as
# antz-managed only when it carries that marker as a line-start header
# comment ("# antz:generated ..."); a mention elsewhere is not ours.
#
# Backup policy: a pre-existing destination that is not antz-managed is
# backed up to "<file>.bak.<timestamp>" before being overwritten, so no user
# content is ever lost. install.sh never reads, renames, or deletes those
# backups, and never prunes them automatically -- accumulating them is
# accepted and cleaning them up is the user's job.

set -eu

REPO_OWNER="edezacas"
REPO_NAME="antz"
# The install source ref, derived from provenance rather than hardcoded:
# ANTZ_REF, when set non-empty, names the git ref (tag or branch) the fetched
# install.sh itself came from, and is used verbatim here at the RAW_BASE
# construction -- no validation, no tag-syntax assumption. Unset or empty, the
# documented default ref ("master") applies. This governs only the remote
# fetch path; a local-checkout install (LOCAL_ROOT) reads from disk and never
# consults RAW_BASE. See the ANTZ_REF note in the usage header above.
RAW_BASE="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/${ANTZ_REF:-master}"

AGENTS="specifier coder verifier orchestrator"
MARKER="antz:generated"

# The shared library directory the orchestration scripts install into, and
# the scripts themselves (change deembed-orchestration-scripts, libdirinstall):
# "${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts" -- resolved ONCE, at
# runtime, inside resolve_libdir(), never hardcoded, and shared by both
# clients (one libdir, not a per-client subdirectory). An empty
# XDG_CONFIG_HOME falls back exactly like an unset one.
LIBDIR_SUBPATH="antz/scripts"
SCRIPTS="antz-flow.sh"

resolve_libdir() {
  # Echoes the resolved absolute libdir, with no trailing slash. $HOME is
  # expanded here, by the shell running install.sh -- the fallback literal
  # never survives into anything written.
  cfg=${XDG_CONFIG_HOME:-}
  [ -n "$cfg" ] || cfg="$HOME/.config"
  printf '%s/%s\n' "${cfg%/}" "$LIBDIR_SUBPATH"
}

usage() {
  echo "Usage: $0 [--claude] [--opencode] [--pi] [--all] [--check]" >&2
}

want_claude=0
want_opencode=0
want_pi=0
explicit=0
check_only=0

for arg in "$@"; do
  case "$arg" in
    --claude) want_claude=1; explicit=1 ;;
    --opencode) want_opencode=1; explicit=1 ;;
    --pi) want_pi=1; explicit=1 ;;
    --all) want_claude=1; want_opencode=1; want_pi=1; explicit=1 ;;
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
  command -v pi >/dev/null 2>&1 && want_pi=1
  [ -d "$HOME/.pi/agent" ] && want_pi=1
fi

if [ "$want_claude" -eq 0 ] && [ "$want_opencode" -eq 0 ] && [ "$want_pi" -eq 0 ]; then
  echo "Neither Claude Code, OpenCode, nor Pi detected. Nothing to install." >&2
  echo "Pass --claude, --opencode, --pi, or --all to force installation for a specific client." >&2
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

yaml_quote_desc() {
  # $1 = raw single-line description text; prints it as a double-quoted
  # single-line YAML scalar: embedded backslashes are escaped first (so the
  # quote-escape's own backslash below is never double-escaped), then double
  # quotes. Undoing those two escapes left-to-right reproduces the value
  # byte-for-byte, so quoting never alters what a client reads.
  esc=$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '"%s"' "$esc"
}

claude_tools_for_access() {
  case "$1" in
    readonly) printf 'Read, Grep, Glob, Bash' ;;
    readwrite) printf 'Read, Grep, Glob, Bash, Edit, Write, Skill' ;;
    orchestrateonly) printf 'Read, Grep, Glob, Bash, Agent' ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

opencode_edit_perm_for_access() {
  case "$1" in
    readonly) printf 'deny' ;;
    readwrite) printf 'allow' ;;
    orchestrateonly) printf 'deny' ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

opencode_mode_for_access() {
  case "$1" in
    readonly) printf 'subagent' ;;
    readwrite) printf 'subagent' ;;
    orchestrateonly) printf 'primary' ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

opencode_task_perm_for_access() {
  # For readonly/readwrite: a plain scalar (they may never delegate at all).
  # For orchestrateonly: a glob-pattern-keyed object, deny-by-default, allowing
  # only the three role agents by exact name (last-match-wins) -- this is
  # real, runtime-enforced scoping on OpenCode, unlike Claude Code's plain
  # Agent grant (see CLAUDE.md Gotchas).
  case "$1" in
    readonly) printf 'deny' ;;
    readwrite) printf 'deny' ;;
    orchestrateonly)
      printf '\n    "*": deny\n    antz-specifier: allow\n    antz-coder: allow\n    antz-verifier: allow'
      ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

pi_tools_for_access() {
  # Pi's builtin tool names are lowercase (read/grep/find/ls/bash/edit/write),
  # not Claude Code's capitalized Glob/Grep. Nested delegation is authorized
  # by naming the pi-subagents `subagent` tool in the strict allowlist (see
  # pi-subagents docs/agents.md).
  #
  # orchestrateonly also names `edit, write`, which it must: pi-subagents
  # intersects a child's tool plan with the delegating session's available
  # builtins, so a readonly orchestrator would strip edit/write from the
  # readwrite roles it spawns (they would fall back to writing through bash).
  # These are pass-through grants, not a licence to write: the orchestrator's
  # "Never writes anything itself" is the same prompt-level boundary the
  # Claude Code render relies on for its unscoped `Agent` grant.
  case "$1" in
    readonly) printf 'read, grep, find, ls, bash' ;;
    readwrite) printf 'read, grep, find, ls, bash, edit, write' ;;
    orchestrateonly) printf 'read, grep, find, ls, bash, edit, write, subagent' ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

pi_inherit_skills_for_access() {
  # The Pi analogue of the Claude `Skill` grant: only the readwrite roles
  # carry a `## Skills` section and must see Pi's discovered skills catalog.
  # The orchestrator delegates skill discovery to those roles, so it mirrors
  # the readonly level here.
  case "$1" in
    readwrite) printf 'true' ;;
    readonly|orchestrateonly) printf 'false' ;;
    *) echo "Unknown access level: $1" >&2; exit 1 ;;
  esac
}

render_claude() {
  # $1 name, $2 description, $3 access, $4 body, $5 version
  tools=$(claude_tools_for_access "$3")
  desc=$(yaml_quote_desc "$2")
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\nname: %s\ndescription: %s\ntools: %s\n---\n\n%s\n' \
    "$MARKER" "$5" "$1" "$desc" "$tools" "$4"
}

render_opencode() {
  # $1 name (unused, filename carries it), $2 description, $3 access, $4 body, $5 version
  mode=$(opencode_mode_for_access "$3")
  editperm=$(opencode_edit_perm_for_access "$3")
  taskperm=$(opencode_task_perm_for_access "$3")
  desc=$(yaml_quote_desc "$2")
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: %s\nmode: %s\npermission:\n  edit: %s\n  task: %s\n---\n\n%s\n' \
    "$MARKER" "$5" "$desc" "$mode" "$editperm" "$taskperm" "$4"
}

render_pi() {
  # $1 name, $2 description, $3 access, $4 body, $5 version. Pi subagent
  # frontmatter (pi-subagents): an explicit lowercase tool allowlist, plus
  # the inheritance flags the roles' own prompts depend on --
  # inheritSkills (without it the `## Skills` catalog is a silent no-op for
  # the readwrite roles), inheritProjectContext (the target repo's
  # AGENTS.md/CLAUDE.md), replace mode (the role prompt is the whole system
  # prompt) and fresh context (no role may depend on the parent
  # conversation; state comes from disk).
  tools=$(pi_tools_for_access "$3")
  inherit_skills=$(pi_inherit_skills_for_access "$3")
  desc=$(yaml_quote_desc "$2")
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\nname: %s\ndescription: %s\ntools: %s\ninheritProjectContext: true\ninheritSkills: %s\nsystemPromptMode: replace\ndefaultContext: fresh\n---\n\n%s\n' \
    "$MARKER" "$5" "$1" "$desc" "$tools" "$inherit_skills" "$4"
}

render_claude_command() {
  # $1 version
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: Recommended entry point for antz. Delegates to the antz-orchestrator subagent, which runs one change in direct or spec mode.\nargument-hint: [request]\n---\n\nDelegate the user'"'"'s request verbatim to the antz-orchestrator subagent via the Agent tool: $ARGUMENTS\n' \
    "$MARKER" "$1"
}

render_opencode_command() {
  # $1 version
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: Recommended entry point for antz. Runs the antz-orchestrator agent, which runs one change in direct or spec mode.\nagent: antz-orchestrator\n---\n\n$ARGUMENTS\n' \
    "$MARKER" "$1"
}

render_pi_command() {
  # $1 version. Pi prompt templates (docs/prompt-templates.md) take an
  # optional description and argument-hint; the body runs in the invoking
  # main session, which delegates through the pi-subagents `subagent` tool.
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: Recommended entry point for antz. Delegates to the antz-orchestrator subagent, which runs one change in direct or spec mode.\nargument-hint: [request]\n---\n\nDelegate the user'"'"'s request verbatim to the antz-orchestrator subagent via the subagent tool: $ARGUMENTS\n' \
    "$MARKER" "$1"
}

backup_if_unmanaged() {
  # $1 = destination path. A pre-existing destination that is not
  # antz-managed is backed up to "<file>.bak.<timestamp>" before being
  # overwritten, so no user content is ever lost. Antz-managed detection is
  # anchored to the line-start header comment: a mid-line or mid-body
  # mention of the marker must not mark a user file as ours (it gets backed
  # up like any other file). install.sh never reads, renames, or deletes
  # those backups.
  dest="$1"
  if [ -f "$dest" ] && ! grep -q "^# $MARKER " "$dest" 2>/dev/null; then
    ts=$(date +%Y%m%d%H%M%S)
    cp "$dest" "$dest.bak.$ts"
    echo "Backed up existing $dest -> $dest.bak.$ts (not antz-managed)"
  fi
}

install_file() {
  # $1 destination path, $2 content
  dest="$1"
  content="$2"
  backup_if_unmanaged "$dest"
  printf '%s' "$content" > "$dest"
  echo "Installed $dest"
}

installed_version_of() {
  # $1 = existing installed file path; prints the version embedded in its
  # line-start header marker comment, or nothing if the file doesn't exist
  # or isn't antz-managed. Anchored like install_file's detection, so a
  # stale version mentioned in the file's body can't pass as installed.
  f="$1"
  [ -f "$f" ] || return 0
  sed -n "s/^# $MARKER version=\([^ ]*\).*/\1/p" "$f" | head -n1
}

# NL is a literal newline, used for exact byte surgery in
# install_libdir_script (parameter expansion, no external tools, nothing
# through a command substitution that would strip trailing newlines).
NL='
'

install_libdir_script() {
  # $1 = destination base name, $2 = the script source's exact bytes.
  # Byte-faithful install (libdirinstall-01): the installed file is the
  # source plus exactly one inserted line -- the antz:generated marker, as a
  # line-start header comment immediately after the "#!/bin/sh" shebang --
  # every other byte (including the source's trailing newline) untouched.
  # It goes through the same install_file, so the anchored marker detection
  # and the .bak.<ts> backup policy apply to libdir files unchanged
  # (libdirinstall-03).
  name="$1"
  src="$2"
  case "$src" in
    "#!/bin/sh$NL"*) ;;
    *)
      echo "Refusing to install $name: its source does not start with a '#!/bin/sh' shebang line." >&2
      exit 1
      ;;
  esac
  content="${src%%"$NL"*}$NL# $MARKER version=$version -- do not edit by hand; regenerate with install.sh$NL${src#*"$NL"}"
  install_file "$ANTZ_SCRIPTS_DIR/$name" "$content"
}

read_script_sources() {
  # libdirinstall-05 (one atomic pass): read or fetch the flow script source
  # into a variable BEFORE any destination file is written, so a failing
  # source aborts the whole install loudly (fetch_file's own error names the
  # unreadable file; a remote fetch honors ANTZ_REF through RAW_BASE) and
  # leaves the previous install -- client files and libdir -- completely
  # intact. The "; printf x" sentinel stripped on the next line preserves the
  # source's exact trailing bytes through command substitution; no heredoc
  # body sits inside the $( ) capture (posixsh-01).
  src_flow=$(fetch_file "scripts/orchestration/antz-flow.sh"; printf x)
  src_flow=${src_flow%x}
}

install_libdir_scripts() {
  # The libdir file (libdirinstall-01/06): written in the same single pass as
  # the client files (one invocation, no post-install step), into the one
  # shared client-independent libdir resolved once by resolve_libdir; every
  # invocation of the installed script is `sh "<resolved path>" <arguments>`
  # -- no exec bit installed or required, nothing added to PATH, no hook or
  # plugin. Its source was read or fetched before this runs
  # (read_script_sources; libdirinstall-05).
  mkdir -p "$ANTZ_SCRIPTS_DIR"
  install_libdir_script antz-flow.sh "$src_flow"
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
    # Any intervening CHANGELOG.md entries print at most once for the whole
    # report, never once per artifact line (libdirinstall-04).
    if [ "$changelog_shown" -eq 0 ]; then
      entries=$(changelog_since "$old_version" "$changelog")
      if [ -n "$entries" ]; then
        printf '%s\n' "$entries"
        changelog_shown=1
      fi
    fi
  fi
}

version=$(fetch_file "VERSION" | tr -d ' \t\r\n')
changelog=$(fetch_file "CHANGELOG.md")

specifier_meta=$(fetch_file "agents/meta/specifier.yaml")
specifier_name=$(meta_field "$specifier_meta" name)

# The shared scripts libdir, resolved once for this run (libdirinstall-02;
# decision 7: from XDG_CONFIG_HOME at runtime, never hardcoded, the concrete
# resolved absolute path is what any rendered body will carry). Resolution
# writes nothing: --check must create no libdir.
ANTZ_SCRIPTS_DIR=$(resolve_libdir)

# The CHANGELOG interval between the installed and current VERSION belongs
# to the whole report, never to each artifact line (libdirinstall-04).
changelog_shown=0

[ "$want_claude" -eq 1 ] && report_version "Claude Code" "$HOME/.claude/agents/$specifier_name.md" "$version" "$changelog"
[ "$want_opencode" -eq 1 ] && report_version "OpenCode" "$HOME/.config/opencode/agents/$specifier_name.md" "$version" "$changelog"
[ "$want_pi" -eq 1 ] && report_version "Pi" "$HOME/.pi/agent/agents/$specifier_name.md" "$version" "$changelog"

# The same three outcomes for each installed script artifact, keyed off its
# own marker version, after the per-client report lines (libdirinstall-04).
for script in $SCRIPTS; do
  report_version "$script" "$ANTZ_SCRIPTS_DIR/$script" "$version" "$changelog"
done

if [ "$check_only" -eq 1 ]; then
  exit 0
fi

# One atomic pass (libdirinstall-05): every script source is read or fetched
# NOW, before any destination below is written.
read_script_sources

for agent in $AGENTS; do
  meta_content=$(fetch_file "agents/meta/$agent.yaml")
  name=$(meta_field "$meta_content" name)
  description=$(meta_field "$meta_content" description)
  access=$(meta_field "$meta_content" access)
  body=$(fetch_file "agents/prompts/$agent.prompt")

  # The orchestrator prompt carries the "__ANTZ_SCRIPTS_DIR__" placeholder
  # token at every installed-script path position (it is dollar-digit-free
  # and carries no $ARGUMENTS sequence, so client command-body templating
  # cannot corrupt it). Substitute the concrete resolved libdir -- resolved
  # once above by resolve_libdir, no trailing slash -- so no placeholder
  # ever survives a rendered or installed file. Bodies that never carry the
  # token pass through untouched; the command renderers interpolate the same
  # resolved path directly at render time.
  body=$(printf '%s\n' "$body" | sed "s|__ANTZ_SCRIPTS_DIR__|$ANTZ_SCRIPTS_DIR|g")

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

  if [ "$want_pi" -eq 1 ]; then
    mkdir -p "$HOME/.pi/agent/agents"
    content=$(render_pi "$name" "$description" "$access" "$body" "$version")
    install_file "$HOME/.pi/agent/agents/$name.md" "$content"
  fi
done

if [ "$want_claude" -eq 1 ]; then
  mkdir -p "$HOME/.claude/commands"
  install_file "$HOME/.claude/commands/antz.md" "$(render_claude_command "$version")"
fi

if [ "$want_opencode" -eq 1 ]; then
  mkdir -p "$HOME/.config/opencode/commands"
  install_file "$HOME/.config/opencode/commands/antz.md" "$(render_opencode_command "$version")"
fi

if [ "$want_pi" -eq 1 ]; then
  mkdir -p "$HOME/.pi/agent/prompts"
  install_file "$HOME/.pi/agent/prompts/antz.md" "$(render_pi_command "$version")"
fi

# The orchestration script installs in the same pass (libdirinstall-01/06).
install_libdir_scripts

#!/bin/sh
# Installs the antz agents (antz-specifier, antz-coder, antz-verifier, and
# antz-orchestrator) as native subagents for whichever of Claude Code /
# OpenCode are detected on this machine, along with the /antz and
# /antz-set-model commands.
#
# Usage:
#   ./install.sh [--claude] [--opencode] [--all] [--check]
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
SCRIPTS="antz-flow.sh antz-probe.sh antz-set-model.sh"

resolve_libdir() {
  # Echoes the resolved absolute libdir, with no trailing slash. $HOME is
  # expanded here, by the shell running install.sh -- the fallback literal
  # never survives into anything written.
  cfg=${XDG_CONFIG_HOME:-}
  [ -n "$cfg" ] || cfg="$HOME/.config"
  printf '%s/%s\n' "${cfg%/}" "$LIBDIR_SUBPATH"
}

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

render_claude_command() {
  # $1 version
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: Recommended entry point for antz. Delegates to the antz-orchestrator subagent, which sequences specifier -> coder -> verifier for one change.\nargument-hint: [request]\n---\n\nDelegate the user'"'"'s request verbatim to the antz-orchestrator subagent via the Agent tool: $ARGUMENTS\n' \
    "$MARKER" "$1"
}

render_opencode_command() {
  # $1 version
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: Recommended entry point for antz. Runs the antz-orchestrator agent, which sequences specifier -> coder -> verifier for one change.\nagent: antz-orchestrator\n---\n\n$ARGUMENTS\n' \
    "$MARKER" "$1"
}

# Emits the COMPLETE bytes of the installed antz-set-model.sh (the third
# libdir file): the "#!/bin/sh" shebang, then the antz:generated marker as a
# line-start header comment immediately after it (the marker-in-scripts
# contract, carrying install.sh's own $MARKER and $version), then the script
# body. install_libdir_scripts redirects this straight into the libdir
# destination -- plain redirection, no command-substitution capture
# (setmodeldeembed-03). The emitted file is standalone, never templated by
# any client, so the body may use positional parameters freely: the client
# arrives as the script's first positional argument (each per-client
# /antz-set-model command body passes its own; the user never supplies one)
# and selects the agents directory. $HOME inside the body is a literal
# token resolved at edit time by the shell running the script, not by
# install.sh.
emit_set_model_script() {
  printf '#!/bin/sh\n# %s version=%s -- do not edit by hand; regenerate with install.sh\n' "$MARKER" "$version"
  cat <<'SCRIPT'
set -eu

MARKER="antz:generated"
VALID_AGENTS="specifier coder verifier orchestrator"

usage() {
  echo "Usage: /antz-set-model --agent <specifier|coder|verifier|orchestrator> (--model <value>|--clear)" >&2
}

# The first positional argument names the client this invocation serves --
# claude or opencode. It selects the agents directory the editor works in
# and the client name the messages print. A missing or unknown client is a
# usage error naming both valid values, and nothing is written.
case "${1:-}" in
  claude)
    CLIENT=claude
    AGENTS_DIR="$HOME/.claude/agents"
    ;;
  opencode)
    CLIENT=opencode
    AGENTS_DIR="$HOME/.config/opencode/agents"
    ;;
  *)
    echo "Error: the first argument must be the client: claude or opencode." >&2
    usage
    exit 1
    ;;
esac
shift

agent=""
model_value=""
have_model=0
have_clear=0

# Flag values are captured through a pending-flag state machine over a
# plain for-loop.
pending=""
for arg do
  if [ -n "$pending" ]; then
    case "$pending" in
      agent) agent="$arg" ;;
      model) have_model=1; model_value="$arg" ;;
    esac
    pending=""
    continue
  fi
  case "$arg" in
    --agent) pending=agent ;;
    --model) pending=model ;;
    --clear) have_clear=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -n "$pending" ]; then
  case "$pending" in
    agent) echo "Error: --agent requires a value." >&2 ;;
    model) echo "Error: --model requires a value." >&2 ;;
  esac
  usage
  exit 1
fi

if [ -z "$agent" ]; then
  echo "Error: --agent is required." >&2
  usage
  exit 1
fi

case " $VALID_AGENTS " in
  *" $agent "*) ;;
  *)
    echo "Error: unknown agent '$agent'. Must be one of: $VALID_AGENTS." >&2
    usage
    exit 1
    ;;
esac

if [ "$have_model" -eq 1 ] && [ "$have_clear" -eq 1 ]; then
  echo "Error: --model and --clear are mutually exclusive; use exactly one." >&2
  usage
  exit 1
fi

if [ "$have_model" -eq 0 ] && [ "$have_clear" -eq 0 ]; then
  echo "Error: exactly one of --model/--clear is required." >&2
  usage
  exit 1
fi

dest="$AGENTS_DIR/antz-$agent.md"

if [ ! -f "$dest" ]; then
  echo "Error: antz-$agent is not installed for $CLIENT yet (no file at $dest); install it first, e.g. ./install.sh --$CLIENT. No file was written." >&2
  exit 1
fi

# Managed-file detection is anchored to the line-start header comment
# "# antz:generated ..." -- the same header-marker contract install.sh's own
# install_file/installed_version_of reads apply. A file that merely mentions
# the marker string mid-body (or with leading indentation) is not
# antz-managed: it is refused here, untouched.
if ! grep -q "^# $MARKER " "$dest" 2>/dev/null; then
  echo "Error: $dest is not antz-managed (missing the '$MARKER' marker); refusing to modify it. No file was written." >&2
  exit 1
fi

if [ "$have_clear" -eq 1 ] && ! grep -q '^model:' "$dest" 2>/dev/null; then
  echo "antz-$agent ($CLIENT) has no model configured; nothing to clear. $dest is unchanged."
  exit 0
fi

if [ "$have_model" -eq 1 ]; then
  newline="model: $model_value"
  insert=1
else
  newline=""
  insert=0
fi

# The rewrite loop mirrors the retired awk version, but reads lines into a
# variable instead of awk's whole-line positional: drop any "model:" line
# inside the frontmatter (between the first two "---" lines), and optionally
# insert the new model line directly after the "description:" line.
tmp=$(mktemp)
# The scratch file is removed on EVERY exit path -- success, the
# nothing-to-clear no-op (which never reaches the mktemp above), and a
# mid-run failure (set -e exits, e.g. the target turned read-only so the
# rewrite's write fails): the trap is set the moment the scratch exists and
# removes exactly that file -- never the target, never a backup.
trap 'rm -f "$tmp"' EXIT
dashes=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$line" = "---" ]; then
    dashes=$((dashes + 1))
    printf '%s\n' "$line"
    continue
  fi
  if [ "$dashes" -eq 1 ]; then
    case "$line" in
      model:*)
        continue
        ;;
      description:*)
        printf '%s\n' "$line"
        if [ "$insert" -eq 1 ]; then
          printf '%s\n' "$newline"
        fi
        continue
        ;;
    esac
  fi
  printf '%s\n' "$line"
done < "$dest" > "$tmp"
cat "$tmp" > "$dest"

if [ "$have_model" -eq 1 ]; then
  echo "antz-$agent ($CLIENT) now has model: $model_value ($dest)"
else
  echo "Cleared the model for antz-$agent ($CLIENT); $dest no longer has a model: line."
fi
SCRIPT
}

set_model_flow_head() {
  # Emits the client-independent part of the /antz-set-model command body:
  # argument validation (fail fast), the non-interactive bypass, and the
  # interactive path's pre-flight. Everything here happens BEFORE any
  # question is asked, so a doomed request is refused without ever asking
  # the user anything (see the Ordering contract in
  # spdd/changes/set-model-interactive-picker/README.md). __CLIENT__ and
  # __AGENTS_PATH__ are substituted per client by render_set_model_command.
  cat <<'FLOWHEAD'
Arguments: $ARGUMENTS

This command does not delegate to any of the four antz-* subagents -- perform every step below yourself, in this session, using your own Bash tool wherever a shell command is called for.

Step 1 -- Validate the arguments, before asking any question. Accepted arguments: `--agent <specifier|coder|verifier|orchestrator>` (required), plus AT MOST one of `--model <value>` / `--clear`. Each of the following is a usage error: an unknown agent name (must be one of specifier, coder, verifier, orchestrator); a missing `--agent` (including an entirely empty invocation); `--agent` or `--model` given without its value; both `--model` and `--clear` given; unknown options or otherwise malformed arguments. On a usage error: refuse with the specific reason, without asking any question, without running the script, and without writing any file.

Step 2 -- Non-interactive bypass. If `--model <value>` or `--clear` WAS given, never ask anything: run the installed script (the invocation line at the end of this command) with the arguments exactly as given after its fixed client argument, then reply to the user using exactly what the script printed (on failure, the script's own refusal message and the fact that no file was written are the reply).

Step 3 -- Pre-flight. Only when neither `--model` nor `--clear` was given; still strictly before asking any question:
- Confirm the target file `__AGENTS_PATH__/antz-<agent>.md` exists and carries the `antz:generated` marker. If it does not exist, refuse with the failure reason: antz-<agent> must be installed for __CLIENT__ first (e.g. via install.sh). If it exists but does not carry the marker, refuse: the file is not antz-managed. Either way, refuse without asking any question and without writing anything.
- Read the file's current frontmatter `model:` line: the value after `model: `, or note that none is configured.
FLOWHEAD
}

set_model_flow_tail() {
  # Emits the shared apply/relay instructions that close the /antz-set-model
  # command body: how the picker's outcome reaches the installed script (the
  # libdir's antz-set-model.sh, invoked by its concrete resolved path with
  # the copy's own client as the first argument), and the rule that the
  # reply is exactly what the script printed. __CLIENT__ and
  # __SET_MODEL_PATH__ are substituted per client by
  # render_set_model_command.
  cat <<'FLOWTAIL'
Step 5 -- Apply the answer, then reply. Never invoke the script without exactly one of `--model`/`--clear`: the only two valid invocations are `--agent <agent> --model <chosen>` and `--agent <agent> --clear`.
- If the user dismissed the question, or answered with an empty value: cancel -- never run the script, write nothing, and reply that nothing was changed.
- If the user chose the `Revert to default (clear)` option: run the script with `--agent <agent> --clear`.
- Otherwise: run the script with `--agent <agent> --model <chosen>`, passing the chosen value verbatim -- never validated or translated, including free-form answers.

The script is the installed file at `__SET_MODEL_PATH__`, and its first argument is always the client this command serves: run it as `sh "__SET_MODEL_PATH__" __CLIENT__` followed by the chosen flags (e.g. `sh "__SET_MODEL_PATH__" __CLIENT__ --agent coder --model opus`). Then reply to the user using exactly what the script printed: on success, which file changed and what its `model:` line now is (or that it was cleared); on failure, the specific reason and that no file was written. Do not reinterpret, add to, or omit that message.
FLOWTAIL
}

render_set_model_command() {
  # $1 = client ("claude" or "opencode"), $2 = version. Renders the
  # /antz-set-model command file for that client: unlike /antz, this command
  # never delegates to any antz-* subagent -- its body instructs the
  # invoking session to validate, pre-flight, then either run the installed
  # script directly (explicit --model/--clear) or ask the user which model
  # to assign via that client's native question mechanism and feed the
  # chosen value to the same script as --model (the interactive picker; the
  # no-flag form). Each rendered copy is scoped to exactly one client (see
  # README Client binding); the two bodies never mention the other client's
  # directory or frontmatter position. The command body embeds no script:
  # the run instruction invokes the installed libdir file by its concrete
  # resolved path with the copy's client as the first argument
  # (setmodeldeembed-02), and the script itself is unchanged by the picker:
  # the interactive flow is only a new way to PRODUCE the --model value.
  client="$1"
  version="$2"

  case "$client" in
    claude)
      short_desc='Configure or clear an installed antz agent'"'"'s model in Claude Code. Omitting --model/--clear opens an interactive model picker; the explicit flags edit the target file directly in this session; never delegates to a subagent.'
      intro='Configure or clear the model: line in an already-installed Claude Code antz agent file'"'"'s frontmatter (`~/.claude/agents/antz-<agent>.md`).'
      extra_frontmatter='argument-hint: --agent <specifier|coder|verifier|orchestrator> [--model <value>|--clear]
'
      agents_path='$HOME/.claude/agents'
      # No runtime model enumeration exists on Claude Code: the option source
      # is this install-time-embedded documented alias vocabulary
      # (https://code.claude.com/docs/es/model-config), refreshed only by
      # re-running install.sh. AskUserQuestion hard-caps explicit options at
      # 4 per question (with a built-in free-text row), so the explicit set
      # is the three stable family aliases plus the mandated clear option;
      # the rest of the vocabulary is named verbatim in the question text so
      # free-form entry of it carries no typo risk.
      picker=$(emit_picker_claude)
      ;;
    opencode)
      short_desc='Configure or clear an installed antz agent'"'"'s model in OpenCode. Omitting --model/--clear opens an interactive model picker; the explicit flags edit the target file directly in this session; never delegates to a subagent.'
      intro='Configure or clear the model: line in an already-installed OpenCode antz agent file'"'"'s frontmatter (`~/.config/opencode/agents/antz-<agent>.md`).'
      extra_frontmatter=''
      agents_path='$HOME/.config/opencode/agents'
      # The option source is enumerated at invocation time via `opencode
      # models`; no catalog is embedded. Presentation trimming is
      # prompt-level guidance only, and the free-form and clear options must
      # always remain offered so no value is unreachable. There is an
      # EXPLICIT free-form option here (no built-in free-text row is
      # assumed), and the picker degrades to free-form + clear when the
      # enumeration fails or returns nothing.
      picker=$(emit_picker_opencode)
      ;;
    *) echo "Unknown client: $client" >&2; exit 1 ;;
  esac

  flow_head=$(set_model_flow_head | sed "s|__CLIENT__|$client|; s|__AGENTS_PATH__|$agents_path|")
  # The tail names the installed script's concrete resolved path and this
  # copy's client -- the single run instruction of a body that embeds no
  # script (setmodeldeembed-02).
  set_model_path="$ANTZ_SCRIPTS_DIR/antz-set-model.sh"
  flow_tail=$(set_model_flow_tail | sed "s|__CLIENT__|$client|g; s|__SET_MODEL_PATH__|$set_model_path|g")

  body=$(printf '%s\n\n%s\n\n%s\n\n%s\n' \
    "$intro" "$flow_head" "$picker" "$flow_tail")

  desc=$(yaml_quote_desc "$short_desc")
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: %s\n%s---\n\n%s\n' \
    "$MARKER" "$version" "$desc" "$extra_frontmatter" "$body"
}

# The two picker paragraphs below live in their own top-level, no-argument
# emitter functions -- instead of being written inline as heredocs captured
# by command substitutions inside render_set_model_command's case branches --
# because bash 3.2 (macOS /bin/sh in POSIX mode) mis-parses a heredoc whose
# body sits inside $( ... ) (see change fix-install-sh-syntax, posixsh-01).
# Capturing a function's stdout inside $(...) is plain POSIX and parses under
# bash 3.2. The bodies are verbatim: relocating them must not change the
# rendered command files byte-for-byte (posixsh-04).
emit_picker_claude() {
  cat <<'PICKER'
Step 4 -- Ask the user which model to assign to antz-<agent>, via `AskUserQuestion` in this session (it is a main-session tool; never from or via a subagent). Ask ONE question. Its text must state the current state from Step 3 -- either "the currently configured model is <value>" or "no model is currently configured" -- and, when the current value exactly equals one of the offered options' value strings, that option is marked as the current one; otherwise no option is marked. Offer exactly these explicit options, in this order:
1. `sonnet`
2. `opus`
3. `haiku`
4. `Revert to default (clear)` -- choosing it runs the script with `--clear`
`AskUserQuestion` automatically appends a built-in free-text row, so the user can enter any other value via free-form input; do not spend an option slot on a separate "type another value" entry. Also name these further documented alias values verbatim in the question text, so they can be entered via free-form input without typo risk: `best`, `fable`, `sonnet[1m]`, `opus[1m]`, `opusplan`.

The full documented alias vocabulary (source: https://code.claude.com/docs/es/model-config) is embedded in this command at install time: `best`, `fable`, `opus`, `sonnet`, `haiku`, `sonnet[1m]`, `opus[1m]`, `opusplan`. This list is embedded and refreshed only by re-running install.sh; it is never queried at runtime.
PICKER
}

emit_picker_opencode() {
  cat <<'PICKER'
Step 4 -- Ask the user which model to assign to antz-<agent>, via the session's `question` tool. First, enumerate the available models at invocation time: run `opencode models` via the Bash tool; its output lists `provider/model` ids (for example `anthropic/claude-opus-4-5`). No model catalog is embedded in this command. Offer the enumerated `provider/model` ids as the question options; when the catalog is too large to present in one question, you may filter, group, or paginate the presentation sensibly (for example, the current session provider's models first) -- but the free-form option and the revert-to-default (clear) option must always remain offered, so no value is unreachable. If `opencode models` fails or returns no model ids, degrade instead of failing: still ask the question, with the question text stating that no models could be enumerated, offering only the free-form option and the revert-to-default (clear) option.

Alongside any enumerated ids, ALWAYS offer an explicit `Type another value` free-form option (the `question` tool has no built-in free-text row) and the `Revert to default (clear)` option (choosing it runs the script with `--clear`). The question text must state the current state from Step 3 -- either "the currently configured model is <value>" or "no model is currently configured" -- and, when the current value exactly equals one of the offered options' value strings, that option is marked as the current one; otherwise no option is marked. A free-form answer is passed to the script verbatim, never validated or translated.
PICKER
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
  # libdirinstall-05 (one atomic pass): read or fetch the two on-disk
  # script sources into variables BEFORE any destination file is written, so
  # a failing source aborts the whole install loudly (fetch_file's own error
  # names the unreadable file; a remote fetch honors ANTZ_REF through
  # RAW_BASE) and leaves the previous install -- client files and libdir --
  # completely intact. The "; printf x" sentinel stripped on the next line
  # preserves each source's exact trailing bytes through command
  # substitution; no heredoc body sits inside these $( ) captures
  # (posixsh-01). The set-model script has no external source to read: its
  # text is static content of install.sh itself, written straight to the
  # libdir file by emit_set_model_script's redirection at install time
  # (setmodeldeembed-03).
  src_flow=$(fetch_file "scripts/orchestration/antz-flow.sh"; printf x)
  src_flow=${src_flow%x}
  src_probe=$(fetch_file "scripts/orchestration/antz-probe.sh"; printf x)
  src_probe=${src_probe%x}
}

install_libdir_scripts() {
  # The three libdir files (libdirinstall-01/06): written in the same single
  # pass as the client files (one invocation, no post-install step), into the
  # one shared client-independent libdir resolved once by resolve_libdir;
  # every invocation of an installed script is `sh "<resolved path>"
  # <arguments>` -- no exec bit installed or required, nothing added to
  # PATH, no hook or plugin. The two on-disk sources were both read or
  # fetched before this runs (read_script_sources; libdirinstall-05). The
  # set-model script goes through the same backup-if-unmanaged rule and
  # "Installed" message as every other file, but its text is redirected
  # straight from its emitter into the destination -- plain redirection, no
  # command-substitution capture (setmodeldeembed-03).
  mkdir -p "$ANTZ_SCRIPTS_DIR"
  install_libdir_script antz-flow.sh "$src_flow"
  install_libdir_script antz-probe.sh "$src_probe"
  dest="$ANTZ_SCRIPTS_DIR/antz-set-model.sh"
  backup_if_unmanaged "$dest"
  emit_set_model_script > "$dest"
  echo "Installed $dest"
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
done

if [ "$want_claude" -eq 1 ]; then
  mkdir -p "$HOME/.claude/commands"
  install_file "$HOME/.claude/commands/antz.md" "$(render_claude_command "$version")"
  install_file "$HOME/.claude/commands/antz-set-model.md" "$(render_set_model_command claude "$version")"
fi

if [ "$want_opencode" -eq 1 ]; then
  mkdir -p "$HOME/.config/opencode/commands"
  install_file "$HOME/.config/opencode/commands/antz.md" "$(render_opencode_command "$version")"
  install_file "$HOME/.config/opencode/commands/antz-set-model.md" "$(render_set_model_command opencode "$version")"
fi

# The three orchestration scripts install in the same pass (libdirinstall-01/06).
install_libdir_scripts

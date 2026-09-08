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

AGENTS="specifier coder verifier orchestrator"
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
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\nname: %s\ndescription: %s\ntools: %s\n---\n\n%s\n' \
    "$MARKER" "$5" "$1" "$2" "$tools" "$4"
}

render_opencode() {
  # $1 name (unused, filename carries it), $2 description, $3 access, $4 body, $5 version
  mode=$(opencode_mode_for_access "$3")
  editperm=$(opencode_edit_perm_for_access "$3")
  taskperm=$(opencode_task_perm_for_access "$3")
  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: %s\nmode: %s\npermission:\n  edit: %s\n  task: %s\n---\n\n%s\n' \
    "$MARKER" "$5" "$2" "$mode" "$editperm" "$taskperm" "$4"
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

set_model_script() {
  # $1 = client ("claude" or "opencode"). Emits the self-contained POSIX sh
  # script embedded verbatim in that client's installed /antz-set-model
  # command body. A client session runs this script (via its own Bash tool)
  # to add, replace, or remove one already-installed agent file's "model:"
  # frontmatter line -- the same deterministic file-editing contract the
  # retired set-model.sh implemented, but permanently bound to one client
  # (no --claude/--opencode flag; see README Client binding). $HOME below is
  # left as a literal token in the emitted script, resolved by the shell
  # that later runs it, not by install.sh.
  client="$1"
  case "$client" in
    claude) agents_dir='$HOME/.claude/agents' ;;
    opencode) agents_dir='$HOME/.config/opencode/agents' ;;
    *) echo "Unknown client: $1" >&2; exit 1 ;;
  esac
  script=$(cat <<'SCRIPT'
#!/bin/sh
set -eu

MARKER="antz:generated"
VALID_AGENTS="specifier coder verifier orchestrator"
CLIENT="__CLIENT__"
AGENTS_DIR="__AGENTS_DIR__"

usage() {
  echo "Usage: /antz-set-model --agent <specifier|coder|verifier|orchestrator> (--model <value>|--clear)" >&2
}

agent=""
model_value=""
have_model=0
have_clear=0

while [ $# -gt 0 ]; do
  case "$1" in
    --agent)
      if [ $# -lt 2 ]; then
        echo "Error: --agent requires a value." >&2
        usage
        exit 1
      fi
      agent="$2"
      shift 2
      ;;
    --model)
      if [ $# -lt 2 ]; then
        echo "Error: --model requires a value." >&2
        usage
        exit 1
      fi
      have_model=1
      model_value="$2"
      shift 2
      ;;
    --clear)
      have_clear=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

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

if ! grep -q "$MARKER" "$dest" 2>/dev/null; then
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

tmp=$(mktemp)
awk -v newline="$newline" -v insert="$insert" '
  BEGIN { dashes = 0 }
  {
    if ($0 == "---") {
      dashes++
      print
      next
    }
    if (dashes == 1 && $0 ~ /^model:/) {
      next
    }
    print
    if (dashes == 1 && insert == 1 && $0 ~ /^description:/) {
      print newline
    }
  }
' "$dest" > "$tmp"
cat "$tmp" > "$dest"
rm -f "$tmp"

if [ "$have_model" -eq 1 ]; then
  echo "antz-$agent ($CLIENT) now has model: $model_value ($dest)"
else
  echo "Cleared the model for antz-$agent ($CLIENT); $dest no longer has a model: line."
fi
SCRIPT
)
  printf '%s\n' "$script" | sed "s|__CLIENT__|$client|; s|__AGENTS_DIR__|$agents_dir|"
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

Step 2 -- Non-interactive bypass. If `--model <value>` or `--clear` WAS given, never ask anything: run the script below with the arguments exactly as given, then reply to the user using exactly what the script printed (on failure, the script's own refusal message and the fact that no file was written are the reply).

Step 3 -- Pre-flight. Only when neither `--model` nor `--clear` was given; still strictly before asking any question:
- Confirm the target file `__AGENTS_PATH__/antz-<agent>.md` exists and carries the `antz:generated` marker. If it does not exist, refuse with the failure reason: antz-<agent> must be installed for __CLIENT__ first (e.g. via install.sh). If it exists but does not carry the marker, refuse: the file is not antz-managed. Either way, refuse without asking any question and without writing anything.
- Read the file's current frontmatter `model:` line: the value after `model: `, or note that none is configured.
FLOWHEAD
}

set_model_flow_tail() {
  # Emits the shared apply/relay instructions that close the /antz-set-model
  # command body: how the picker's outcome reaches the embedded script, and
  # the rule that the reply is exactly what the script printed.
  cat <<'FLOWTAIL'
Step 5 -- Apply the answer, then reply. Never invoke the script without exactly one of `--model`/`--clear`: the only two valid invocations are `--agent <agent> --model <chosen>` and `--agent <agent> --clear`.
- If the user dismissed the question, or answered with an empty value: cancel -- never run the script, write nothing, and reply that nothing was changed.
- If the user chose the `Revert to default (clear)` option: run the script with `--agent <agent> --clear`.
- Otherwise: run the script with `--agent <agent> --model <chosen>`, passing the chosen value verbatim -- never validated or translated, including free-form answers.

Run the script by saving it below to a temp file and invoking it with `sh <tempfile>` (e.g. `sh /tmp/antz-set-model.sh --agent coder --model opus`). Then reply to the user using exactly what the script printed: on success, which file changed and what its `model:` line now is (or that it was cleared); on failure, the specific reason and that no file was written. Do not reinterpret, add to, or omit that message.
FLOWTAIL
}

render_set_model_command() {
  # $1 = client ("claude" or "opencode"), $2 = version. Renders the
  # /antz-set-model command file for that client: unlike /antz, this command
  # never delegates to any antz-* subagent -- its body instructs the
  # invoking session to validate, pre-flight, then either run the embedded
  # script directly (explicit --model/--clear) or ask the user which model
  # to assign via that client's native question mechanism and feed the
  # chosen value to the same script as --model (the interactive picker; the
  # no-flag form). Each rendered copy is scoped to exactly one client (see
  # README Client binding); the two bodies never mention the other client's
  # directory or frontmatter position. The embedded script itself
  # (set_model_script) is unchanged by the picker: the interactive flow is
  # only a new way to PRODUCE the --model value.
  client="$1"
  version="$2"
  script=$(set_model_script "$client")

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
      picker=$(cat <<'PICKER'
Step 4 -- Ask the user which model to assign to antz-<agent>, via `AskUserQuestion` in this session (it is a main-session tool; never from or via a subagent). Ask ONE question. Its text must state the current state from Step 3 -- either "the currently configured model is <value>" or "no model is currently configured" -- and, when the current value exactly equals one of the offered options' value strings, that option is marked as the current one; otherwise no option is marked. Offer exactly these explicit options, in this order:
1. `sonnet`
2. `opus`
3. `haiku`
4. `Revert to default (clear)` -- choosing it runs the script with `--clear`
`AskUserQuestion` automatically appends a built-in free-text row, so the user can enter any other value via free-form input; do not spend an option slot on a separate "type another value" entry. Also name these further documented alias values verbatim in the question text, so they can be entered via free-form input without typo risk: `best`, `fable`, `sonnet[1m]`, `opus[1m]`, `opusplan`.

The full documented alias vocabulary (source: https://code.claude.com/docs/es/model-config) is embedded in this command at install time: `best`, `fable`, `opus`, `sonnet`, `haiku`, `sonnet[1m]`, `opus[1m]`, `opusplan`. This list is embedded and refreshed only by re-running install.sh; it is never queried at runtime.
PICKER
)
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
      picker=$(cat <<'PICKER'
Step 4 -- Ask the user which model to assign to antz-<agent>, via the session's `question` tool. First, enumerate the available models at invocation time: run `opencode models` via the Bash tool; its output lists `provider/model` ids (for example `anthropic/claude-opus-4-5`). No model catalog is embedded in this command. Offer the enumerated `provider/model` ids as the question options; when the catalog is too large to present in one question, you may filter, group, or paginate the presentation sensibly (for example, the current session provider's models first) -- but the free-form option and the revert-to-default (clear) option must always remain offered, so no value is unreachable. If `opencode models` fails or returns no model ids, degrade instead of failing: still ask the question, with the question text stating that no models could be enumerated, offering only the free-form option and the revert-to-default (clear) option.

Alongside any enumerated ids, ALWAYS offer an explicit `Type another value` free-form option (the `question` tool has no built-in free-text row) and the `Revert to default (clear)` option (choosing it runs the script with `--clear`). The question text must state the current state from Step 3 -- either "the currently configured model is <value>" or "no model is currently configured" -- and, when the current value exactly equals one of the offered options' value strings, that option is marked as the current one; otherwise no option is marked. A free-form answer is passed to the script verbatim, never validated or translated.
PICKER
)
      ;;
    *) echo "Unknown client: $client" >&2; exit 1 ;;
  esac

  flow_head=$(set_model_flow_head | sed "s|__CLIENT__|$client|; s|__AGENTS_PATH__|$agents_path|")
  flow_tail=$(set_model_flow_tail)

  body=$(printf '%s\n\n%s\n\n%s\n\n%s\n\n```sh\n%s\n```\n' \
    "$intro" "$flow_head" "$picker" "$flow_tail" "$script")

  printf -- '---\n# %s version=%s -- do not edit by hand; regenerate with install.sh\ndescription: %s\n%s---\n\n%s\n' \
    "$MARKER" "$version" "$short_desc" "$extra_frontmatter" "$body"
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

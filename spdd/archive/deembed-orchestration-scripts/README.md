# Change: deembed-orchestration-scripts

## Goal

De-embed the antz orchestration scripts and drastically cut the token cost
and KV-cache churn of an orchestration session (analysis:
`docs/antz-analisis-go-vs-posix-desembed.md`, option C — pure POSIX, no
Go). Today `orchestrator.prompt` embeds ~335 lines of scripts behind
`# antz-include:` markers that `install.sh`'s `inject_includes()`
re-materializes into the rendered `antz-orchestrator` body, and the
rendered prose orders the agent to save each script to a temp file and run
it — so the agent re-emits the whole script text as expensive output-tool
tokens on every session and every resume, and the embedded content sits in
the system prompt. `/antz-set-model` embeds its ~155-line script in both
command copies the same way. This change installs the three orchestration
scripts plus the set-model script as four FILES in one shared, resolved
library directory, turns every invocation into a one-line path call, and
retires the embed machinery. Script behavior and every machine line stay
byte-identical.

Decisions already taken by the user (2026-09-13), binding here: shared
libdir `"${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/"` (1); set-model
included in this change (2); minor grade with an explicit CHANGELOG note
(3); the combined ensure+state subcommand deferred to another change (4);
AGENTS.md/CLAUDE.md Gotchas and docs/orchestrator.md updated here (5); no
runtime version handshake — `install.sh --check` offline only (6);
install.sh resolves XDG_CONFIG_HOME once and writes the concrete path into
what it renders, never hardcoding `$HOME/.config` (7).

## Contract

- Sub-specs in dependency order: 01 libdirinstall (install side: four
  scripts as marked files, XDG resolution, backup, --check, fail-closed
  atomic pass) → 02 invocations (prompt invokes by path; include-marker
  mechanism and inject_includes() retired; stable-prefix criteria) →
  03 setmodeldeembed (set-model script as the fourth libdir file with a
  required client first argument; command bodies invoke by path) → 04
  docslaw (AGENTS.md/CLAUDE.md law + docs/orchestrator.md note) → 05
  testsuite (the suites pinning the embedded shape re-scoped) → 06
  versionbump (VERSION 4.7.1 → 4.8.0, minor, explicit note) → the e2e QA
  suite (verifier-owned, `e2e-qa.feature`).
- Expected VERSION outcome: **4.8.0** (modeled in 06). The working tree
  carries the bump; the human commits and tags.
- The three orchestration scripts are byte-identical to today (repo
  sources untouched; installed copies gain one marker line after the
  shebang); the set-model script keeps its entire observable contract and
  gains a required client first argument.

## Shared contracts

- **Libdir path contract** (01 ↔ 02 ↔ 03): one shared directory,
  resolved by install.sh at runtime as
  `"${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts"` (empty XDG falls back
  like unset). install.sh substitutes the concrete resolved absolute path
  — no trailing slash — into every rendered file that references a script.
  The prompt source carries the placeholder `__ANTZ_SCRIPTS_DIR__` at that
  position (dollar-digit-free shape, so client command-body templating
  cannot corrupt it); no placeholder survives any rendered or installed
  file. Command renderers interpolate the path directly (they are built at
  render time, not read from a source file).
- **Marker-in-scripts contract** (01 ↔ 03): each installed script carries
  `# antz:generated version=<VERSION> -- do not edit by hand; regenerate
  with install.sh` as a line-start header comment immediately after its
  shebang. The anchored detection (`^# antz:generated `) of `install_file`
  and `installed_version_of` applies unchanged — backup-if-unmanaged and
  version reading need no new mechanism. Repo sources under
  `scripts/orchestration/` stay byte-unchanged.
- **Invocation contract** (01 ↔ 02 ↔ 03): every call is
  `sh "<resolved path>" <arguments>`. No exec bit required, nothing on
  PATH, no hook or plugin, no temp-file copy, no re-materialization. The
  flow subcommands stay exactly discover/ensure/state/release; `state`
  still receives the probe's path as its second argument.
- **Machine-line vocabulary byte-identity** (02 ↔ 03 ↔ e2e): every
  `state=`, `candidate=`, `branch=`, `gate=`, `released`, `dirty=yes`,
  `subspec=`, `open_questions=`, `rejected_count=`, `change_dir=missing`,
  `skill=`, and `Skills: none matched` line, and every set-model message,
  is byte-identical to today. The scripts' own header usage comments
  therefore keep their historical `sh <tempfile> ...` wording
  (byte-identity wins over cosmetic freshness).
- **Client argument for the set-model script** (03): the installed
  `antz-set-model.sh` takes `<claude|opencode>` as its first positional
  argument and resolves the agents directory internally. Each per-client
  command body passes its own client; the user never supplies one — the
  set-model domain's Client-binding contract is preserved at the command
  level.
- **Stable prefix** (02): within one installed VERSION, the rendered
  agent/command trees are byte-identical across installs and contain no
  per-session data; scripts and prompt are separately installed artifacts,
  so a script edit can never dirty the prompt prefix. The only
  version-bearing string is the frontmatter marker line — the accepted,
  documented bump invalidation.

## Invariants (change-wide)

- POSIX sh only, Linux/macOS, bash-3.2-safe (the posixsh-01 mechanical
  scan still finds zero heredoc bodies inside command substitutions). No
  Go, no CLI on PATH, no hooks/plugins. Nothing is installed beyond the
  existing twelve client files plus the four libdir scripts.
- The scripts' behavior is unchanged: every pre-existing script-level
  assertion passes unmodified; the script suites' behavior matrices are
  untouched.
- `--check` writes nothing and creates no libdir; backups are never read,
  renamed, pruned, or deleted.
- No role ever commits anything; all work stays uncommitted on
  `antz/deembed-orchestration-scripts`; the local `v4.8.0` tag is the
  human's follow-up.
- The flow law is untouched: no `-B`, no `--force`, no merges, no resets,
  no branch deletes, never a forced checkout; the branch is only a marker.
- Directory ownership, session guards (dedup/latch), the bounded-retry
  machinery, receipts, and the closing-block contracts are unchanged.
- The install is one atomic pass: all four script sources are read or
  fetched (through `fetch_file`, honoring `ANTZ_REF` on the remote path)
  before any destination is written; a failing source aborts loudly and
  leaves the previous install intact.

## Out of scope

- The combined ensure+state subcommand for resumes (deferred; decision 4).
- A runtime prompt↔scripts version handshake — `install.sh --check` is
  the only version drift surface (decision 6).
- Uninstall, Windows, a third client (Pi), a Go binary, anything on PATH.
- Any change to the scripts' subcommands, behavior, or output vocabulary.
- Any change to specifier/coder/verifier prompts, `agents/meta/`, the
  access model, the twelve client-file install paths, or the rendered
  frontmatter shapes.
- Client-specific libdir subdirectories (decision 1: one shared libdir).
- Pruning `.bak.<timestamp>` files.
- Shortening the orchestrator prompt's routing prose beyond the replaced
  invocation instructions — the tables and guard wording are pinned law;
  the token win comes from removing the ~335 embedded script lines and
  the per-session re-materialization, which IS specified (02, scenario 07).

## Entities

| Name | Path | New-or-Existing | Notes |
|---|---|---|---|
| Installed flow script | `<libdir>/antz-flow.sh` | New (installed copy) | byte-faithful source + marker line; source `scripts/orchestration/antz-flow.sh` byte-unchanged |
| Installed probe | `<libdir>/antz-probe.sh` | New (installed copy) | byte-faithful source + marker line; run by `state` |
| Installed skills script | `<libdir>/antz-skills.sh` | New (installed copy) | byte-faithful source + marker line; fence-indent carve-out retired with the embed |
| Set-model script | `<libdir>/antz-set-model.sh` | New | extracted from install.sh's emitter; gains required client first argument; internal agents-dir resolution |
| Placeholder token | `__ANTZ_SCRIPTS_DIR__` in `agents/prompts/orchestrator.prompt` | New (source only) | substituted at render time by the concrete resolved libdir path; never survives a render |

## Operations

| Type | Identifier | Description |
|---|---|---|
| new install step | `install.sh` → libdir scripts | installs the 4 scripts (marker/backup/atomic pass), same run as the client files |
| extended report | `install.sh --check` | one line per script artifact (fresh / up to date / drift), CHANGELOG printed once, writes nothing |
| unchanged | `sh "<libdir>/antz-flow.sh" discover \| ensure <slug> \| state <slug> "<libdir>/antz-probe.sh" \| release <slug>` | antz-flow.sh subcommands and machine lines byte-identical |
| unchanged | `sh "<libdir>/antz-skills.sh" <working-root> <keyword>...` | derivation output contract byte-identical |
| modified invocation | `sh "<libdir>/antz-set-model.sh" <claude\|opencode> --agent <name> (--model <value>\|--clear)` | new required client first argument; editing contract and messages byte-identical |
| retired | `inject_includes()` + `# antz-include:` markers + the antz-skills fence-indent carve-out | the embed mechanism is removed wholesale (invocations-02) |

## Relevant files (pointers per sub-spec)

- **01 libdirinstall** (destination domain: `install-render`):
  `install.sh` (libdir resolution, script install loop, `report_version`/
  `--check` extension, `fetch_file`, `install_file`, `installed_version_of`);
  `scripts/orchestration/{antz-flow,antz-probe,antz-skills}.sh`
  (byte-untouched sources); `tests/refpin_test.sh` (refpin-05 re-scope);
  a new self-contained libdir install suite tagging the `libdirinstall-NN`
  ids.
- **02 invocations** (destination domain: `flow-branch`):
  `agents/prompts/orchestrator.prompt` (three fences → invocation lines);
  `install.sh` (`inject_includes()` removal, placeholder substitution);
  supersession notes land in `spdd/specs/skills-activation.md` (temp-file
  invariant) alongside the flow-branch merge; structural-count MODIFYs of
  flow-09 and orchprose-01.
- **03 setmodeldeembed** (destination domain: `set-model`; two re-scopes
  merge into `spdd/specs/posixsh.md`): `install.sh`
  (`emit_set_model_script`/`set_model_script`/`render_set_model_command`);
  the two rendered command copies; `tests/set-model-command_test.sh`;
  `tests/installsh-posixsh_test.sh` (posixsh-04 re-key + inventory).
- **04 docslaw** (destination domain: `flow-branch` — renderinject-07
  MODIFY): `AGENTS.md`, `CLAUDE.md` (Gotchas bullets + Client Integration
  sentence, byte-identical pair), `docs/orchestrator.md` (dated note).
- **05 testsuite** (destination domain: `flow-branch`):
  `tests/antz-flow_test.sh`, `tests/orchestrator-status-probe_test.sh`,
  `tests/orchestrator-skills-block_test.sh`,
  `tests/orchestrator-sessionguards_test.sh`, `tests/renderinject_test.sh`,
  `tests/roles_test.sh`, `tests/orchestrator-render-sync_test.sh`.
- **06 versionbump** (destination domain: `versioning`): `VERSION`,
  `CHANGELOG.md`.
- **e2e-qa.feature**: verifier-owned; executed through install.sh's CLI
  affordances, the installed files, and the script invocations as the
  installed bodies instruct them; live-session halves judged by mechanism
  per the repo's established e2e convention.

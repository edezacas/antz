# fix-install-sh-syntax

## Goal
Make `install.sh` run under macOS's `/bin/sh` (bash 3.2 in POSIX mode) behind
the documented invocation `curl -fsSL
https://raw.githubusercontent.com/edezacas/antz/master/install.sh | sh`,
which today dies with `sh: line 230: syntax error near unexpected token ';;'`
and installs nothing — while changing no documented behavior anywhere else.

## Root cause (reproduced, not guessed)
A bash 3.2.57 build was provisioned in this investigation and reproduces the
failure exactly (same line, same token, in `--posix` mode and plain mode):

- bash 3.2's parser mis-reads a heredoc whose **body sits inside a command
  substitution** — `script=$(cat <<'SCRIPT' … SCRIPT)`. It keeps parsing the
  heredoc body as command text; the first `;;` inside that body (install.sh
  line 230, the set-model argument loop of the heredoc-emitted script) is
  then an unexpected token. Line 230 is quoted text, never executed code.
- install.sh contains three instances of the trap: **line 204**
  (`script=$(cat <<'SCRIPT'` in `set_model_script`) and **lines 424/448**
  (`picker=$(cat <<'PICKER'` in both case branches of `render_set_model_command`).
- It went undetected locally because Linux `sh` (as here, bash 5.3-as-sh) and
  modern bash parse the construct without complaint; only bash 3.2 chokes.

Validated fix shape (in this session, byte-exact): keep each heredoc in its
own top-level, no-argument emitter function (like `set_model_flow_head`
already does) and capture its output — `script=$(emit_set_model_script)`,
`picker=$(emit_picker_claude)` / `picker=$(emit_picker_opencode)`. Capturing
a function's stdout inside `$(...)` is plain POSIX and parses in bash 3.2.
A render into isolated HOMEs proved every installed file byte-identical to
the pre-fix render.

The emitted set-model script's own `for arg do` is fine: only
heredoc-inside-command-substitution breaks bash 3.2, and the emitted script
has none (see posixsh-04).

## Contract
- install.sh parses with exit 0 under macOS-fidelity POSIX sh (bash 3.2
  --posix) — see `01-posixsh.feature`.
- No heredoc body may sit inside a command substitution in install.sh — the
  mechanical regression guard `posixsh-01`.
- Rendered output (all agent files, both `antz.md`, both `antz-set-model.md`,
  markers, VERSION embedding), flags, install paths, `--check` mechanics and
  the Linux `sh` behaviors are all unchanged — `posixsh-03`, `posixsh-04`, the
  e2e suite, and every pre-existing spec domain (`spdd/specs/set-model.md`,
  `specifier-role.md`, `versioning.md`) remain byte-level true.

## Shared contracts
- The bash 3.2 reproduction helper `tests/bash32-sh.sh` (created by the
  coder): provisions-or-surfaces a cached GNU bash 3.2.57 `bash` binary.
  Verified build recipe: bash-3.2.57 sources from ftp.gnu.org,
  `CC="gcc -std=gnu89"`, `CFLAGS="-O1 -std=gnu89
  -Wno-implicit-function-declaration"`, then `./configure && make` (three
  patch-independent fixes folded in). The pre-change tree must fail
  `bash3.2 --posix -n install.sh` with the line-230 `;;` error — that
  reproduced data point is part of the acceptance (`posixsh-02`).
- One change slug: `fix-install-sh-syntax`.

## Invariants
- Only `install.sh` (plus the two `tests/` helpers and VERSION/CHANGELOG
  bookkeeping) changes; nothing under `agents/`, `commands/`, `docs/`, or
  `spdd/` non-change paths is touched by the fix.
- Rendered byte-identity (posixsh-04) is a hard gate; any code change beyond
  relocating the three heredocs into emitter functions needs its own
  justification against this sub-spec.

## Versioning consequence (per spdd/specs/versioning.md)
A commit changing `install.sh` needs a same-commit VERSION bump + matching
CHANGELOG.md entry, plus the local `vX.Y.Z` tag. This is a fix to install
mechanics that changes what happens (install now works where it failed):
grade as **minor** (2.3.0 → 2.4.0, `v2.4.0`). The bump/tag belong to the
coder's commit, not to this spec's commit.

## Out of scope
- Any change to rendered command/agent content, marker mechanics, install
  paths or flags (all frozen by posixsh-04).
- Other shells' support matrices (dash, busybox, zsh) beyond "the plain
  POSIX sh check keeps passing".
- Retiring or reworking `set_model_script`/the emitted script semantics.

## Relevant files
- `install.sh` — the fix site (lines 204, 424, 448; touched functions
  `set_model_script`, `render_set_model_command`).
- `tests/bash32-sh.sh` — new bash 3.2 reproduction helper (coder creates;
  recipe above).
- `tests/installsh-posixsh_test.sh` — natural vehicle for the coder's unit
  suite (precedent: `tests/set-model-command_test.sh`).
- `spdd/specs/versioning.md` — bump policy the fix commit must follow.
- Already-cached bash 3.2.57 build used in this investigation:
  `/tmp/opencode/bash-3.2.57/bash` (fresh on any machine via the helper).

## End-to-end QA suite
 See `e2e-qa.feature` in this directory: full install under plain POSIX sh
 (e2e-qa-01), the user's exact macOS invocation reproduced end-to-end under
 bash 3.2 (`e2e-qa-02`), and `--check` staying a no-writer report
 (`e2e-qa-03`).

# Change: orchestrator-fast-path

## Goal
Three improvements to antz's orchestrated flow, delivered as one change with
six implementation sub-specs plus the e2e suite:

1. **Extract the embedded scripts** of `orchestrator.prompt` into source
   files under `scripts/orchestration/` (`antz-flow.sh`, the status probe as
   `antz-probe.sh`, `antz-skills.sh`). `install.sh` injects their content
   into the rendered `antz-orchestrator` body for both Claude Code and
   OpenCode — same runtime contract (temp file + `sh <tempfile> ...`),
   byte-identical render, nothing new installed standalone. No behavior
   change. This also lets `tests/` test the scripts as files instead of
   extracting them from the prompt.
2. **Session guards in the orchestrator prompt** (prose, patch-level):
   (a) dedup — never delegate the same `(sub-spec, role)` pair twice within
   one orchestrator invocation (single carve-out: step 4's bounded-retry
   relay); (b) latch — after any stop-and-report, no further delegation of
   any kind in that same session.
3. **Receipts — classify without re-running tests**: the coder writes
   `spdd/changes/<slug>/NN-<feature>.result` at the end of each session that
   finishes or advances a sub-spec (fixed grep-able grammar: one
   `test_command=` line + one `id=<feature>-<index> result=green|skip|blocked
   reason=...` line per scenario id; blocked reasons carry the existing
   `BLOCKED:` convention). The orchestrator's probe reads receipts and emits
   `receipt=<file> covered=N/N complete=yes|no class=...`; classification
   becomes file reading (`done` / `blocked` / `in_progress`). The
   orchestrator never runs the unit suite for classification and never as a
   pre-verifier gate — the only exception is a missing/incomplete/mismatched
   receipt, where it re-runs the suite once for that doubtful sub-spec.
   Test-command discovery moves to the coder. Each role's conversational
   report gains a grep-able closing block (`status` / `ids` / `results`) as a
   mirror only — the disk receipt is the authority.

## Contract
- Sub-specs in dependency order: 01 scriptsource (source files + prompt
  markers) → 02 renderinject (install.sh injection) → 03 testharness (tests
  read files) → 04 sessionguards (prose law) → 05 receipts (coder + probe +
  classification) → 06 closingblock (report mirrors + the VERSION bump) →
  07 e2e (verifier-owned suite).
- Expected VERSION outcome (modeled in 06): `4.2.1` → **`4.3.0`**, one
  `[4.3.0]` CHANGELOG.md entry covering all three improvements, graded
  **minor** (most severe component: the render change / role behavior
  changes). The working tree must carry the bump so the human's commit does
  (no role ever commits).

## Shared contracts
- **Include-marker contract** (01 ↔ 02 ↔ 03): in
  `agents/prompts/orchestrator.prompt`, each of the three script fences'
  body is exactly one line `# antz-include: scripts/orchestration/<name>.sh`
  (`antz-flow`, `antz-probe`, `antz-skills`); install.sh replaces each such
  line with the verbatim content of the named file when rendering
  `antz-orchestrator` for either client, never leaves a marker in a rendered
  body, and fails loudly (naming the file) when a script cannot be read or
  fetched. The rendered orchestrator body is byte-identical to the pre-change
  render (same version marker).
- **Receipt grammar** (05 ↔ 06): file `spdd/changes/<slug>/NN-<feature>.result`
  (mirrors the sub-spec filename; updated in place by later sessions);
  exactly one non-empty `test_command=<discovered unit-suite run command>`
  line; one `id=<feature>-<index> result=<green|skip|blocked> reason=<text>`
  line per declared scenario id (exact id-set match, scenario order, no
  duplicates); non-empty reason on every line; a blocked line's reason
  starts with `BLOCKED: `. Classification mapping (probe-emitted `class=`):
  blocked first (any `result=blocked`, regardless of coverage), then done
  (complete=yes and all results green/ordinary-skip), else in_progress.
  `complete=yes` = receipt exists, one non-empty `test_command=` line, exact
  declared id set (a foreign id is a mismatch → complete=no).
- **Closing-block grammar** (06, all roles): exactly three consecutive
  lines at the end of each role's conversational report —
  `status=<value>`, `ids=<id,id,...>`, `results=<value>` — per-role
  vocabularies pinned in closingblock-02; mirror only, never a routing
  input; the disk receipt is the authority wherever both exist.
- **Scenario-id conventions** unchanged: `<feature>-<index>` ids in tag
  first lines; test names carry the id; `BLOCKED: <why>` (plain colon) is
  the skip-reason convention; OPEN_QUESTIONS.md presence is a hard stop;
  REJECTED.md's `## Rejection <n>` bounded retry is untouched.

## Invariants (change-wide)
- No role ever commits anything; all work stays uncommitted on
  `antz/orchestrator-fast-path`; the branch-marked flow law
  (`antz-flow.sh`'s never-destructive behavior) is untouched.
- Change 1 is provably no-behavior-change: script files are byte-equal
  dedents of the current snippets; the rendered orchestrator body is
  byte-identical to the pre-change render; assertion coverage of the three
  script suites is unchanged.
- The orchestrator runs the unit suite in exactly one situation: the
  doubtful-receipt exception (receipts-08) — never for classification of a
  well-formed receipt, never as a pre-verifier gate; the verifier's e2e
  Integration Verification suite remains the independent gate.
- Directory ownership unchanged: the coder writes only under
  `spdd/changes/<slug>/` (now also receipts); the orchestrator still never
  writes anything itself; `agents/meta/*` stay byte-for-byte unchanged.
- install.sh stays POSIX sh and bash-3.2-safe; `--check` stays keyed off the
  installed specifier agent's marker version.
- The bounded-retry carve-out: step 4's relay is the single permitted second
  delegation of a `(sub-spec, role)` pair in one invocation (sessionguards-01).

## Out of scope
- A formalized Result Contract beyond the receipt grammar and the closing
  block.
- Any change to the branch-marked flow law (`antz-flow.sh`'s
  never-destructive behavior, the no-commit law, directory ownership).
- Any change to the scripts' behavior, subcommands, or output vocabulary
  beyond the probe's extended subspec line (receipts-06).
- Any change to the verifier's duties, the e2e suite's role, or the
  rejection machinery's bounds.
- The `worktree` sibling branch variant.

## Entities
| Name | Path | New-or-Existing | Notes |
|---|---|---|---|
| Flow script source | `scripts/orchestration/antz-flow.sh` | New | byte-equal dedent of the prompt's first 3-space bare fence |
| Status probe source | `scripts/orchestration/antz-probe.sh` | New | dedent of the ```` ```sh ```` fence; gains receipt/covered/complete/class fields |
| Skills derivation source | `scripts/orchestration/antz-skills.sh` | New | dedent of the antz-skills.sh fence |
| Result receipt | `spdd/changes/<slug>/NN-<feature>.result` | New | coder-written per sub-spec; grammar in Shared contracts |

## Operations
| Type | Identifier | Description |
|---|---|---|
| unchanged | `sh <tempfile> discover \| ensure <slug> \| state <slug> <probe-path> \| release <slug>` | antz-flow.sh subcommands, contract untouched |
| unchanged | `sh <tempfile> <working-root> <match keyword> ...` | antz-skills.sh invocation, untouched |
| extended output | probe `subspec=` line | gains `receipt= covered= complete= class=` fields (receipts-06) |
| new artifact write | coder → `NN-<feature>.result` | at session end, per receipts-01..05 |

## Relevant files (pointers per sub-spec)
- **01 scriptsource**: `agents/prompts/orchestrator.prompt` (three fenced
  bodies → include markers); new `scripts/orchestration/{antz-flow,antz-probe,antz-skills}.sh`.
- **02 renderinject**: `install.sh` (injection keyed to the orchestrator,
  both clients; fetch path for the script files; header line-21 drift fix
  from `spdd/specs/versioning.md`); `AGENTS.md`/`CLAUDE.md` gotcha wording.
- **03 testharness**: `tests/antz-flow_test.sh`,
  `tests/orchestrator-status-probe_test.sh`,
  `tests/orchestrator-skills-block_test.sh` (file-loading replaces the
  fence extractors; additive-vs-HEAD guard re-scoped); a render-consistency
  guard.
- **04 sessionguards**: `agents/prompts/orchestrator.prompt` (dedup + latch
  prose; step-4 carve-out).
- **05 receipts**: `agents/prompts/coder.prompt` (receipt duty +
  test-command discovery), `agents/prompts/orchestrator.prompt` (step 3
  file-reading classification + doubtful-receipt exception),
  `scripts/orchestration/antz-probe.sh` (extended line),
  `AGENTS.md`/`CLAUDE.md` (receipt gotcha).
- **06 closingblock**: all four `agents/prompts/*.prompt` report sections
  (specifier prompt's historical byte-for-byte pin lifted for this additive
  edit only), `AGENTS.md`/`CLAUDE.md`, `VERSION`, `CHANGELOG.md`.
- **07 e2e**: verifier-owned; no coder implementation.

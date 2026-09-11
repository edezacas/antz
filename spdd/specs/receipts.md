# Domain: receipts

## Origin
- Specced and delivered from change `orchestrator-fast-path` (merged 2026-09-11,
  archived in `spdd/archive/orchestrator-fast-path/`). This is a **new standalone
  spec domain**: before this change no spec domain covered the coder's result
  receipts, the closing-block report convention, or the classification-by-file-
  reading contract. The orchestrator-flow edges of the delivering sub-spec 05
  (the probe's extended `subspec=` line, step 3's file-reading classification,
  the doubtful-receipt exception, the no-pre-verifier-gate rule) merged into
  `spdd/specs/flow-branch.md` (its receipts-06..09 entries).
- Reported defect it fixes: the orchestrator classified sub-specs by discovering
  and running each project's unit suite itself — slow, ambiguous to discover,
  and it made the orchestrator run tests as a pre-verifier gate. With receipts,
  classification is mechanical file reading; the coder (who knows the project's
  test convention) records the discovered command and per-scenario outcomes at
  session end, and the unit suite is run by the orchestrator in exactly one
  situation: the doubtful-receipt exception.

## Goal
The coder writes `spdd/changes/<slug>/NN-<feature>.result` at the end of each
session that finishes or advances a sub-spec (named after the sub-spec file,
`01-api.feature` → `01-api.result`; a later session rewrites it in place). The
grammar is fixed and grep-able: exactly one non-empty `test_command=` line (the
unit-suite run command the coder discovered and used — discovery is the coder's
job, the way any contributor would) plus one
`id=<feature>-<index> result=<green|skip|blocked> reason=<text>` line per
declared scenario id (exact declared id set, scenario order, no duplicates,
non-empty reason on every line; blocked reasons carry the existing `BLOCKED: `
convention). The orchestrator's probe reads the receipts and emits
`receipt= covered= complete= class=` per sub-spec; classification becomes
mechanical file reading (`done` / `blocked` / `in_progress`). Each role's
conversational report ends with a grep-able closing block (`status=` / `ids=` /
`results=`) as a transparency mirror only — the disk receipt is the authority
wherever both exist.

## Shared contracts
- **Receipt grammar** (this domain ↔ `flow-branch.md`'s receipts-06..09): the
  grammar above is what the probe checks mechanically and what the
  orchestrator's classification reads.
- **Closing-block grammar** (closingblock-01..02 ↔ every role prompt): exactly
  three consecutive lines at the end of each role's report, with per-role value
  vocabularies pinned in the prompts.
- The governing rule extends to the closing block: no routing, count, or
  decision ever derives from it; disk state (the receipt) is the authority.

## Feature: the coder records per-scenario results in a receipt (coder duty)

  Background:
    Given a change directory "spdd/changes/<slug>/" holding sub-spec files
      "NN-<feature>.feature" whose declared scenario ids the probe already
      extracts from their tag comments
    And a coder session implementing one sub-spec tags each unit test with
      its scenario's "<feature>-<index>" id (existing convention)

  # ADD - receipts-01
  At the end of a session that finishes or advances its sub-spec, the coder
  writes `spdd/changes/<slug>/NN-<feature>.result` mirroring the sub-spec's
  filename, containing exactly one `test_command=` line whose value is the
  unit-suite run command the coder discovered and used for this sub-spec, plus
  one `id=<feature>-<index> result=<green|skip|blocked> reason=<text>` line per
  declared scenario id.

  # ADD - receipts-02 (outline)
  | outcome                                                       | receipt line                                  |
  |---------------------------------------------------------------|-----------------------------------------------|
  | the scenario's unit test passes                               | id=<id> result=green reason=<unit test name>  |
  | the scenario is an ordinary skip (not unit-testable, no stub) | id=<id> result=skip reason=<why>              |
  | the scenario is a "BLOCKED:" skip/reason stub                 | id=<id> result=blocked reason=BLOCKED: <why>  |

  # ADD - receipts-03
  The receipt's id lines name exactly the sub-spec's declared id set, each once,
  in the sub-spec's scenario order, each with a non-empty reason; a foreign id
  never appears; a declared id with no test yet still gets its line
  (result=skip or result=blocked with an honest reason) — never a silent
  omission.

  # ADD - receipts-04
  A fresh coder session on the same sub-spec rewrites the same receipt in place
  — never a second, accumulated `NN-<feature>.result-2` or sibling file; the
  file always holds the newest session's state (its outcomes and test command).

  # ADD - receipts-05
  A planning-stage refusal (the existing whole-sub-spec `BLOCKED:` stub, tagged
  with the sub-spec's first scenario id) still produces a truthful receipt:
  every declared id gets `result=blocked` and the same `BLOCKED: <why>` reason,
  and `test_command=` still records the discovered (or honestly undiscoverable)
  suite command — the receipt is never empty.

  # ADD - receipts-10
  AGENTS.md and CLAUDE.md each carry an identical receipt-convention gotcha
  bullet: the file name written by the coder at session end, the
  `test_command=` + per-id grammar, `BLOCKED:` as the blocked reason, and that
  the orchestrator classifies by reading receipts — running the unit suite only
  for a doubtful receipt, never as a pre-verifier gate.

  ### Invariants
  - The disk receipt is the classification authority; a role's conversational
    report is never an input to it (the governing rule holds).
  - The probe still runs no tests and no git: receipts are read as files, like
    OPEN_QUESTIONS.md and REJECTED.md before them.
  - The unit suite is run by the orchestrator in exactly one situation: the
    doubtful-receipt exception (receipts-08, in `spdd/specs/flow-branch.md`) —
    never for classification of a well-formed receipt, never as a pre-verifier
    gate.
  - Sequential coder sessions, the bounded REJECTED.md retry, the BLOCKED:
    stop-and-relay behavior, and directory ownership are all unchanged; the
    receipt lives under `spdd/changes/<slug>/`, written by the coder like every
    other role artifact; the orchestrator never writes anything itself.
  - The sub-spec's empty-ids case keeps its existing stop-and-ask outcome
    (never vacuously done): with no ids the receipt has no id lines, the probe
    emits complete=no class=in_progress, and the orchestrator stops and asks.
  - Receipts cover coder sub-spec sessions only — not the specifier's or the
    verifier's own artifacts.

## Feature: closingblock — grep-able report mirrors in every role, and the 4.3.0 bump

  Background:
    Given the four role prompts' report sections (specifier "## Output,
      written to...", coder "## Output", verifier "## Report Format",
      orchestrator "## Report Format")
    And "spdd/specs/skills-activation.md" prompts-05's historical
      byte-for-byte guard on "agents/prompts/specifier.prompt" (superseded
      for this additive edit only — see the supersession record there)

  # ADD - closingblock-01
  Every role prompt's report section requires the report to end with a closing
  block of exactly three consecutive lines — `status=<value>`, `ids=<id,id,...>`,
  `results=<value>` — grep-able, short, deterministic; and states the block is a
  mirror only: no routing, count, or decision ever derives from it, and wherever
  a disk receipt exists, the receipt is the authority over the block's mirrored
  values.

  # ADD - closingblock-02 (outline)
  | role         | status value(s)                                                                             | ids                                        | results                                                                                             |
  |--------------|---------------------------------------------------------------------------------------------|--------------------------------------------|-----------------------------------------------------------------------------------------------------|
  | specifier    | spec_complete                                                                               | the declared ids of the sub-specs it wrote | none                                                                                                 |
  | coder        | done, blocked                                                                                | its sub-spec's declared ids                | comma-joined id=<id> result=<green|skip|blocked> tokens mirroring its receipt, in receipt order      |
  | verifier     | approved, rejected (approved-with-warnings folds to approved; prose verdict authoritative)   | the change's declared ids                  | comma-joined id=<id> result=<green|skip|blocked> tokens from the receipts as found on disk at verification end |
  | orchestrator | delegated-specifier, delegated-coder, delegated-verifier, stopped, released, waiting-user    | the ids from the probe                     | comma-joined <subspec-file>=<done|blocked|in_progress> per sub-spec, from the probe's class fields   |

  # ADD - closingblock-03
  The coder's report body names the receipt file it wrote or updated; its
  `results=` tokens match that receipt's id lines exactly (the receipt is the
  authority; a deviation is a bug, absorbed by the bounded REJECTED.md retry);
  a session that refused before touching the sub-spec still closes honestly:
  `status=blocked` with the `BLOCKED:` reason in the report prose.

  # ADD - closingblock-04
  Every role's report section states the block is never an input to any routing
  state or count (extending prompts-06's skills-line rule); AGENTS.md and
  CLAUDE.md state the closing-block convention identically (byte-identical
  gotcha bullet, may share the receipt bullet's file).

  # MODIFY - closingblock-05
  The specifier prompt's historical byte-for-byte pin is lifted for exactly this
  additive edit: the diff vs the pre-change file is only the closing-block
  requirement added to its output/report section; no existing bullet is
  reworded or removed (supersedes the prompts-05 pin in
  `spdd/specs/skills-activation.md` — see the supersession record there).

  # ADD - closingblock-06
  The bump is present: VERSION reads exactly `4.3.0` (newline-terminated only
  content) and CHANGELOG.md carries a `## [4.3.0] - <date>` section above
  `[4.2.1]`, with Added/Changed entries describing all three improvements (the
  scripts extracted to `scripts/orchestration/` with install.sh injection, no
  behavior change; the session guards; the coder-written result receipts with
  file-reading classification and the doubtful-receipt exception) plus the
  closing-block convention; every earlier CHANGELOG entry is byte-for-byte
  untouched. Since no role ever commits, the working tree carries the bump so
  the human's commit does.

  # ADD - closingblock-07
  The grade is minor, stated and justified against the versioning table
  (`spdd/specs/versioning.md`): change 1 alters install.sh's rendered agent
  bodies (a behavior change to the render = minor) and change 3 changes role
  behavior (the coder's receipt duty, the orchestrator's classification source);
  not patch (not wording-only: rendered output and role behavior change) and not
  major (the workflow contract, the `antz:generated` marker format, the access
  model, the directory layout, and the install locations are all unchanged — the
  receipt file is additive inside the existing change directory).

  ### Invariants
  - The disk receipt is the authority; the closing block is a transparency
    mirror, never a routing input (the governing rule extends to it).
  - "VERSION" is the only content of the "VERSION" file; the entry follows Keep
    a Changelog format and the file's existing style.
  - No role commits anything; the "v4.3.0" tag is the human's commit-time
    follow-up, created against the bump commit and not pushed automatically.
  - If the human splits the work into several commits, each commit touching
    agents/ and/or install.sh carries its own bump per the versioning rule —
    the modeled working-tree outcome is the single 4.3.0 state above.
  - "agents/meta/*" stay byte-for-byte unchanged.

## Out of scope
- A formalized Result Contract beyond the receipt grammar and the closing
  block: no new cross-role status protocol, no receipt-derived merge artifacts
  in `spdd/specs/`, no new status vocabulary for the verifier.
- Any change to the verifier's duties, the e2e suite's role, or the rejection
  machinery's bounds.
- Receipts for the specifier's or verifier's own artifacts.
- The scripts/render/tests layers (merged into `spdd/specs/flow-branch.md`).

## Relevant files
- `agents/prompts/coder.prompt` — the `## Receipt` section (receipt duty,
  grammar, discovery) plus the name-the-receipt and closing-block bullets.
- `agents/prompts/{specifier,verifier,orchestrator}.prompt` — the closing-block
  bullets in their report sections (orchestrator's flow edges in
  `spdd/specs/flow-branch.md`).
- `scripts/orchestration/antz-probe.sh` — the extended `subspec=` line
  (receipts-06, in `spdd/specs/flow-branch.md`).
- `AGENTS.md`, `CLAUDE.md` — the identical Receipts and Closing block gotcha
  bullets.
- `VERSION`, `CHANGELOG.md` — the 4.3.0 bump (closingblock-06..07).
- `tests/receipts_test.sh`, `tests/closingblock_test.sh` — one test per
  scenario id, with SKIP stubs for the live-session e2e ids.
- `spdd/archive/orchestrator-fast-path/` — the delivering change, preserved
  for history.

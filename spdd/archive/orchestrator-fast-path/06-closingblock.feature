# Change: orchestrator-fast-path — sub-spec 06 (report layer + the change's version bump)
#
# Each role's conversational report gains a short grep-able closing block —
# status / ids / results — as a mirror only. The disk receipt is the
# authority wherever both exist; no routing or decision may derive from the
# block (the governing rule and prompts-06's "never a routing input" rule
# extend to it).
#
# This sub-spec also models the change's expected VERSION outcome: all
# three improvements land as one working-tree state that the human commits
# (no role ever commits). One bump, graded by the most severe component:
# change 1 (render change, minor), change 2 (patch prose), change 3
# (receipts, minor) → minor → VERSION 4.2.1 → 4.3.0 with a single matching
# [4.3.0] CHANGELOG.md entry.

Feature: closingblock — grep-able report mirrors in every role, and the 4.3.0 bump

  Background:
    Given the four role prompts' report sections (specifier "## Output,
      written to...", coder "## Output", verifier "## Report Format",
      orchestrator "## Report Format")
    And "spdd/specs/skills-activation.md" prompts-05's historical
      byte-for-byte guard on "agents/prompts/specifier.prompt" (superseded
      for this additive edit only)

  # ADD - closingblock-01: the shared grammar — three consecutive lines,
  # mirror only, receipt is the authority.
  Scenario: closingblock-01
    When the reader reads any role prompt's report section after this
      sub-spec
    Then it requires the report to end with a closing block of exactly
      three consecutive lines: "status=<value>", "ids=<id,id,...>",
      "results=<value>" — grep-able, short, deterministic
    And it states the block is a mirror only: no routing, count, or decision
      ever derives from it, and wherever a disk receipt exists, the receipt
      is the authority over the block's mirrored values

  # ADD - closingblock-02: the per-role value vocabularies, pinned so each
  # block is deterministic.
  Scenario Outline: closingblock-02
    When the reader reads the row's role prompt
    Then its closing block fills the three lines per the row, mirroring
      disk state

    Examples:
      | role          | status value(s)                                        | ids                                         | results                                                                       |
      | specifier     | spec_complete                                          | the declared ids of the sub-specs it wrote  | none                                                                          |
      | coder         | done, blocked                                          | its sub-spec's declared ids                 | comma-joined "id=<id> result=<green|skip|blocked>" tokens mirroring its receipt, in receipt order |
      | verifier      | approved, rejected (approved-with-warnings folds to approved; the prose verdict stays authoritative) | the change's declared ids | comma-joined "id=<id> result=<green|skip|blocked>" tokens from the receipts as found on disk at verification end |
      | orchestrator  | delegated-specifier, delegated-coder, delegated-verifier, stopped, released, waiting-user | the ids from the probe | comma-joined "<subspec-file>=<done|blocked|in_progress>" per sub-spec, from the probe's class fields |

  # ADD - closingblock-03: the coder's block additionally names its receipt
  # in the report body, and honestly mirrors a session that produced no
  # receipt-worthy progress.
  Scenario: closingblock-03
    When a coder session ends
    Then its report body names the receipt file it wrote or updated (its
      "## Output" already lists files changed)
    And its "results=" tokens match that receipt's id lines exactly (the
      receipt is the authority; a deviation is a bug, absorbed by the
      bounded REJECTED.md retry)
    And a session that refused before touching the sub-spec still closes
      honestly: "status=blocked" with the "BLOCKED:" reason in the report
      prose

  # ADD - closingblock-04: the block is a mirror only — enforced in prose
  # and docs.
  Scenario: closingblock-04
    When the reader reads the role prompts and the policy docs
    Then every role's report section states the block is never an input to
      any routing state or count (extending prompts-06's skills-line rule)
    And "AGENTS.md" and "CLAUDE.md" state the closing-block convention
      identically (the same gotcha bullet that carries the receipt
      convention may carry it, byte-identical between the two files)

  # MODIFY - closingblock-05: the specifier prompt's historical
  # byte-for-byte pin is lifted for exactly this additive edit.
  Scenario: closingblock-05
    When the diff of "agents/prompts/specifier.prompt" is inspected
    Then it differs from the pre-change file only by the closing-block
      requirement added to its output/report section
    And no existing bullet of the specifier prompt is reworded or removed

  # ADD - closingblock-06: the bump is present — VERSION reads 4.3.0 and
  # CHANGELOG.md gains the matching top entry (the versioning rule: any
  # commit touching agents/ and/or install.sh bumps, in the same commit;
  # since no role commits, the working tree must carry the bump so the
  # human's commit does).
  Scenario: closingblock-06
    When the reader reads "VERSION" and the top of "CHANGELOG.md"
    Then "VERSION" reads exactly "4.3.0"
    And "CHANGELOG.md" contains a "[4.3.0] - <date>" section above
      "[4.2.1]", with Added/Changed entries describing all three
      improvements: the orchestrator scripts extracted to
      "scripts/orchestration/" with install.sh injecting them into the
      rendered antz-orchestrator body (no behavior change); the session
      guards (dedup and the post-stop latch); and the coder-written result
      receipts with the orchestrator's file-reading classification and the
      doubtful-receipt suite exception; plus the closing-block convention
    And every earlier CHANGELOG entry is byte-for-byte untouched

  # ADD - closingblock-07: the grade is minor, stated and justified against
  # the versioning table (most severe component wins).
  Scenario: closingblock-07
    When the reader reads the "[4.3.0]" entry against the grading scale
    Then the change grades as "minor": change 1 alters install.sh's
      rendered agent bodies (a behavior change to the render = minor, per
      versioning-04's row 2) and change 3 changes role behavior (the
      coder's receipt duty, the orchestrator's classification source)
    And it is not "patch" (not wording-only: rendered output and role
      behavior change) and not "major" (the workflow contract, the
      "antz:generated" marker format, the access model, the directory
      layout, and the install locations are all unchanged — the receipt
      file is additive inside the existing change directory)

### Invariants
- The disk receipt is the authority; the closing block is a transparency
  mirror, never a routing input (the governing rule extends to it).
- "VERSION" is the only content of the "VERSION" file ("4.3.0" with
  trailing newline); the entry follows Keep a Changelog format and the
  file's existing style.
- No role commits anything; the "v4.3.0" tag is the human's commit-time
  follow-up, created against the bump commit and not pushed automatically.
- If the human splits the work into several commits, each commit touching
  agents/ and/or install.sh carries its own bump per the versioning rule —
  the modeled working-tree outcome is the single 4.3.0 state above.
- "agents/meta/*" stay byte-for-byte unchanged.

## Out of scope
- A formalized Result Contract beyond the receipt grammar (sub-spec 05) and
  the closing block: no new cross-role status protocol, no receipt-derived
  merge artifacts in spdd/specs/.
- Any change to the verifier's duties or the e2e suite's role.
- The scripts/render/tests layers (sub-specs 01–03).

## Relevant files
- "agents/prompts/specifier.prompt" — closing-block line (closingblock-05).
- "agents/prompts/coder.prompt" — closing-block line in "## Output".
- "agents/prompts/verifier.prompt" — closing-block line in "## Report
  Format".
- "agents/prompts/orchestrator.prompt" — closing-block line in "## Report
  Format" (its status vocabulary mirrors the flow's outcomes).
- "AGENTS.md", "CLAUDE.md" — the identical closing-block/receipt gotcha
  wording.
- "VERSION", "CHANGELOG.md" — the 4.3.0 bump (closingblock-06..07).
- "tests/" — one test per scenario id, with SKIP stubs for the live-session
  e2e ids (07-e2e).

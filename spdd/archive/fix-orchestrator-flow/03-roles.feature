# Change: fix-orchestrator-flow — sub-spec 03 (roles: the coder's ownership by
# write surface, the verifier's plain-mv archive)
#
# Plan items 1.4 and 1.6 of docs/plan-revision-2026-09.md §3 Cambio A.
#
# Layer: the coder prompt's directory-ownership bullet (Input Rule) and the
# verifier prompt's Merge & Archive move bullet, plus the policy-doc gotcha
# bullet that restates the coder's ownership (AGENTS.md / CLAUDE.md,
# byte-identical between the two files per the shared-bullet convention).
#
# The defect (1.4): the coder prompt contradicts itself — the "## Owns" line
# says implementation starts from "spdd/changes/<change-slug>/" and existing
# "spdd/specs/" for context, while the Input Rule says "Read only from
# spdd/changes/" — and, worse, both state the coder's surface by READ surface,
# which cannot express that the coder's real writes (the implementation and
# tests) live outside spdd/ by definition. The second-review correction: state
# the surface by WRITE surface. The defect (1.6): the verifier's archive step
# offers "git mv" first, which always fails here — nothing is ever committed,
# so the files are untracked — an avoidable trap.
#
# Merge map: all scenarios are ADD against a new domain file at merge
# (suggested name spdd/specs/role-surfaces.md). Note for the merge:
# spdd/specs/access-model.md's invariant "Coder ownership rules stay as-is:
# the coder only reads spdd/changes/ and never touches spdd/specs/ or
# spdd/archive/" is superseded by roles-01/roles-04 and the verifier should
# record the supersession there.

Feature: the coder's directory ownership is stated by write surface and the verifier's archive step is a plain mv with its reason

  Background:
    Given "agents/prompts/coder.prompt" as published before this change,
      carrying the "## Owns" line naming "spdd/changes/<change-slug>/" and
      existing "spdd/specs/" for context, and the Input Rule bullet "Read
      only from spdd/changes/. Never touch spdd/specs/ (except as read-only
      context) or spdd/archive/."
    And "agents/prompts/verifier.prompt" as published before this change,
      carrying the Merge & Archive bullet "move spdd/changes/<change-slug>/
      to spdd/archive/<change-slug>/ unmodified (via git mv, or a plain mv
      — nothing here is ever committed, the orchestrator's release gate only
      reads the working tree)"
    And "AGENTS.md" and "CLAUDE.md", each carrying the identical
      "Strict directory ownership" gotcha bullet stating the coder role only
      reads "spdd/changes/" and must never touch "spdd/specs/" or
      "spdd/archive/"

  # ADD - roles-01: the coder's directory-ownership bullet is rewritten by
  # write surface — reads both spec surfaces, writes the implementation
  # wherever it belongs, never touches the archive.
  Scenario: roles-01
    When the reader reads the coder prompt's Input Rule
    Then the directory-ownership bullet states the surface by write surface:
      the coder reads "spdd/changes/" and "spdd/specs/" — both as read-only
      context, "spdd/specs/" never written — and writes the code and tests
      the sub-spec calls for wherever they belong in the project, plus its
      receipt in "spdd/changes/<slug>/", and never touches "spdd/archive/"
    And the old read-surface phrasing ("Read only from spdd/changes/") is
      gone, with its contradiction against the "## Owns" line
    And the rest of the Input Rule is unchanged: the missing-change-dir stop,
      the missing-sub-spec stop, the OPEN_QUESTIONS.md hard stop, and the
      refuse-a-multi-layer-plan rule all keep their meaning

  # ADD - roles-02: the coder prompt stays internally consistent — the Owns
  # line, the write-surface bullet, and the receipt duty name the same
  # surfaces.
  Scenario: roles-02
    When the reader reads the coder prompt's "## Owns" line, the rewritten
      Input Rule bullet, and the "## Receipt" section together
    Then all three name the same surfaces: reading "spdd/changes/" and
      "spdd/specs/" as context, writing the implementation and tests wherever
      they belong in the project, and writing the receipt inside
      "spdd/changes/<slug>/"
    And the receipt duty itself is unchanged by this sub-spec (the
      "test_command=" grammar is sub-spec 02-receipts' concern)

  # ADD - roles-03: the verifier's archive step is a plain mv as the only
  # instruction, with the reason stated in the prompt.
  Scenario: roles-03
    When the reader reads the verifier prompt's Merge & Archive section
    Then the archive-move instruction is a plain "mv" as the only mechanism:
      move "spdd/changes/<change-slug>/" to "spdd/archive/<change-slug>/"
      unmodified after the merge succeeds
    And the reason is stated in the prompt itself: "git mv" on untracked
      files always fails, since nothing is ever committed
    And "git mv" no longer appears as an offered option anywhere in the
      prompt, and the release-gate half of the reason survives (the
      orchestrator's release gate only reads the working tree)
    And the rest of Merge & Archive is unchanged: the move happens only on
      approved or approved-with-warnings, never archives a rejected change,
      and the never-overwrite-a-domain-spec rule stands

  # ADD - roles-04: the policy docs' strict-ownership gotcha bullet follows
  # the write-surface contract, byte-identical in both files.
  Scenario: roles-04
    When the reader reads the "Strict directory ownership" gotcha bullet of
      "AGENTS.md" and of "CLAUDE.md"
    Then both state the write-surface contract identically (byte-identical
      bullet, the files' shared-bullet convention): the coder reads
      "spdd/changes/" and "spdd/specs/" as read-only context, never writing
      "spdd/specs/", writes the code and tests the sub-spec calls for
      wherever they belong in the project plus its receipt in
      "spdd/changes/<slug>/", and never touches "spdd/archive/"; the verifier
      merges into specs and archives changes but never overwrites a domain
      spec file wholesale (merge scenario-by-scenario, ADD/MODIFY/REMOVE)
    And neither doc anywhere states that the coder only reads
      "spdd/changes/", nor that the coder must never touch "spdd/specs/"

  # ADD - roles-05: the prompt guards that pin every pre-change line of the
  # coder and verifier prompts are retired loudly — the rewordings are
  # legitimate — and no other suite pins the removed wording.
  Scenario: roles-05
    When the test suites are run after the rewrites
    Then the coder-prompt and verifier-prompt additive-vs-HEAD guards (the
      every-HEAD-line-survives-verbatim checks) no longer fail: they are
      retired with a loud printed note — the same retirement-note precedent
      as the render byte-identity retirements — or re-scoped the way the
      sessionguards removal check is gated, so the legitimate rewordings pass
      while the suites keep their other assertions
    And the suites that pin surrounding content stay green without edits:
      no test pins "git mv", no test pins the coder's "Read only from"
      wording, and the closingblock/receipts/skills-activation extracts of
      the coder and verifier report and receipt sections keep passing

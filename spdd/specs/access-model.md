# Domain: access-model

## Origin
- Specced and delivered from change `specifier-write-access` (merged
  2026-09-11, archived in `spdd/archive/specifier-write-access/`). This is a
  **new standalone spec domain**: before this change, `spdd/specs/` held no
  governing spec for the role access model — the `access` values declared in
  `agents/meta/*.yaml`, install.sh's rendered access grants, and the
  policy-doc wording that describes them. The change was discovered live
  during `flow-branch-checkout` dogfooding: `agents/meta/specifier.yaml` and
  `agents/meta/verifier.yaml` declared `access: readonly`, rendering to NO
  edit capability on both clients while both roles' own prompts require
  writing their core artifacts — installed specifier sessions silently
  completed with zero files written. Only the coder was renderable as
  readwrite.
- **Decision (settled):** both corrected roles get `access: readwrite`. A
  path-restricted new access level was considered and dropped: neither
  target client's permission layer can scope edits to paths (no "may write
  only spdd/"), so a new level would map to nothing mechanically
  enforceable — an illusion of least privilege. The honest minimal fix is
  readwrite for both, with the real boundary kept where it actually lives:
  prompt-level path ownership per role plus the never-commits law.
- Cross-references: the bump in this domain follows the policy of
  `spdd/specs/versioning.md` (tracked path `agents/meta/` → mandatory bump,
  graded minor). The e2e Background line in `spdd/specs/specifier-role.md`
  describing the specifier's tool grant was touched up by this change's
  merge (readwrite grants) — that file's domain is the specifier prompt's
  Output behavior, not the access model.
- Change `skills-activation` (merged 2026-09-11, archived in
  `spdd/archive/skills-activation/`) merged its render/docs MODIFY edges
  into this file's render-01 and docs-03 (the Claude `readwrite` grant
  gains `Skill`; the Client Integration readwrite bullet corrected). Its
  remaining scenarios (role skills activation, the orchestrator's
  delegation skills block, the adoption/rejection register, the 4.2.0
  bump) live in `spdd/specs/skills-activation.md`.
- Extended by change `optimize-test-suite` (merged 2026-09-14): adds five
  renderdedup scenarios (ADD `renderdedup-01..05`) verifying one-owner-per-
  facet deduplication of render coverage. Removes render-03 (git-HEAD byte-
  compare of rendered files), docs-01..04 (prose pins), and meta-03's
  byte-identical-to-HEAD pins. render-04 is re-keyed as the sole mapping-
  level owner via forced renders. The change's scenarios and end-to-end QA
  are preserved for history in `spdd/archive/optimize-test-suite/`, not
  reproduced here.

## Goal
The role access model, as implemented by the four `agents/meta/*.yaml`
files and rendered by install.sh: `specifier`, `coder`, and `verifier`
declare `access: readwrite` (edit capability, each for its own prompt-owned
artifact surfaces); `orchestrator` declares `access: orchestrateonly`. The
taxonomy stays exactly `readonly | readwrite | orchestrateonly` — no new
level. install.sh is never edited to deliver this: its mapping functions
already render readwrite correctly, and its readonly mapping branches stay
in code and docs as a defined level even though, after this change, no meta
file declares readonly. The safety boundary is prompt-level path ownership
per role plus the never-commits law, not tool absence — framework
permissions cannot scope edits to paths, and granting Edit/Write grants
artifact authorship, never commit authority.

## Shared contracts
The access values declared in `agents/meta/*.yaml` are the single input to
install.sh's mapping functions; the meta scenarios and the render scenarios
consume the same field identically (meta-01/02 are render-01/02's
precondition). The corrected access-model statement is stated identically
in AGENTS.md and CLAUDE.md (docs-02 pins the sync).

  ## Feature: agents/meta/specifier.yaml and agents/meta/verifier.yaml declare access: readwrite (extended by optimize-test-suite: render-03 removed, docs-01..04 removed, renderdedup-01..05 added)

  Background:
    Given the four role metadata files "agents/meta/specifier.yaml",
      "agents/meta/coder.yaml", "agents/meta/verifier.yaml", and
      "agents/meta/orchestrator.yaml", each carrying "name", "description",
      and "access" fields
    And "agents/meta/coder.yaml" declares "access: readwrite" and
      "agents/meta/orchestrator.yaml" declares "access: orchestrateonly"
      (both unchanged by this change)

  # ADD - meta-01: the specifier role's access is corrected from readonly to
  # readwrite -- it authors spdd/changes/<slug>/ (README.md, numbered
  # .feature files, OPEN_QUESTIONS.md), which no readonly grant can write.
  Scenario: meta-01
    When the reader reads "agents/meta/specifier.yaml"
    Then its "access" field reads "readwrite"
    And its "name" field still reads "antz-specifier"
    And its "description" field is unchanged

  # ADD - meta-02: the verifier role's access is corrected from readonly to
  # readwrite -- it merges into spdd/specs/, moves approved changes to
  # spdd/archive/, and appends spdd/changes/<slug>/REJECTED.md.
  Scenario: meta-02
    When the reader reads "agents/meta/verifier.yaml"
    Then its "access" field reads "readwrite"
    And its "name" field still reads "antz-verifier"
    And its "description" field is unchanged

  # ADD - meta-03: the other two roles are untouched -- coder stays
  # readwrite, orchestrator stays orchestrateonly, byte-for-byte.
  Scenario: meta-03
    When the reader reads "agents/meta/coder.yaml" and "agents/meta/orchestrator.yaml"
    Then "agents/meta/coder.yaml" still declares "access: readwrite" and is otherwise byte-for-byte unchanged
    And "agents/meta/orchestrator.yaml" still declares "access: orchestrateonly" and is otherwise byte-for-byte unchanged

  ### Invariants
  - No new access level is introduced: the taxonomy stays
    readonly | readwrite | orchestrateonly.
  - No prompt body changes: every file under "agents/prompts/" is
    byte-for-byte unchanged (the path-ownership rules there are already
    correct -- the boundary is prompt discipline, not tool absence).
  - install.sh is byte-for-byte unchanged by this sub-spec (the mapping
    functions already render readwrite correctly).
  - The safety boundary narrative survives: no role ever commits; each
    role's writable surface is owned by its own prompt's rules, enforced at
    the prompt level, never by a path-scoped permission (impossible on both
    target clients).

## Feature: install.sh renders specifier and verifier with full edit capability, coder and orchestrator unchanged

  Background:
    Given "agents/meta/specifier.yaml" and "agents/meta/verifier.yaml" declare "access: readwrite" (meta-01, meta-02)
    And "agents/meta/coder.yaml" declares "access: readwrite" and "agents/meta/orchestrator.yaml" declares "access: orchestrateonly"
    And the pre-change (readonly) renders of specifier and verifier carried "tools: Read, Grep, Glob, Bash" on Claude Code and "edit: deny" on OpenCode

  # MODIFY - render-01 (originally delivered by specifier-write-access; the
  # readwrite tools string was MODIFIED by change skills-activation, merged
  # 2026-09-11 — the Claude readwrite grant gains the `Skill` tool): the
  # corrected roles render on Claude Code with Edit, Write, and Skill
  # granted.
  Scenario Outline: render-01
    When install.sh renders "agents/meta/<role>.yaml" for Claude Code
    Then the rendered frontmatter carries "tools: Read, Grep, Glob, Bash, Edit, Write, Skill"

    Examples:
      | role       |
      | specifier  |
      | coder      |
      | verifier   |

  # ADD - render-02: the corrected roles render on OpenCode with edit
  # allowed, task delegation denied, subagent mode kept.
  Scenario Outline: render-02
    When install.sh renders "agents/meta/<role>.yaml" for OpenCode
    Then the rendered frontmatter carries "mode: subagent"
    And "permission:" carries "edit: allow"
    And "permission:" carries "task: deny"

    Examples:
      | role       |
      | specifier  |
      | verifier   |

  # ADD - render-04: the readonly mapping semantics are preserved in
  # install.sh even though no meta file declares readonly anymore -- the
  # mapping is a defined contract (kept verbatim), not dead-code bait.
  Scenario: render-04
    When the reader reads install.sh's access-mapping functions
    Then "readonly" still maps to "Read, Grep, Glob, Bash" (no Edit/Write) on Claude Code
    And "readonly" still maps to "edit: deny" and "task: deny" on OpenCode
    And the mapping functions' behavior is unchanged from the pre-change install.sh

  ### Invariants
  - The "antz:generated version=X -- do not edit by hand; regenerate with
    install.sh" marker format is unchanged (changing it would be a
    major-grade contract break and would break the /antz-set-model
    management check).
  - install.sh's mapping code is byte-for-byte unchanged: this change
    touches meta files only; install.sh itself is not edited at all.
  - After this change no meta file declares readonly, yet the readonly
    mapping remains a defined level (docs and mapping both keep it).
  - Renders are still deterministic from (prompt body, meta access, source
    VERSION); nothing else about the render pipeline changes.

## Feature: AGENTS.md, CLAUDE.md, and docs/orchestrator.md access-model wording matches reality (docs-01..04 removed by optimize-test-suite)

  This Feature is deleted per the owner's revised scope: all history/evolution
  calibration and prose pins are deleted; the access model's product truth
  stays pinned by the meta declarations (meta-01..03) and the render mappings
  (render-01, render-02, render-04). The retained scenario ids
  (docs-01..04) no longer exist in any suite.

## Feature: the role agents' render coverage has one owner per facet and
  asserts only the current version's behavior (from optimize-test-suite)

  Background:
    Given the readwrite Claude tools line "Read, Grep, Glob, Bash, Edit,
      Write, Skill" rendered from agents/meta/specifier.yaml,
      agents/meta/coder.yaml, and agents/meta/verifier.yaml
    And the ownership map over the retained render suites, one owner per
      facet: access-model owns the role agents' access-to-grants mapping
      pins (the Claude readwrite tools line, the OpenCode readwrite shape,
      the readonly and orchestrateonly mapping levels) and the meta
      declarations; skills-activation-render owns the Skill-grant scoping,
      the OpenCode frontmatter shape guard, and marker format plus
      render determinism; description-quoting owns the rendered-description
      quoting at its three render sites; libdirinstall owns install
      mechanics, --check, and the libdir scripts' marker stamping;
      header-marker owns marker detection anchoring, backups, and
      install.sh's header-comment statements; orchestrator-render-sync owns
      the installed-libdir-vs-source drift guard

  # ADD - renderdedup-01: the render-01 id is carried by access-model alone,
  # covering all three readwrite roles.
  Scenario: renderdedup-01
    When the access-model suite runs
    Then render-01 is registered for specifier, coder, and verifier — the
      sole registrations pinning the role agents' Claude readwrite tools
      line
    And render-02 stays registered for specifier and verifier (OpenCode
      mode: subagent, edit: allow, task: deny)

  # REMOVE - renderdedup-02: the duplicated render-01 registrations are
  # removed from the non-owning suite.
  Scenario: renderdedup-02
    When the skills-activation-render suite runs
    Then its three render-01 registrations — the same rendered bytes
      access-model render-01 pins — are gone
    And render-02, render-03, and render-04 stay registered under their
      ids, and the e2e-render-01 skip stub stays

  # MODIFY - renderdedup-03: the skills-activation-render suite is re-keyed
  # to current-version behavior only.
  Scenario: renderdedup-03
    When the skills-activation-render suite runs
    Then render-02 asserts only the Skill-grant scoping: forced readonly
      and orchestrateonly renders grant no Skill (the exact mapping strings
      are access-model render-04's facet)
    And render-03 asserts only the OpenCode frontmatter shape: no
      permission.skill block and no tools: entry in any rendered OpenCode
      frontmatter
    And render-04 asserts the marker format on every rendered agent and
      command file and that a second render of the same tree is
      byte-identical
    And the "only rendered change vs the pre-change renderer" scoping
      registration is deleted, with the controlled-mutation fixture
      machinery removed alongside it — not left as dead code

  # MODIFY - renderdedup-04: the access-model suite loses its git-HEAD
  # mechanisms; render-04 becomes the sole mapping-level owner.
  Scenario: renderdedup-04
    When the access-model suite runs
    Then render-03 — the byte-compare of rendered coder/orchestrator files
      against git HEAD's meta renders — is removed entirely
    And meta-03 keeps its access/name/description field checks and its
      byte-identical-to-HEAD pins are removed
    And render-04, via forced readonly and orchestrateonly renders, pins
      the mapping levels once: readonly maps to "Read, Grep, Glob, Bash"
      on Claude (no Edit, Write, or Skill) and to mode: subagent with
      edit: deny and task: deny on OpenCode; orchestrateonly maps to
      "Read, Grep, Glob, Bash, Agent" on Claude (no Skill); markers present
    And render-04's install.sh source-line greps — a third mechanism for
      the mapping coverage its functional renders already prove — are
      removed

  # REMOVE - renderdedup-05: the docs prose pins are deleted per the
  # owner's revision.
  Scenario: renderdedup-05
    When the access-model suite runs
    Then docs-01..04 are no longer registered: no exact-phrase assertion
      of AGENTS.md, CLAUDE.md, or docs/orchestrator.md prose remains in the
      retained suites
    And the access model's product truth stays pinned by the meta
      declarations (meta-01..03, minus HEAD pins) and the render mappings
      (render-01, render-02, render-04)

  ### Invariants
  - The ownership map is the dedup law: a future check on an owned facet
    extends the owning suite instead of re-pinning elsewhere.
  - No genuine render coverage is lost: every removed registration's
    verifiable content is either deleted by the owner's revision
    (history/evolution calibration, git-HEAD mechanisms, prose pins) or
    retained exactly once in its owning suite — the orchestrateonly string
    in access-model render-04, the OpenCode shape in skills-activation-render
    render-03.
  - Current-version law for both suites: zero real-tree-vs-git-HEAD
    comparisons, zero byte-pins vs git HEAD, zero exact-phrase prose
    assertions of prompts/docs.
  - No cross-suite source scans are introduced: the tools line's uniqueness
    is carried by this map and the specified removals, never by a suite
    asserting other test files' sources (the decoupling law).
  - The four non-owning suites (description-quoting, libdirinstall,
    header-marker, orchestrator-render-sync) are untouched: their facets are
    already single-owned; the map only declares them.

## Feature: VERSION bumped to 4.1.0 with a matching CHANGELOG.md entry in the same working tree (bump-01..03 retired by optimize-test-suite)

  This Feature's scenario ids (bump-01..03) are retired per the owner's
  revised scope: the change is tests-only, no VERSION/CHANGELOG bump is
  introduced, and the frozen-history calibration that these scenarios pinned
  is deleted. The version check shrinks to two assertions in
  tests/versioncurrent_test.sh (versioncurrent-02, in
  `spdd/specs/versioning.md`).

## End-to-end QA suite

Operates at the real product UI: invoking the installed agents, install.sh's
CLI against the user's machine, and reading the docs. All scenarios were
delivered by `specifier-write-access` (all tagged ADD) and verified live by
the verifier at merge time (e2e-render-01/02 and e2e-bump-01 executed
against the real HOME; e2e-meta-01/02 observed live as the specifier's
authored `spdd/changes/specifier-write-access/` artifacts and the
verifier's own merge+archive writes; e2e-docs-01 verified by reading the
docs against the meta files).

  Background:
    Given a local checkout of a test repo that is a git repository
    And antz installed for the current client (antz:generated markers
      present, version = the repo's current VERSION)

  # ADD - e2e-meta-01: a specifier invocation actually writes its artifacts.
  Scenario: e2e-meta-01
    When the user invokes the specifier with a small natural-language change request
    Then "spdd/changes/<slug>/" is populated with "README.md" and numbered ".feature" files
    And no error or silent no-op occurred for lack of edit permission

  # ADD - e2e-meta-02: a verifier invocation actually writes its artifacts.
  Scenario: e2e-meta-02
    Given a coder has completed one sub-spec of a change and the orchestrator has delegated verification
    When the user invokes the verifier for that change
    Then either "spdd/specs/" gained the merged domain content and the change dir moved to "spdd/archive/<slug>/"
    Or "spdd/changes/<slug>/REJECTED.md" was appended with a rejection entry
    And no error or silent no-op occurred for lack of edit permission

  Background:
    Given the user's machine has the pre-change antz installed (installed copies marked "antz:generated version=<pre-change VERSION>", specifier/verifier without edit capability)

  # ADD - e2e-render-01: reinstalling overwrites the hand-patched temporary
  # edit grants with the real ones, same marker format.
  Scenario: e2e-render-01
    When the user runs "./install.sh --all" from the post-change checkout
    Then the installed "~/.claude/agents/antz-specifier.md" and "~/.claude/agents/antz-verifier.md" carry "tools: Read, Grep, Glob, Bash, Edit, Write"
    And the installed OpenCode copies carry "edit: allow" and "task: deny" and "mode: subagent"
    And every installed file is marked "antz:generated version=<new VERSION>" in the unchanged marker format
    And the installed coder and orchestrator copies carry their unchanged grants

  # ADD - e2e-render-02: --check sees the drift and prints the changelog
  # before reinstall, and reports up to date after.
  Scenario: e2e-render-02
    When the user runs "./install.sh --check" before reinstalling
    Then it reports the installed-to-source version drift for both clients and prints the new "CHANGELOG.md" entry
    When the user runs "./install.sh --all" and then "./install.sh --check" again
    Then "--check" reports "already up to date" for both clients

  # ADD - e2e-docs-01: a user reading the docs derives the real access
  # model, with no contradiction left against the meta files or the roles'
  # prompts.
  Scenario: e2e-docs-01
    When the user reads the "## Gotchas" sections of "AGENTS.md" and "CLAUDE.md" and then the four "agents/meta/*.yaml" files
    Then the documented access values match the declared ones for all four roles
    And no doc statement contradicts a role prompt's own artifact-writing requirements

  # ADD - e2e-bump-01: the bump is real, discoverable, and consistent with
  # the --check machinery the versioning policy describes.
  Scenario: e2e-bump-01
    When the user reads "VERSION" and the top of "CHANGELOG.md"
    Then "VERSION" reads "4.1.0" and the top section is "[4.1.0] - 2026-09-11" describing the access correction
    And "./install.sh --check" on a machine with pre-change installed copies reports the drift to "4.1.0" and prints the "[4.1.0]" entry

## Out of scope
- `agents/prompts/*` bodies (path-ownership rules there are already correct).
- Any edit to `install.sh` (including no new access level and no mapping
  change); the flow script (`antz-flow.sh`); the `worktree` branch and its
  historical docs (`docs/worktree-isolation-plan*.md`).
- Path-scoped permission machinery of any kind; mechanical bump enforcement.

## Relevant files
- `agents/meta/specifier.yaml`, `agents/meta/verifier.yaml` — the two
  corrected files (line 3: `access: readonly` → `readwrite`).
- `agents/meta/coder.yaml`, `agents/meta/orchestrator.yaml` — untouched
  regression guards.
- `install.sh` — the mapping functions
  (`claude_tools_for_access`, `opencode_edit_perm_for_access`,
  `opencode_mode_for_access`, `opencode_task_perm_for_access`), read only;
  byte-for-byte unchanged (render-04).
- `AGENTS.md:19`, `CLAUDE.md:19` — the access-model gotcha bullet (docs-01,
  docs-02); `AGENTS.md:33`, `CLAUDE.md:32` — Client Integration mapping
  bullets (docs-03).
- `docs/orchestrator.md:87-101` — delegation-scoping paragraph (docs-04).
- `CHANGELOG.md`, `VERSION` — the 4.1.0 bump (bump-01..03).
- `tests/access-model_test.sh` — one test per scenario id (meta-01..03,
  render-01..04, docs-01..04, bump-01..03), SKIP stubs for all `e2e-*` ids.
- `tests/skills-activation-render_test.sh` — one test per scenario id
  (render-02, render-03, render-04, renderdedup-02, renderdedup-03), SKIP
  stubs for e2e-render-01.
- `spdd/archive/specifier-write-access/` — the delivering change, preserved
  for history.
- `spdd/archive/optimize-test-suite/` — the dedup/current-version change,
  preserved for history.

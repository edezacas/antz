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

## Feature: agents/meta/specifier.yaml and agents/meta/verifier.yaml declare access: readwrite

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

  # ADD - render-03: regression guard -- the two untouched roles render
  # byte-for-byte identically to the pre-change render.
  Scenario: render-03
    When install.sh renders "agents/meta/coder.yaml" and "agents/meta/orchestrator.yaml" for both clients
    Then every rendered file is byte-for-byte identical to rendering the pre-change meta files for both clients

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

## Feature: AGENTS.md, CLAUDE.md, and docs/orchestrator.md access-model wording matches reality

  Background:
    Given "AGENTS.md" and "CLAUDE.md", each carrying a "## Gotchas" bullet that currently reads (in its access-model part): "access is readonly | readwrite | orchestrateonly. The specifier/verifier roles are readonly (no edit/write capability); the coder role is readwrite (the only role that modifies files); the orchestrator role is orchestrateonly -- readonly plus a delegation capability, used only by it."
    And "docs/orchestrator.md"'s "Platform delegation scoping" section currently states: "the specifier/verifier readonly boundary is real"

  # ADD - docs-01: AGENTS.md's access-model gotcha states the corrected
  # model -- three readwrite roles with their artifact surfaces, one
  # orchestrateonly role, boundary at prompt level.
  Scenario: docs-01
    When the reader reads the "## Gotchas" section of "AGENTS.md"
    Then its access-model bullet states that the specifier, coder, and verifier roles are "readwrite" (edit capability, each for its own prompt-owned artifact surfaces: the specifier authors "spdd/changes/<slug>/", the coder implements sub-specs, the verifier merges into "spdd/specs/" and owns "spdd/archive/" moves and "REJECTED.md" appends)
    And it states that the orchestrator role remains "orchestrateonly" -- readonly-equivalent tools plus a delegation capability, used only by it
    And it states that the safety boundary is prompt-level path ownership per role plus the never-commits law, not tool absence -- framework permissions cannot scope edits to paths
    And it does not state that any of specifier, coder, or verifier is "readonly" or that the coder is "the only role that modifies files"

  # ADD - docs-02: CLAUDE.md states the identical corrected model (the two
  # policy docs duplicate each other and must not fork).
  Scenario: docs-02
    When the reader compares the access-model gotcha bullets of "AGENTS.md" and "CLAUDE.md"
    Then they state the identical corrected model: specifier/coder/verifier "readwrite", orchestrator "orchestrateonly", prompt-level boundary, never-commits law intact

  # MODIFY - docs-03 (originally delivered by specifier-write-access; the
  # readwrite Client Integration mapping sentence was MODIFIED by change
  # skills-activation, merged 2026-09-11 — readwrite now states full edit
  # access plus, on Claude Code, the `Skill` tool grant, with the OpenCode
  # side inheriting the native skill tool by default): the wrong claim is
  # gone everywhere in both policy docs, not only from the gotcha bullet.
  Scenario: docs-03
    When the reader reads "AGENTS.md" and "CLAUDE.md" in full
    Then neither file anywhere states that the specifier or verifier role is "readonly", lacks edit/write capability, or that the coder is the only role that modifies files
    And the "## Client Integration" mapping description states the defined mapping levels ("access: readonly" maps to no edit/write capability, "readwrite" to full edit access plus, on Claude Code, the "Skill" tool grant with OpenCode agents inheriting the client's native skill tool by default, "orchestrateonly" to readonly plus delegation) -- noting that after the access-model change no role declares readonly, while install.sh keeps the mapping

  # ADD - docs-04: docs/orchestrator.md's delegation-scoping paragraph is
  # corrected without weakening its verified platform claim.
  Scenario: docs-04
    When the reader reads "docs/orchestrator.md"'s "Platform delegation scoping" section
    Then it no longer states that a specifier/verifier readonly boundary is real
    And it still states that Claude Code's subagent "tools:" list is a strict, enforced allowlist (the verified platform fact, which is why the old readonly denial was real)

  ### Invariants
  - The Governing-rule narrative is untouched: no role, including the
    orchestrator, may depend on another role's conversational output.
  - The never-commits law is untouched and restated where the access model
    is described: granting Edit/Write grants artifact authorship, never
    commit authority (no role carries a commit fence; committing is always
    the human's follow-up).
  - Coder ownership rules stay as-is: the coder only reads "spdd/changes/"
    and never touches "spdd/specs/" or "spdd/archive/" -- readwrite for the
    verifier does not weaken that.
  - The historical sibling-variant docs ("docs/worktree-isolation-plan*.md")
    are not corrected: they describe the "worktree" branch's variant
    historically.
  - The stale e2e Background line in "spdd/specs/specifier-role.md" ("the
    specifier's own tool grant is Read, Grep, Glob, Bash -- readonly
    access") was drift created by this change, touched up by the verifier
    during its merge (readwrite grants); the coder never edits
    "spdd/specs/".

## Feature: VERSION bumped to 4.1.0 with a matching CHANGELOG.md entry in the same working tree

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit changing "agents/prompts/", "agents/meta/", or "install.sh" bumps "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" read "4.0.0" (flow-branch-checkout's pending, uncommitted bump) at this change's start
    And "CHANGELOG.md" carried an uncommitted "[4.0.0] - 2026-09-11" section (flow-branch-checkout)

  # ADD - bump-01: the bump is present -- VERSION reads 4.1.0 and
  # CHANGELOG.md gains a matching [4.1.0] section, layered above [4.0.0].
  Scenario: bump-01
    When the reader reads "VERSION"
    Then it reads exactly "4.1.0"
    And "CHANGELOG.md" contains a "[4.1.0] - 2026-09-11" section above the "[4.0.0]" section
    And that section's Changed entries describe the specifier and verifier access correction to "readwrite", the unchanged render for coder/orchestrator, the retained readonly mapping, and the docs correction

  # ADD - bump-02: the grade is minor, stated and justified against the
  # versioning table.
  Scenario: bump-02
    When the reader reads the "[4.1.0]" entry against the "## Versioning" gradation
    Then the change grades as "minor": a behavior change to the roles' rendered agents (Edit/Write granted, edit allowed)
    And it does not grade as "major": the access-model taxonomy, the access-to-frontmatter mapping, the "antz:generated" marker format, the directory layout, and the install locations are all unchanged

  # ADD - bump-03: shared-file edits are strictly additive over the pending
  # flow-branch-checkout edits -- never reverting them.
  Scenario: bump-03
    When the reader inspects this change's edits to "VERSION", "CHANGELOG.md", "AGENTS.md", and "CLAUDE.md"
    Then each edit adds or corrects on top of flow-branch-checkout's pending hunks
    And flow-branch-checkout's pending content survives: "VERSION" keeps its 4.0.0 history via the "[4.0.0]" section, the flow-branch gotcha wording in both docs, the orchestrator.prompt and antz-flow changes, and tests/antz-flow_test.sh are all still present and unmodified by this change

  ### Invariants
  - No tag is created by any role: per the never-commits law the local
    "v4.1.0" tag is the human's commit-time follow-up, created against the
    human's bump commit.
  - The CHANGELOG entry follows Keep a Changelog format and the file's
    existing entry style.
  - VERSION is the only content of the "VERSION" file ("4.1.0", trailing
    newline as before).

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
- `spdd/archive/specifier-write-access/` — the delivering change, preserved
  for history.

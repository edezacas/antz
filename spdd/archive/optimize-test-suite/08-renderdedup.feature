# Sub-spec 08 — render-01 dedup: one owner per render facet, current-version
# behavior only.
# Destination domain: `access-model` (the render/access-domain spec; every
# merge edge of this sub-spec lands in `spdd/specs/access-model.md`).
# Dependency order: 8 (the suites source the harness library from sub-spec
# 01; otherwise independent of 02-07).
# Coherence note for the verifier: this sub-spec supersedes sub-spec 05's
# stale clause "access-model_test.sh still registers meta-01..03,
# render-01..04, and docs-01..04" for exactly two ids — render-03 (removed)
# and docs-01..04 (removed) — per the owner's revision below. meta-01..02,
# render-01, render-02, render-04 stay registered.

Feature: the role agents' render coverage has one owner per facet and
  asserts only the current version's behavior
  Two suites pin the identical rendered readwrite Claude tools line —
  access-model render-01 and the skills-activation-render suite's three
  render-01 registrations. The access-model suite owns the role agents'
  access-to-grants mapping pins and absorbs the render-01 id whole; the
  skills-activation-render suite keeps only what is uniquely its own. Per
  the owner's revision, the retained render coverage is current-version
  behavior only: all history/evolution calibration and prose pins are
  deleted — zero real-tree-vs-git-HEAD comparisons, zero byte-pins vs git
  HEAD, zero exact-phrase prose assertions of prompts/docs (the sole
  repo-wide exception, Working-Root triplication consistency in
  roles_test.sh, is not this sub-spec's).

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

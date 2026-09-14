# Domain: versioning

## Origin
- Specced and delivered from change `versioning-install-sh` (merged
  2026-09-08). Before it, `AGENTS.md` and `CLAUDE.md` stated that `VERSION`/
  `CHANGELOG.md` track only `agents/prompts/` and `agents/meta/`, and that
  "Changes elsewhere (`install.sh`, docs) don't require a bump". That is
  wrong: `install.sh` renders the installed commands/agents directly and
  embeds the source `VERSION` in each installed file's `antz:generated`
  marker comment, so an unbumped `install.sh`-only change leaves installed
  copies silently stale (`install.sh --check` would report them as up to
  date). The change expanded the tracked set to include `install.sh`, removed
  the exemption sentence, preserved the docs-only no-bump clause explicitly,
  and recorded the rationale. The change's scenarios and end-to-end QA are
  preserved for history in `spdd/archive/versioning-install-sh/`, not
  reproduced here. This domain is a NEW standalone spec domain: no prior
  governing spec covered repo policy/versioning docs (`spdd/specs/` held only
  `set-model.md`, the `/antz-set-model` command domain).

## Goal
The repo's versioning policy, as documented in `AGENTS.md` and `CLAUDE.md`
(two `## Versioning` sections that duplicate each other and must stay in
sync): `VERSION` (semver) and `CHANGELOG.md` (Keep a Changelog format) track
changes to `agents/prompts/`, `agents/meta/`, and `install.sh`. Any commit
that changes any of those three must bump `VERSION` and add a matching
`CHANGELOG.md` entry in the same commit — one patch/minor/major scale for
`agents/` and `install.sh` changes alike. Changes to docs (`AGENTS.md`,
`CLAUDE.md`, `docs/`, `spdd/`) and to `tests/` don't require a bump. The rule
is policy documentation only: no mechanical enforcement (script, hook, or CI
check) verifies bumps; enforcement is the maintainer's discipline plus the
existing `--check` report.

## Shared contracts

None required: this is a single docs-layer domain. The only cross-file
contract is internal to the docs: `AGENTS.md` and `CLAUDE.md` must state the
identical rule (versioning-06).

## Feature: Repo versioning policy - VERSION/CHANGELOG.md track agents/, and now install.sh

  Background:
    Given the repo files "AGENTS.md" and "CLAUDE.md", each carrying a
      "## Versioning" section (three bullets: the tracked-set/same-commit
      rule, the marker embedding/--check description, and the local vX.Y.Z
      tag per bump)
    And "install.sh" renders every installed agent and command file with an
      "antz:generated version=X.Y.Z" marker comment embedding the source
      VERSION, and "./install.sh --check" compares the installed specifier
      agent copy's embedded version against the source VERSION, printing the
      intervening CHANGELOG.md entries when they differ

  # ADD - versioning-01: the tracked set expands to include install.sh, and
  # the same-commit requirement carries over verbatim in structure. A commit
  # is bump-mandatory if it touches ANY of the three, regardless of what else
  # it contains (docs, tests, spdd/ - mixed commits are still bump commits).
  Scenario: versioning-01
    When the reader reads the "## Versioning" section of AGENTS.md
    Then it states that "VERSION" (semver) and "CHANGELOG.md" (Keep a
      Changelog format) track changes to "agents/prompts/", "agents/meta/",
      and "install.sh"
    And it states that any commit that changes any of those three must bump
      "VERSION" and add a matching "CHANGELOG.md" entry in the same commit
    And the same-commit bump requirement holds regardless of what else the
      commit changes - a commit touching "agents/" and/or "install.sh"
      together with docs or tests is still a bump commit

  # ADD - versioning-02: the wrong sentence is gone, and nothing equivalent
  # takes its place. The old sentence singled out install.sh as bump-exempt;
  # any wording with that effect must disappear from both files.
  Scenario: versioning-02
    When the reader reads AGENTS.md and CLAUDE.md in full
    Then neither file contains the sentence "Changes elsewhere (install.sh,
      docs) don't require a bump"
    And neither file contains any other statement that a change to
      "install.sh" is exempt from the "VERSION"/"CHANGELOG.md" bump
      requirement

  # ADD - versioning-03: the docs-only no-bump clause is preserved
  # explicitly, not left to inference from the removal of the old sentence.
  # The stated rule must resolve every row of the table unambiguously - a
  # reader applying it to a real commit never lands on "unclear". Note the
  # first row pair: the delivering change itself is the worked example
  # (docs-only commit, no bump).
  Scenario Outline: versioning-03
    When the reader reads the "## Versioning" section of AGENTS.md (and
      CLAUDE.md)
    Then it explicitly states which paths are NOT tracked and require no
      "VERSION"/"CHANGELOG.md" bump
    And the stated rule resolves the row's commit as: <resolution>

    Examples:
      | a commit that changes only            | resolution                                             |
      | agents/prompts/                       | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | agents/meta/                          | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | install.sh                            | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | agents/ and install.sh in one commit  | a VERSION bump + matching CHANGELOG.md entry, same commit |
      | AGENTS.md, CLAUDE.md, docs/, or spdd/ | no VERSION bump and no CHANGELOG.md entry             |
      | tests/                                | no VERSION bump and no CHANGELOG.md entry             |

  # ADD - versioning-04: the gradation applies to install.sh changes exactly
  # as the existing gradation applies to agents/ changes - one scale, not a
  # second rubric. The rows pin the boundary of each grade with concrete
  # install.sh-shaped examples. A commit touching several tracked paths is
  # graded by its most severe component.
  Scenario Outline: versioning-04
    When the reader reads the "## Versioning" section
    Then it applies the same patch/minor/major scale to "install.sh" changes
      as to "agents/" changes
    And it grades the row's install.sh-only change as a <grade> bump

    Examples:
      | install.sh-only change                                                                                                                             | grade |
      | wording-only tweak: comment, usage/echo string, or internal refactor with no change to rendered output or reported behavior                        | patch |
      | behavior change: rendered agent/command bodies, flags, install paths, detection logic, or the --check report change                                 | minor |
      | breaking change to the workflow contract or the rendered command contract (e.g. the "antz:generated" marker format the /antz-set-model management check depends on, or the access-to-frontmatter mapping) | major |

  # ADD - versioning-05: the rationale is recorded in the section, so a
  # future maintainer can re-derive the rule instead of relitigating it. The
  # rationale must not promise any new machinery: it relies on the existing
  # marker/version/--check behavior, unchanged by the change.
  Scenario: versioning-05
    When the reader reads the "## Versioning" section
    Then it records why "install.sh" is tracked: "install.sh" renders the
      installed agent and command files directly and embeds the source
      "VERSION" in each installed file's "antz:generated" marker comment
    And it records that without a bump, "./install.sh --check"'s version
      comparison reports no drift, so installed command/agent copies
      silently go stale after an install.sh-only change - the only defense
      is the documented bump rule

  # ADD - versioning-06: the two policy docs stay in sync - they duplicate
  # each other, and the rule must not fork between them.
  Scenario: versioning-06
    When the reader compares the "## Versioning" sections of AGENTS.md and
      CLAUDE.md
    Then they state the identical rule: same tracked set, same same-commit
      bump requirement, same preserved docs-only no-bump clause, same
      gradation
    And a future rule change updates both files in the same commit - neither
      file may lag the other

  # ADD - versioning-07: the section's other two bullets survive with
  # unchanged meaning, and the tag rule now covers install.sh-mandated bumps
  # without being reworded.
  Scenario: versioning-07
    When the reader reads the "## Versioning" section
    Then it still states that "install.sh" embeds the source "VERSION" in
      each installed file's marker comment, that every run compares the
      installed copy's embedded version and prints the intervening
      "CHANGELOG.md" entries when newer, and that "./install.sh --check"
      only prints that report without writing files
    And it still states that every "VERSION" bump gets a local "vX.Y.Z" git
      tag created against the bumping commit, tags not pushed automatically -
      now applying to install.sh-mandated bumps as well

  ### Invariants
  - The rule is policy documentation only. Nothing adds mechanical
    enforcement (no script, hook, or CI check verifying bumps); enforcement
    is the maintainer's discipline plus the existing --check report.
  - The delivering change touched ONLY "AGENTS.md" and "CLAUDE.md" (the
    "## Versioning" first bullet) plus the single scope line of
    "CHANGELOG.md". "install.sh" is byte-for-byte untouched - including its
    header comment at install.sh:21, which restates the OLD tracked set
    ("VERSION + CHANGELOG.md track changes to agents/prompts/ and
    agents/meta/.") and remains stale as accepted, recorded drift: the next
    change that legitimately touches "install.sh" (which must bump under
    this rule anyway) should correct line 21 as part of its mandatory-bump
    commit. **CLOSED** by change `orchestrator-fast-path` (renderinject-06,
    merged 2026-09-11): that change touched install.sh legitimately, bumped to
    4.3.0, and corrected the header sentence to name all three tracked paths
    ("agents/prompts/, agents/meta/, and install.sh"); the recorded drift no
    longer exists.
  - The delivering change itself required no bump and shipped none: its diff
    is docs-only, which the preserved docs-only clause classifies as no-bump
    (worked example for versioning-03's "AGENTS.md, CLAUDE.md, docs/, or
    spdd/" row; observed as e2e-qa-04).
  - The rule is forward-looking. It mandates no retroactive "CHANGELOG.md"
    entries or tags for past install.sh-only changes (notably
    set-model-interactive-picker, shipped without a bump), and no rewrite of
    history in "spdd/specs/" or "spdd/archive/".
  - "VERSION"/"CHANGELOG.md" edits that ARE a bump are part of that bump,
    never separately tracked changes requiring a further bump.
  - Mixed-commit grading (versioning-04): the commit's grade is the most
    severe component's grade.
  - Supersession: this domain supersedes the historical invariant recorded
    in `spdd/specs/set-model.md` (Invariants: "A change confined to
    `install.sh` does not touch `agents/prompts/` or `agents/meta/` and so
    does not require a `VERSION`/`CHANGELOG.md` bump"), which was true under
    the old rule at that change's merge time and is deliberately left
    untouched there; the historical versioning notes in `spdd/archive/`
    READMEs are likewise immutable records of their time.

## Feature: VERSION bumped to 4.4.0 with a matching CHANGELOG.md entry describing the flow fixes, graded minor

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.3.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.3.0] - 2026-09-11"

  # ADD - bump440-01: the bump is present — VERSION reads 4.4.0 and
  # CHANGELOG.md gains a matching [4.4.0] section above [4.3.0].
  Scenario: bump440-01
    When the reader reads "VERSION"
    Then it reads exactly "4.4.0" (the version value plus one trailing
      newline, its only content)
    And "CHANGELOG.md" carries a "## [4.4.0] - <date>" section above the
      "[4.3.0]" section, in Keep a Changelog format and the file's existing
      entry style
    And that section's Added/Changed entries describe the change's substance:
      the orchestrator delegating never-specified changes to the specifier
      with the mid-session-deletion and post-verifier routing, the dedup
      guard's two enumerated exceptions, step 5 detecting the verifier's
      outcome from disk with the release-gate disambiguation, the defined
      waiting-user stop variant, the coder's write-surface ownership bullet,
      the verifier's plain-mv archive step with its reason, and the literal
      "test_command=none" sentinel with the probe's acceptance and the
      never-execute rule
    And every earlier CHANGELOG entry is byte-for-byte untouched, so the
      pinned history keeps passing: "[4.3.0]" still sits above "[4.2.1]" and
      still describes its changes

  # ADD - bump440-02: the grade is minor, stated and justified against the
  # versioning table — and no tag is created by any role.
  Scenario: bump440-02
    When the reader reads the "[4.4.0]" entry against the versioning gradation
    Then the change grades as "minor": it changes role behavior — the
      orchestrator's routing and outcome detection, the coder's ownership
      bullet, the verifier's archive instruction — which the gradation
      reserves for minor, not patch (not wording-only: rendered agent bodies
      and role behavior both change)
    And it does not grade as "major": the workflow contract, the
      "antz:generated" marker format, the access model, the directory layout,
      and the install locations are all unchanged — the probe's output
      vocabulary, the release machine lines, the receipt grammar's shape, and
      the four-subcommand flow script all survive
    And "install.sh" itself is untouched: the bump flows into installed copies
      only through the re-render, via the normal "./install.sh --all"
      follow-up
    And no tag is created by any role: the local "v4.4.0" tag is the human's
      commit-time follow-up, created against the human's bump commit and not
      pushed automatically

  ### Invariants
  - The versioning policy is unchanged: this bump follows the existing
    gradation, not a new rubric.
  - No role commits anything; the tag is the human's commit-time follow-up.

## Feature: VERSION bumped to 4.5.0 with a matching CHANGELOG.md entry describing the flow-script guards, graded minor (from 03-bump450.feature, change `flow-script-guards`)

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.4.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.4.0] - 2026-09-12"

  # ADD - bump450-01: the bump is present — VERSION reads 4.5.0 and
  # CHANGELOG.md gains a matching [4.5.0] section above [4.4.0].
  Scenario: bump450-01
    When the reader reads "VERSION"
    Then it reads exactly "4.5.0" (the version value plus one trailing
      newline, its only content) and agrees with the newest topmost
      CHANGELOG entry
    And "CHANGELOG.md" carries a dated "## [4.5.0] - <date>" section above
      "## [4.4.0]", in the file's Keep a Changelog style (category headings
      with bold lead-in bullets)
    And the "## [4.4.0]" section and every entry below it are byte-for-byte
      unchanged

  # ADD - bump450-02: the [4.5.0] entry describes the change and states the
  # minor grade with its versioning-table justification.
  Scenario: bump450-02
    When the reader reads the "## [4.5.0]" section
    Then it describes the flow script's mechanical slug validation
      ("state=bad_slug", non-destructive), the new-flow tree guard
      ("state=tree_dirty" only when the change dir is absent and the marker
      branch would be newly created, skipped on resume), and the advisory
      "dirty=yes" resume line
    And it describes the orchestrator prompt wiring (the step-1 ensure
      instructions, the latch, and the Report Format now name the new states)
      and the rewritten/added flow-suite tests (including the scripts
      byte-unchanged guard re-scoped off antz-flow.sh)
    And it states the grade as minor, not patch and not major, naming the
      behavior change to the flow script and orchestrator routing (not the
      wording-only patch) and the surviving workflow contract, marker format,
      access model, directory layout, install locations, four subcommands,
      probe output vocabulary, release machine lines, and receipt grammar (not
      major)
    And it states that install.sh itself is untouched and the bump reaches
      installed copies only through the normal "./install.sh --all" re-render,
      and that no role creates the v4.5.0 tag (it is the human's commit-time
      follow-up)

  ### Invariants
  - The versioning policy is unchanged: this bump follows the existing
    gradation, not a new rubric.
  - No role commits anything; the v4.5.0 tag is the human's commit-time
    follow-up.

## Feature: VERSION bumped to 4.6.0 with a matching CHANGELOG.md entry describing the precision-gap fixes, graded minor (from 05-bump460.feature, change `precision-gaps`)

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.5.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.5.0] - 2026-09-12"

  # ADD - bump460-01: the bump is present — VERSION reads 4.6.0 and
  # CHANGELOG.md gains a matching [4.6.0] section above [4.5.0].
  Scenario: bump460-01
    When the reader reads "VERSION"
    Then it reads exactly "4.6.0" (the version value plus one trailing
      newline, its only content) and agrees with the newest topmost
      CHANGELOG entry
    And "CHANGELOG.md" carries a dated "## [4.6.0] - <date>" section above
      "## [4.5.0]", in the file's Keep a Changelog style
    And the "## [4.6.0]" entry describes the precision-gap fixes: the
      specifier's conventions, the coder's mechanical checks, the verifier's
      mechanical "code present" criterion and per-domain spec-file rule, the
      orchestrator's bounded slug derivation, and the probe's
      convention-aligned id extraction with its test and spec updates
    And the "## [4.5.0]" section and every entry below it are byte-for-byte
      unchanged

  # ADD - bump460-02: the grade is minor, stated and justified.
  Scenario: bump460-02
    When the reader reads the "## [4.6.0]" entry
    Then it states the grade as minor, not patch and not major, naming the
      justification: role-prompt behavior changes are changes to rendered
      agent bodies, and the probe's extraction behavior changes — not the
      wording-only patch
    And it names what survives unchanged (not major): the workflow contract,
      the "antz:generated" marker format, the access model, the directory
      layout, and the install locations
    And it states that "install.sh" itself is untouched and the bump reaches
      installed copies only through the normal "./install.sh --all"
      re-render, and that no role creates the "v4.6.0" tag

  ### Invariants
  - The versioning policy is unchanged: this bump follows the existing
    gradation, not a new rubric.
  - No role commits anything; the v4.6.0 tag is the human's commit-time
    follow-up.

## Feature: VERSION bumped to 4.7.0 with a matching CHANGELOG.md entry describing the install.sh hardening, graded minor (from 06-bump470.feature, change `hardening-installsh`)

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.6.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.6.0] - 2026-09-13"

  # ADD - bump470-01: the bump is present -- VERSION reads 4.7.0 and
  # CHANGELOG.md gains a matching [4.7.0] section above [4.6.0].
  Scenario: bump470-01
    When the reader reads "VERSION"
    Then it reads exactly "4.7.0" (the version value plus one trailing
      newline, its only content) and agrees with the newest topmost
      CHANGELOG entry
    And "CHANGELOG.md" carries a dated "## [4.7.0] - <date>" section above
      "## [4.6.0]", in the file's Keep a Changelog style (category
      headings with bold lead-in bullets)
    And the "## [4.7.0]" entry describes each of: the header-anchored
      marker detection at the three sites and the backup-before-overwrite
      hole it closes; the quoted description scalars at the three render
      sites; the ANTZ_REF ref derivation replacing the hardcoded master
      (a tagged install no longer reads master content); the embedded
      script's mktemp cleanup trap; the stated .bak.<ts> policy and the
      header completion (orchestrator and commands named); and the
      AGENTS.md/CLAUDE.md "not present yet" correction
    And the "## [4.6.0]" section and every entry below it are byte-for-byte
      unchanged

  # ADD - bump470-02: the grade is minor, stated and justified.
  Scenario: bump470-02
    When the reader reads the "## [4.7.0]" entry against the versioning
      gradation
    Then the change grades as "minor": install.sh's detection logic and
      rendered output both change (anchored marker detection, quoted
      descriptions, ANTZ_REF-driven fetch URLs), which the gradation
      reserves for minor, not patch (not wording-only)
    And it does not grade as "major": the workflow contract, the
      "antz:generated" marker format, the access model, the directory
      layout, and the install locations are all unchanged -- the marker
      line's shape, the flags, the frontmatter field set, and the install
      paths all survive, so no consumer breaks
    And it states that "agents/prompts/" and "agents/meta/" are untouched
      and no role creates the "v4.7.0" tag: the local tag is the human's
      commit-time follow-up, created against the human's bump commit and
      not pushed automatically

  ### Invariants
  - The versioning policy is unchanged: this bump follows the existing
    gradation, not a new rubric.
  - No role commits anything; the v4.7.0 tag is the human's commit-time
    follow-up.
  - The earlier bump suites' install.sh-untouched guards (bump440/450/460)
    retire vacuously on their own change_pending gates once HEAD carries
    their entries -- they need no edit from this change.

## End-to-end QA suite

Operates through the real product UI: the repo's policy docs read by a user,
and `install.sh`'s own CLI (its flags are a UI affordance, not an internal
API call - same convention as `spdd/specs/set-model.md`'s e2e suite). All
scenarios were delivered by `versioning-install-sh` (all tagged ADD; no prior
e2e series existed, so ids start at 01).

  Background:
    Given a local checkout of the antz repo with the change applied
      ("AGENTS.md" and "CLAUDE.md" stating the new rule; "install.sh",
      "VERSION", "CHANGELOG.md" body, "agents/", "tests/", "docs/", "spdd/"
      all at their pre-change state)
    And Claude Code and OpenCode both detected, with clean, empty
      "~/.claude/agents", "~/.claude/commands", "~/.config/opencode/agents",
      and "~/.config/opencode/commands" directories
    And the user has already run "./install.sh --all", installing all 4
      agents plus the "/antz" and "/antz-set-model" commands for both
      clients, every installed file marked "antz:generated version=<current
      VERSION>"

  # ADD - e2e-qa-01: the rule is discoverable, correct, and identical in both
  # policy docs; the wrong sentence is gone; the docs-only clause survived.
  # This is the change's primary user-visible outcome.
  Scenario: e2e-qa-01
    When the user opens "AGENTS.md" and then "CLAUDE.md"
    Then each "## Versioning" section states that a commit changing
      "agents/prompts/", "agents/meta/", or "install.sh" bumps "VERSION" and
      adds a matching "CHANGELOG.md" entry in the same commit
    And neither file contains the sentence "Changes elsewhere (install.sh,
      docs) don't require a bump"
    And each section states that docs-only changes - including "AGENTS.md"
      and "CLAUDE.md" themselves - require no bump
    And the two sections state the identical rule

  # ADD - e2e-qa-02: the motivating staleness is real today, observed through
  # install.sh's own CLI. The user simulates exactly the practice the new
  # rule forbids - an install.sh-only change that alters rendered output with
  # no bump - and watches the tooling stay silent. This is why the rule
  # exists; after the restore step the repo and installs are back to the
  # committed state.
  Scenario: e2e-qa-02
    When the user edits "install.sh" only, adding one sentence to the
      "/antz" command description rendered by "render_claude_command" and
      "render_opencode_command", without touching "VERSION" or
      "CHANGELOG.md"
    And the user runs "./install.sh --check"
    Then "--check" reports "already up to date (antz <current VERSION>)" for
      both clients - the rendered-command drift is invisible to it
    And the user runs "./install.sh --all"
    Then both clients' installed "~/.claude/commands/antz.md" and
      "~/.config/opencode/commands/antz.md" carry the altered description
      but are still marked "antz:generated version=<current VERSION>"
    And a fresh "./install.sh --check" still reports "already up to date
      (antz <current VERSION>)" for both clients
    When the user restores "install.sh" to its committed state (e.g. "git
      checkout -- install.sh") and re-runs "./install.sh --all"
    Then the installed copies once again match the committed "install.sh",
      still marked "antz:generated version=<current VERSION>", and
      "install.sh" itself matches its committed state again

  # ADD - e2e-qa-03: the documented rule alone resolves the gradation for
  # install.sh-only changes - a reader never needs tribal knowledge. Each row
  # is answerable purely from the "## Versioning" section.
  Scenario Outline: e2e-qa-03
    When the user, reading only the "## Versioning" section, considers a
      future commit whose only change is <change>
    Then the documented rule predicts: <prediction>

    Examples:
      | change                                                                            | prediction                                                                  |
      | a comment-only or wording-only install.sh tweak with no rendered-output change    | a patch bump + matching CHANGELOG.md entry in the same commit + local vX.Y.Z tag |
      | an install.sh behavior change to the rendered commands (e.g. the interactive-picker rendering shipped by set-model-interactive-picker) | a minor bump + matching CHANGELOG.md entry in the same commit + local vX.Y.Z tag |
      | an install.sh contract break (e.g. changing the "antz:generated" marker format)   | a major bump + matching CHANGELOG.md entry in the same commit + local vX.Y.Z tag |

  # ADD - e2e-qa-04: the delivering change itself is the worked example of
  # the preserved docs-only clause - a user can predict from the docs that a
  # commit touching only AGENTS.md/CLAUDE.md bumps nothing, and the repo's
  # actual state confirms the prediction.
  Scenario: e2e-qa-04
    When the user considers this change's diff - only "AGENTS.md" and
      "CLAUDE.md" edited (plus the single "CHANGELOG.md" scope line per the
      delivering change's README decision 3)
    Then the documented docs-only clause predicts no "VERSION" bump
    And the repo confirms it: "VERSION" still reads the pre-change value,
      and "CHANGELOG.md" contains no entry describing this change

  # ADD - e2e-qa-05: positive control for the recorded rationale - when the
  # rule IS followed (install.sh change + bump, same commit), the existing
  # --check machinery the docs describe does flag the drift and print the
  # changelog. The rationale in the docs is thus verifiable, not aspirational.
  # Restore steps return the repo AND the installed copies to the committed
  # state.
  Scenario: e2e-qa-05
    When the user simulates a rule-following install.sh-only change in the
      working tree: the same rendered-description edit as e2e-qa-02, plus
      bumping "VERSION" (e.g. to <next minor>) and prepending a matching
      "CHANGELOG.md" entry describing it
    And the user runs "./install.sh --check"
    Then "--check" reports "Claude Code: antz <current VERSION> -> <next
      minor>" and "OpenCode: antz <current VERSION> -> <next minor>"
    And "--check" prints the newly added "CHANGELOG.md" entry
    And the user runs "./install.sh --all"
    Then every installed agent and command file for both clients is
      regenerated with the altered "/antz" description and marked
      "antz:generated version=<next minor>"
    And a fresh "./install.sh --check" reports "already up to date (antz
      <next minor>)" for both clients
    When the user restores "install.sh", "VERSION", and "CHANGELOG.md" to
      their committed states (e.g. "git checkout -- install.sh VERSION
      CHANGELOG.md") and re-runs "./install.sh --all"
    Then the installed copies are again rendered from the committed source
      and marked "antz:generated version=<current VERSION>", and
      "install.sh", "VERSION", and "CHANGELOG.md" each match their committed
      states again

## Feature: VERSION bumped to 4.7.1 with a matching CHANGELOG.md entry describing the style rewrite, graded patch (from 07-bump471.feature, change `style-rewrite`)

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.7.0" at this change's start, with CHANGELOG.md's
      newest entry "## [4.7.0] - 2026-09-13"

  # ADD - bump471-01: the bump is present — VERSION reads 4.7.1 and
  # CHANGELOG.md gains a matching [4.7.1] section above [4.7.0].
  Scenario: bump471-01
    When tests/bump471_test.sh runs
    Then VERSION is a semver agreeing with the newest (topmost) CHANGELOG
      entry — together pinning "VERSION reads exactly 4.7.1" today
    And CHANGELOG.md carries exactly one dated "## [4.7.1] - <date>" heading
      sitting above "## [4.7.0]"
    And the [4.7.1] section describes the style rewrite
    And the entry states the grade and its justification: patch — wording
      only, no behavior change
    And every entry from [4.7.0] down is byte-for-byte unchanged versus git
      HEAD

  # ADD - bump471-02: the working-vs-HEAD guards are born gated, and the
  # no-commit law holds.
  Scenario: bump471-02
    When the flow's work sits uncommitted on the change's marker branch
    Then the suite's install.sh-untouched and no-v4.7.1-tag checks are gated
      on the change_pending predicate
    And the suite never commits, never tags, and never mutates the working
      tree
    And the suite exits 0 in both the pending and the committed state

  ### Invariants
  - VERSION is never pinned as a cross-change literal.
  - Every new working-vs-HEAD window is born gated on the change_pending
    pattern.
  - The grade is patch: agents/prompts/ wording only — no capability,
    rendered surface, contract, or detection change; agents/meta/* and
    install.sh are byte-unchanged across the whole change.

## Feature: VERSION bumped to 4.8.0 with a matching CHANGELOG.md entry describing the de-embed of orchestration scripts, graded minor (from 06-versionbump.feature, change `deembed-orchestration-scripts`)

  Background:
    Given "spdd/specs/versioning.md" as the governing policy: a commit
      changing "agents/prompts/", "agents/meta/", or "install.sh" bumps
      "VERSION" and adds a matching "CHANGELOG.md" entry in the same commit
    And "VERSION" reads "4.7.1" at this change's start, with CHANGELOG.md's
      newest entry "## [4.7.1] - 2026-09-13"

  # ADD - versionbump-01: the bump is present — VERSION reads 4.8.0 and
  # CHANGELOG.md gains a matching [4.8.0] section above [4.7.1].
  Scenario: versionbump-01
    When the reader reads "VERSION"
    Then it reads exactly "4.8.0" (the value plus one trailing newline,
      its only content)
    And "CHANGELOG.md" carries a "## [4.8.0] - <date>" section above the
      "[4.7.1]" section, in Keep a Changelog format and the file's
      existing entry style
    And that section's entries describe the change's substance: the four
      scripts installed as files under the resolved
      "${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/" libdir with
      marker, backup, and --check reporting; the orchestrator prompt and
      both /antz-set-model command bodies invoking the installed scripts
      by their resolved paths with zero script re-materialization;
      inject_includes() and the "# antz-include:" markers retired along
      with the antz-skills.sh fence-indent carve-out; the set-model
      script's required client first argument and internal agents-dir
      resolution; --check extended to the installed scripts; the
      AGENTS.md/CLAUDE.md law and docs/orchestrator.md updated; and the
      expected cache effect (the rendered orchestrator body from ~483
      lines to ~150, per-session script re-materialization to zero)
    And every earlier CHANGELOG entry is byte-for-byte untouched

  # ADD - versionbump-02: the grade is minor, stated explicitly, with the
  # install-locations clause addressed head-on.
  Scenario: versionbump-02
    When the reader reads the "[4.8.0]" entry's grading statement
    Then it states the grade as minor — rendered agent/command bodies and
      install mechanics change, which is a behavior change and not the
      wording-only kind that grades as patch
    And it states explicitly why it is not major, addressing the
      "install locations" clause head-on: the workflow contract, the
      machine-line vocabulary, the "antz:generated" marker format, the
      access model, and the twelve client-file install paths are all
      unchanged; the libdir is an additional install location shared by
      both clients that no existing consumer breaks on (the same
      explicit-adjacency-note precedent as the 4.3.0 entry)
    And it states that the local "v4.8.0" tag is the human's commit-time
      follow-up, created against the human's bump commit and never pushed
      automatically, and that no role creates it

  # ADD - versionbump-03: one bump covers the whole change.
  Scenario: versionbump-03
    When the change's diff is graded by its most severe component
    Then the single 4.8.0 bump covers the orchestrator prompt edit,
      install.sh's mechanics change, the command files' rendered shape,
      and the docs/tests edits together
    And no additional bump or entry is required for the docs-only or
      tests-only parts (the docs-only clause of the policy applies to
      them)

  ### Invariants
  - The versioning policy is unchanged: this bump follows the existing
    gradation, not a new rubric.
  - No role commits anything; the v4.8.0 tag is the human's commit-time
    follow-up.

## Feature: the suite area tests only the current version's behavior (from optimize-test-suite)

  Background:
    Given the re-scoped law: the test area pins no version history — no
      append-only guarantee, no entry ordering/uniqueness/dating check,
      no git-HEAD comparison, no per-version content pin
    And the change is tests-only: agents/, install.sh,
      scripts/orchestration/, and spdd/specs/ stay byte-identical, and
      VERSION and CHANGELOG.md are read-only for every test
    And the check suite "tests/versioncurrent_test.sh" is hermetic and
      render-free: it reads only VERSION and CHANGELOG.md of the tree
      under test — no install.sh invocation, no network, no git query —
      and any staged fixture tree lives in temp space per the harness

  # ADD - versioncurrent-01: the frozen-history suites are gone and their
  # unique ids are registered by no suite.
  Scenario: versioncurrent-01
    When the test area is scanned
    Then the files bump440_test.sh, bump450_test.sh, bump460_test.sh,
      bump470_test.sh, bump471_test.sh, bump480_test.sh,
      skills-activation-bump_test.sh, skills-desc-match-bump_test.sh,
      docs-bump_test.sh, versioning-rule_test.sh, and the interim
      changelog-history_test.sh no longer exist under tests/
    And no suite registers a test whose id is bump440-01..02,
      bump450-01..02, bump460-01..02, bump470-01..02, bump471-01..02,
      bump421-01..02, versionbump-01..03, bump-01..03, versioning-01..07,
      or versionhistory-01..05
    And access-model_test.sh still registers meta-01..03, render-01,
      render-02, and render-04, with its bump-01..03 still retired

  # ADD - versioncurrent-02: the one version check is exactly two
  # assertions.
  Scenario: versioncurrent-02
    When tests/versioncurrent_test.sh runs its version check
    Then it carries exactly two assertions: VERSION's entire content is
      a semver X.Y.Z plus one trailing newline, and VERSION equals the
      version in the newest (topmost) "## [X.Y.Z] - <date>" heading of
      CHANGELOG.md
    And the agreement assertion is relative — it binds whatever VERSION
      and CHANGELOG.md the tree under test carries, never a literal
      version

  # ADD - versioncurrent-03: a future bump needs no test edit, only the
  # two assertions staying true.
  Scenario: versioncurrent-03
    When a staged copy of the working tree prepends a new dated
      "## [X.Y.Z]" entry atop CHANGELOG.md and bumps VERSION to match it
    Then the version check passes from that staged tree with no edit to
      the suite
    And the inverse holds: with VERSION bumped but no new entry added,
      the check fails — it never passes vacuously

  ### Invariants
  - tests/versioncurrent_test.sh is the only home of a version assertion in
    the area: exactly the two assertions of versioncurrent-02; no
    append-only, ordering, dating, uniqueness, history, or git-HEAD check
    exists in any suite, and none regrows.
  - Hermetic and render-free throughout: no install.sh invocation, no
    network, no git query; fixture trees are staged copies under temp space
    (harness helpers), and the working tree's own files are never mutated
    by a test.
  - Reported test names carry the versioncurrent ids declared here, per the
    repo convention.
  - Of the deleted coverage, only the current-version guarantees (semver
    shape, VERSION-to-newest-entry agreement) survive, inside
    versioncurrent-02; everything else — history, evolution calibration,
    prose pins — is deleted outright, with past versions recorded only in
    CHANGELOG.md itself and the merged versioning domain spec.

## Out of scope
- Any edit to "install.sh" (including its stale line-21 header comment),
  "agents/prompts/", "agents/meta/", "VERSION", "tests/", "docs/",
  "spdd/specs/", or "spdd/archive/" (beyond the delivering change's own
  declared file list: the two policy docs' first bullet, the CHANGELOG.md
  scope line, and the coder's own new test suite).
- Any behavioral change to "install.sh"'s marker/version/--check machinery -
  it already fully supports the rule.
- Extending the tracked set beyond "agents/prompts/", "agents/meta/", and
  "install.sh" ("tests/" and "spdd/" stay untracked).
- Retroactive entries, tags, or version renumbering for past changes.
- Mechanical bump enforcement (CI/pre-commit).

## Relevant files
- `/home/edezacas/Projects/edezacas/antz/AGENTS.md` and
  `/home/edezacas/Projects/edezacas/antz/CLAUDE.md` — the `## Versioning`
  sections (byte-identical across both files; first bullet restated by this
  domain, second and third bullets preserved).
- `/home/edezacas/Projects/edezacas/antz/CHANGELOG.md` — scope sentence (line
  3) updated to cover `install.sh`; entries are the artifact every mandated
  bump must add to.
- `/home/edezacas/Projects/edezacas/antz/VERSION` — semver source of the
  marker comment embedded in every installed file.
- `/home/edezacas/Projects/edezacas/antz/install.sh` — the machinery the rule
  relies on, untouched: the five render sites embedding `$version` in the
  `antz:generated` marker, `installed_version_of`/`changelog_since`/
  `report_version` and the `--check` path keyed off the installed specifier
  agent file. Its line-21 header comment still restates the old tracked set
  (accepted drift; see Invariants).
- `/home/edezacas/Projects/edezacas/antz/tests/versioning-rule_test.sh` —
  self-contained bash test harness, one test per scenario/example-row above,
  tagged with scenario ids in each test's reported name; e2e-only ids appear
  as explicit SKIP stubs.

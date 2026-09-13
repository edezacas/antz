# Change: fix-test-regression-precision-gaps

Repairs the test regression Change C (precision-gaps) left on master once
committed: three suites in `tests/` fail because their diff-window
assertions assume HEAD = the pre-change state. HEAD is 7969c2b (Change C
committed), so every "working copy vs HEAD" window that expected the
reword to be pending now reads an empty/identical diff. Scope is **tests/
only** (plus this change's `spdd/` artifact): no VERSION bump, no
CHANGELOG entry (the versioning rule does not require one for `tests/`),
`agents/` and `install.sh` untouched, and plan items D and E are
explicitly out of scope.

## Goal

- **sluglimit-02 commits robustly** — `tests/sluglimit_test.sh`'s
  working-vs-HEAD window assertions (the exactly-one-removed/one-added
  diff window with verbatim bullet identity, the collision-rule tail
  identity, the fence/table-count equality vs HEAD) adopt the
  `change_pending()` gating pattern: enforced while the derivation-bullet
  reword is pending, retired with a loud note once committed.
- **rolechecks-01/05 commit robustly** — `tests/rolechecks_test.sh`'s
  window assertions (the appended-sentence-yields-HEAD's-bullet check, the
  roles-03 re-scope inversion, the roles-01/02/04/05 byte-identity vs
  HEAD, the pre-change-pin Given) adopt the same pattern, gated
  per-artifact.
- **conventions-04's retirement path survives post-commit** —
  `make_fixture_differs` synthesizes the diff inside the fixture (commit
  the copied tree as-is, then mutate the fixture's working
  specifier.prompt) instead of reading the real HEAD, so the two
  `..._when_copy_differs` tests cover the "cambio pendiente -> retiro
  ruidoso con nota" path whether or not the change is committed.
- **Born-robust rule** — every diff-window assertion touched by this
  change (and every new one) is gated from birth; the absolute content
  pins stay enforced in every repo state and are the durable coverage.

## Contract (per sub-spec)

Each sub-spec below is independently implementable and verifiable; the
three are mutually independent (different suites, different destination
domains) and the numbering is presentation order only.

- **01-sluglimit** — `tests/sluglimit_test.sh` sluglimit-02: pinned
  meanings become absolute (HEAD-independent) and stay enforced; the
  working-vs-HEAD window assertions gate on a per-suite `change_pending()`
  predicate with the bump-pattern conjunction (differs from HEAD AND
  HEAD's derivation bullet does not yet state the length limit), retiring
  loudly. Declared destination domain: `flow-branch`.
- **02-rolechecks** — `tests/rolechecks_test.sh` rolechecks-01 and
  rolechecks-05: content pins and the observable criterion stay enforced
  absolutely; the window assertions gate per-artifact (coder.prompt;
  tests/roles_test.sh) on the same pattern. Declared destination domain:
  `role-surfaces`.
- **03-conventions** — `tests/conventions_test.sh` conventions-04:
  `make_fixture_differs` synthesizes the fixture's diff window (no
  real-HEAD reads), so the retirement path stays covered post-commit; the
  byte-identical and degenerate fixtures and the working-suites test keep
  their semantics. Declared destination domain: `specifier-role`.

## Shared contracts

- **The `change_pending()` gating pattern** (shared by 01-sluglimit and
  02-rolechecks, per the established precedent in `tests/bump440_test.sh`,
  `tests/bump450_test.sh`, `tests/bump460_test.sh`): a HEAD-comparison
  guard is enforced only while the guarded artifact differs from git HEAD
  **and** HEAD does not yet carry the change's marker content (for the
  derivation bullet: the length-limit wording; for the coder prompt's
  pre-planning bullet: the appended id-search sentence; for roles_test.sh:
  the re-scoped roles-03 pin). Otherwise the guard retires vacuously,
  printing a loud `note:` naming the guarded artifact and stating the
  retirement; the test stays registered and passes in both states. The
  conjunction is the stacking lesson: once HEAD carries the marker, any
  current diff is a later change's legitimate edit and must not resurrect
  the guard.
- **Loud-note convention**: retirement notes print to the suite's output
  in the established greppable `note:` style (as
  `tests/orchestrator-sessionguards_test.sh`'s sessionguards-04 gate and
  prompts-05/closingblock-05 already do).
- **Absolute vs window assertions**: content pins (required/forbidden
  strings, observable criteria, suite-green runs) never read git HEAD and
  stay enforced in every repo state; only working-vs-HEAD comparisons gate.
- Both role prompts and `tests/roles_test.sh` are read-only fixtures for
  this change: their rewordings are Change C's, already committed.

## Invariants

- No role ever commits anything; the suites never commit and never mutate
  the working tree (the conventions fixtures are throwaways under
  `mktemp -d`).
- Once a window guard retires, its coverage lives on in the absolute
  content pins — a retirement is never a deletion of the test.
- `agents/prompts/*.prompt`, `scripts/orchestration/*`, `install.sh`,
  `VERSION`, and `CHANGELOG.md` are byte-unchanged by this change.
- Every new diff-window assertion in `tests/` must be born gated
  (change_pending-style); ungated working-vs-HEAD windows are the bug
  class this change closes.

## Out of scope

- Plan items D (style rewrite) and E (install.sh/docs hardening).
- The gates themselves (prompts-05, closingblock-05) — already landed and
  correct; only the fixture that exercises them changes.
- rolechecks-02/03/04's byte-identity-vs-HEAD comparisons of surrounding
  bullets and sluglimit-01's flow-script invariant (passing today; a
  future change's call if a later reword trips them).
- VERSION / CHANGELOG.md (no bump required for `tests/` changes).

## Relevant files

### 01-sluglimit (declared destination domain: flow-branch)

- `tests/sluglimit_test.sh` — the suite to fix: `test_sluglimit_02`
  (the diff-window block and the tail/fence/table-vs-HEAD comparisons are
  the gated set; the requires/refuses are the absolute set), the
  `step1_window`/`tail_of`/`flow_limit` helpers and the HEAD baselines it
  already builds.
- `tests/bump440_test.sh`, `tests/bump450_test.sh`, `tests/bump460_test.sh`
  — the `change_pending()` precedents (bump460's conjunction is the
  stacking-robust form to mirror).
- `tests/orchestrator-sessionguards_test.sh` — the loud-`note:` gate style
  (sessionguards-04).
- `spdd/specs/flow-branch.md` — the sluglimit feature this sub-spec's
  MODIFY merges into.

### 02-rolechecks (declared destination domain: role-surfaces)

- `tests/rolechecks_test.sh` — the suite to fix: `test_rolechecks_01`
  (the appended-sentence-vs-HEAD check is the gated set), `test_rolechecks_05`
  (the Given, the re-scope inversion, and the roles-01/02/04/05
  byte-identity loop are the gated set; the content requires and the
  suite-green run stay absolute), the `ID_SEARCH`/HEAD baselines it
  already defines.
- `tests/bump440_test.sh`, `tests/bump450_test.sh`, `tests/bump460_test.sh`
  — the same `change_pending()` precedent (per-artifact predicates here:
  coder.prompt and tests/roles_test.sh).
- `tests/roles_test.sh` — read-only: the roles suite the rolechecks-05
  window guards; its re-scoped roles-03 pin is the marker content.
- `spdd/specs/role-surfaces.md` — the rolechecks feature this sub-spec's
  MODIFYs merge into.

### 03-conventions (declared destination domain: specifier-role)

- `tests/conventions_test.sh` — the suite to fix: `make_fixture_differs`
  (the only fixture builder reading the real HEAD), the two
  `..._when_copy_differs` tests, and the unchanged `make_fixture_identical`
  / `make_fixture_no_bullet` / working-suites test.
- `tests/skills-activation-prompts_test.sh` — read-only: prompts-05's
  specifier guard (`specifier_byte_identical_to_head`) whose gate the
  synthesized fixture must trip; the prompts suite has no other
  specifier.prompt assertions.
- `tests/closingblock_test.sh` — read-only: closingblock-05's two gated
  assertions (the only closingblock assertions reading
  agents/prompts/specifier.prompt beyond the Output/report section
  extract).
- `agents/prompts/specifier.prompt` — read-only: the mutation target
  inside the fixture; the safe reword sites are outside the
  report/Output section (pinned by closingblock-01/02/04).
- `spdd/specs/specifier-role.md` — the conventions feature this
  sub-spec's MODIFY merges into.

### e2e-qa (the change's end-to-end suite)

- `e2e-qa.feature` — one runnable scenario (`e2e-regression-01`) observing
  the three suites' output on committed master: exit 0, no FAIL, all ids
  registered, retirement notes loud.

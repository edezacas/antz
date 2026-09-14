# Change: optimize-test-suite

## Goal (revised)
The test area must test ONLY the current version's behavior. Everything that
calibrates history/evolution or pins prose is deleted. Rationale: tests/ are
~21,600 lines against a ~1,458-line product (install.sh +
scripts/orchestration/ = 335 lines; prompts = 335); the ~15:1 ratio is the
problem. End state: one runner, one shared harness, a full run under 60s,
hermetic, green in the committed-and-archived era, with real current-version
behavior covered.

## Deleted (whole files)
The 9 bump suites (bump440/450/460/470/471/480, docs-bump,
skills-activation-bump, skills-desc-match-bump), versioning-rule, docslaw,
repodocs, readmefile, skills-activation-docs, entities-operations-table,
conventions, closingblock, orchestrator-skills-block,
orchestrator-sessionguards, skills-activation-prompts, rolechecks, sluglimit,
setmodeldeembed, renderinject. Plus the interim changelog-history suite
(versioncurrent-01) and the redundant skills-activation-render render-01
registrations (renderdedup-02, not the file).

## Retained behavior (current version)
install.sh render/backup/--check/libdir/ref-pin/quoting/access-model/
skills-grant/header-marker/POSIX-sh; antz-flow.sh preflight fail-closed,
branch ensure, machine states; antz-probe.sh receipt parsing; set-model
script + command; /antz command bodies; runner_test + thinned harness_test;
receipts (the contract the probe consumes); the pin that antz-flow.sh
contains the line `diff --quiet HEAD -- scripts/...` is product behavior and
stays (it is the flow's own checkout guard asserted as source content, not a
test comparing the tree to HEAD — hygiene-02's carve-out list already
excludes it via the product-behavior exemption the hygiene spec states).

## Permanent laws (sub-spec 09, enforced by hygiene-01..04)
1. No suite executes another suite; the runner alone answers "is the whole
   area green".
2. No suite asserts another suite's source content or output.
3. No retained suite compares the real tree against git HEAD (`git
   merge-base`, `show HEAD:`, `diff --quiet HEAD`, `cmp` vs HEAD) or
   byte-pins its own file against HEAD.
4. No exact-phrase prose assertions of prompts or docs. Sole exception: the
   Working-Root triplication check in tests/roles_test.sh (the three role
   prompts' triplicated sections stay byte-identical to each other).

## Supersessions (explicit)
- The verifier-02 frozen-surface guard (`git diff --quiet HEAD --
  scripts/orchestration/ agents/meta/`) retained by rolesdecouple is
  reverted per law 3.
- Sub-spec 05's append-only/history guarantee is dropped; the version check
  shrinks to 2-3 assertions: VERSION is semver; VERSION equals the newest
  CHANGELOG.md entry (versioncurrent-02).
- The earlier plan to keep versioning-rule and one stable history suite is
  dropped: versioning-rule is deleted (versioncurrent-01).
- Sub-spec 08 supersedes sub-spec 05's stale clause that access-model still
  registers render-01..04 and docs-01..04 — for exactly two ids: render-03
  and docs-01..04 are removed; meta-01..02, render-01, render-02, render-04
  stay.

## Live-coverage transfers
Where each deleted suite's live assertions went; everything else died as
prose/history calibration.
| Deleted suite | Disposition |
| --- | --- |
| conventions | crosssuites-03 removes conventions-04 whole (all its registrations ran other suites in real and fixture trees); its remaining content was prose pins → died. |
| entities-operations-table | specifier-02's child re-execution and cross-suite runs removed by crosssuites-04; table-prose pins → died. |
| readmefile | specifier-prompt prose pins → died. |
| closingblock | Its receipts contract coverage stays with the receipts suite (transfer). coder-04's own-source extract pins stay in the closingblock suite; the receipts rerun + git-HEAD byte-pin are removed (crosssuites-02). |
| orchestrator-skills-block | Prompt prose pins → died. |
| orchestrator-sessionguards | Prompt prose pins → died. |
| skills-activation-prompts | Prompt prose pins → died. |
| rolechecks | Roles behavior stays in the roles suite's retained ids (roles-01..04, terminology-01..03, verifier-01, testsuite-06/08 per rolesdecouple); rolechecks-05's HEAD byte-pins and suite reruns → died. |
| sluglimit | Orchestrator-prompt prose pins → died; no live behavior found. |
| setmodeldeembed | Set-model command behavior → set-model-command suite (transfer); setmodeldeembed-05's cross-suite greps/reruns removed (crosssuites-05). |
| renderinject | Retired injection mechanism → died (quoting-05's grep of its source removed, crosssuites-01). |
| 9 bump suites + versioning-rule + changelog-history | History/evolution calibration → replaced by versioncurrent-02's two-assertion current-version check; unique old ids re-pinned nowhere (versioncurrent-01). |
| docslaw / repodocs / skills-activation-docs | Docs prose pins → died. |

## Sub-specs (dependency order, destination domain)
| Sub-spec | Destination domain | Declared ids | Status |
| --- | --- | --- | --- |
| 01-harness.feature | test-harness | harness-01..06 | DONE (receipt on disk) |
| 02-runner.feature | test-runner | runner-01..05 | DONE (receipt on disk) |
| 03-rolesdecouple.feature | role-surfaces | rolesdecouple-01..05 | DONE (receipt on disk) |
| 04-crosssuites.feature | install-render (receipts/specifier-role/posixsh merge edges) | crosssuites-01..05 | DONE (receipt on disk) |
| 05-versioncurrent.feature | versioning | versioncurrent-01..03 | pending |
| 06-invocationsfix.feature | install-render | invocationsfix-01..02 | pending |
| 07-posixshfix.feature | posixsh | posixshfix-01..04 | pending |
| 08-renderdedup.feature | access-model | renderdedup-01..05 | pending |
| 09-hygiene.feature | test-runner | hygiene-01..04 | pending |

## Shared contracts
- Harness output contract (01, consumed by 02 and every suite): per test one
  `PASS: <name>` / `FAIL: <name>` / `SKIP: <name> (<reason>)` line, `<name>`
  beginning with the scenario id; final line `pass=<n> fail=<n> skip=<n>`;
  exit 0 exactly when no registered test failed.
- Suite discovery contract (02, 09): a suite is any `tests/*_test.sh`;
  `tests/bash32-sh.sh` and `tests/harness.sh` are helpers, not suites.
- Receipt contract: unchanged — the probe's consumed fields
  (`test_command=`, per-id `result=green|skip|blocked`, `BLOCKED:` prefix)
  stay byte-compatible (04's coder-04 re-scope).
- Render mechanics: every suite renders install.sh only through the harness
  library's render helpers (01 Background; asserted by 03/07/08).

## Invariants
- Tests-only change: `agents/`, `install.sh`, `scripts/orchestration/`,
  `spdd/specs/` stay byte-identical; no VERSION/CHANGELOG bump; nobody
  commits anything.
- One runner (`tests/run_all.sh`) is the only answer to "is the whole area
  green"; full run < 60s, hermetic (temp space only, no network).
- The four permanent laws hold era-independently (hygiene-04): green in the
  committed-and-archived era with no test edit.
- No suite registers a deleted suite's unique ids (versioncurrent-01).

## Out of scope
- Any product edit (see invariants) and any version bump.
- Reinstating history/evolution calibration, git-HEAD comparisons, or prose
  pins — removed deliberately, guarded against regrowth by 09.
- The versioning policy's prose in AGENTS.md/CLAUDE.md — docs are not edited
  by this change.

## Relevant files
- 01-harness (→ test-harness): `tests/harness.sh`, `tests/*_test.sh` helper
  copies (run_test/new_tmp_dir/extract_* bodies), `tests/bash32-sh.sh`.
- 02-runner (→ test-runner): `tests/run_all.sh`, `tests/*_test.sh` glob.
- 03-rolesdecouple (→ role-surfaces): `tests/roles_test.sh` (testsuite-08,
  roles-05, verifier-02, terminology-03, rolechecks-05 sites).
- 04-crosssuites (→ install-render et al.): `tests/quoting_test.sh`
  (quoting-05), `tests/closingblock_test.sh` (coder-04),
  `tests/conventions_test.sh`, `tests/entities-operations-table_test.sh`,
  `tests/setmodeldeembed_test.sh`; merges into `spdd/specs/receipts.md`,
  `spdd/specs/specifier-role.md`, `spdd/specs/posixsh.md`.
- 05-versioncurrent (→ versioning): `tests/versioncurrent_test.sh` (new),
  `VERSION`, `CHANGELOG.md`.
- 06-invocationsfix (→ install-render): `tests/invocations_test.sh`
  (invocations-07), `spdd/archive/deembed-orchestration-scripts/README.md`.
- 07-posixshfix (→ posixsh): `tests/posixsh_test.sh` (posixsh-04),
  `install.sh` (report inventory, read-only).
- 08-renderdedup (→ access-model): `tests/access-model_test.sh`,
  `tests/skills-activation-render_test.sh`; merge into
  `spdd/specs/access-model.md`.
- 09-hygiene (→ test-runner): `tests/hygiene_test.sh` (new), scan root
  `tests/`.

## e2e
See `e2e-qa.feature` — one command, full run < 60s, hermetic, green in the
committed-and-archived era.

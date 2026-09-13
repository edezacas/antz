# Change: hardening-installsh (Cambio E of docs/plan-revision-2026-09.md, section 3)

## Goal

Harden `install.sh` and fix the stale docs line, and nothing else from the
plan: the `antz:generated` marker detection is anchored to a line-start
header comment at all three sites (closing the overwrite-unmanaged-file-
without-backup hole); rendered `description:` frontmatter values become
quoted YAML scalars at all three render sites; the install source ref is
derived from provenance (`ANTZ_REF`) instead of a hardcoded `master`
`RAW_BASE`; the embedded set-model script gets a temp-file cleanup trap;
the `.bak.<ts>` backup policy is stated and the `install.sh` header is
completed (orchestrator and commands named); AGENTS.md/CLAUDE.md's false
"`spdd/` — not present yet" Structure line describes the real state; and
the whole change bumps VERSION to 4.7.0 with a matching CHANGELOG entry,
graded minor (detection logic + rendered output change). Nothing from
Cambio D (style rewrite) is included.

## Contract (what a user of the change observes)

- A file is recognized as antz-managed only by a line-start header comment
  `# antz:generated ...` — in `install_file`, `installed_version_of`, and
  the `/antz-set-model` embedded script alike. A file that merely mentions
  the marker mid-body is unmanaged: backed up before overwrite, refused by
  the set-model script, and reported as a fresh install by `--check`.
- Backups are `<file>.bak.<YYYYMMDDHHMMSS>`, created exactly when the
  destination exists without the header marker, and never read, renamed,
  or deleted by `install.sh` (accumulation accepted and documented;
  cleanup is the user's).
- Every rendered `description:` value is a double-quoted single-line YAML
  scalar (embedded `"` and `\` escaped), value-preserving, at
  `render_claude`, `render_opencode`, and `render_set_model_command`.
- `ANTZ_REF` (env var, used verbatim) overrides the fetch ref; unset/empty
  keeps the documented `master` default. Local-checkout installs are
  unaffected. README, `install.sh`'s header usage, and both policy docs'
  Client Integration bullet document it.
- The embedded set-model script leaves no mktemp scratch file behind on
  any exit path, and its token-free constraint (no `$<digit>`, no
  `$ARGUMENTS`) survives.
- VERSION reads 4.7.0; CHANGELOG.md carries `[4.7.0]` above `[4.6.0]`.

## Shared contracts

- **Header-marker line** (defined by sub-spec 01, consumed by 04): a file
  is antz-managed when its content carries `# antz:generated ` as a
  line-start header comment. The marker string and the rendered marker
  line's format are unchanged — only detection is anchored.
- **renderinject-06 header-identity window** (retired by sub-spec 01, the
  change's first header-editing sub-spec, with the repo's loud-note
  convention): the base-vs-working header byte-identity assertion is
  retired once for this change's legitimate header edits (the .bak policy
  statement in 01, the ANTZ_REF usage docs and tagged-URL example in 03);
  its tracked-set sentence assertion stays enforced. Sub-spec 03's header
  edits rely on that retirement — the orchestrator implements in
  dependency order (01 before 03).
- **Rendered-output byte-identity gates** (retired/re-scoped by sub-spec
  02, with loud notes): `renderinject-01/02/05`'s base-render comparisons
  and `skills-activation-render_test.sh`'s render-03/render-04-scoping
  renderer comparisons go stale on the quoted descriptions; they are
  updated within this change so the full `tests/` suite passes. No other
  sub-spec changes rendered output.
- **Bump suite precedent** (consumed by 06): the new
  `tests/bump470_test.sh` follows `tests/bump460_test.sh` — VERSION as
  semver agreeing with the newest topmost entry, the `[4.6.0]`-down tail
  pinned byte-identical to git HEAD. The earlier bump suites'
  install.sh-untouched guards retire vacuously on their own
  `change_pending` gates (HEAD already carries their entries) and need no
  edit.

## Invariants (change-wide)

- The marker string, the rendered marker line's format, the access model,
  the directory layout, the install locations, the flags, and the rendered
  frontmatter field set are unchanged — the change grades minor, never
  major.
- `agents/prompts/` and `agents/meta/` are untouched by the entire change.
- `install.sh` stays parseable POSIX sh (posixsh-01..03 stay green) and
  keeps exactly one executable curl invocation, inside `fetch_file`.
- All rendered output stays deterministic.
- No role commits anything; the `v4.7.0` tag is the human's commit-time
  follow-up.

## Out of scope

- Everything from Cambio D (style rewrite of the role prompts) — excluded
  by the request.
- Unifying AGENTS.md/CLAUDE.md into a single source for their
  byte-identical portions (explicitly a separate decision per the plan).
- The Overview sentences "No application code lives here yet" (a different
  claim, separate decision).
- Auto-detecting the piped URL's ref, a `--ref` CLI flag, or ref
  validation; automatic pruning/capping of `.bak.<ts>` backups; quoting
  the `/antz` command descriptions; changes to the picker, argument
  contract, or ordering contract of `/antz-set-model`.

## Sub-specs (dependency order) and relevant files

### 01-marker.feature — domain: install-render (new)
- `install.sh` — `install_file` (~:545-556, marker grep at :549),
  `installed_version_of` (~:558-564, anchored version read), the `MARKER`
  constant (:34), and the header comment (backup-policy statement at
  ~:21-24 area + header completion of the opening sentence at :2-4).
- `tests/renderinject_test.sh` — renderinject-06's header-identity window
  (retire with a loud note; tracked-set assertion stays enforced).
- `tests/set-model-command_test.sh` — command-install-03/04 backup pins
  (stay green; verify only).
- `tests/installsh-posixsh_test.sh` — parse guards (stay green).

### 02-quoting.feature — domain: install-render (new)
- `install.sh` — `render_claude` (~:197-202), `render_opencode`
  (~:204-211), `render_set_model_command` `short_desc` (~:474, :490,
  emitted at :512-513).
- `agents/meta/*.yaml` — the description inputs (read-only, untouched).
- `tests/renderinject_test.sh` — renderinject-01/02/05 base-render
  byte-identity gates (retire/re-scope with loud notes).
- `tests/skills-activation-render_test.sh` — render-03 and
  render-04-scoping renderer comparisons (re-scope).
- `tests/set-model-command_test.sh` + `tests/access-model_test.sh` —
  line-anchored frontmatter assertions (stay green; verify only).

### 03-refpin.feature — domain: install-render (new)
- `install.sh` — `RAW_BASE` construction (:28-31), `fetch_file` (:88-95),
  header usage comment (:6-14) incl. the curl example at :8.
- `README.md` — Install section (~:65-82).
- `AGENTS.md` / `CLAUDE.md` — Client Integration RAW_BASE bullet
  (AGENTS.md:38, CLAUDE.md:37).
- `tests/renderinject_test.sh` — renderinject-04_shared_fetch_path
  one-curl pin (stays green; verify only).

### 04-setmodel.feature — domain: set-model (existing)
- `install.sh` — `emit_set_model_script` heredoc (~:268-416): the marker
  check at :360, the rewrite loop and `mktemp` at :383-408 (trap site).
- `spdd/specs/set-model.md` — "Target file / marker contract" and
  set-model-cmd-07 (the MODIFY merge target).
- `tests/set-model-command_test.sh` — the extracted-script harness
  (fixtures carry header markers; extend with trap + mid-body-marker
  cases).

### 05-repodocs.feature — domain: repo-docs (new)
- `AGENTS.md` (:13) and `CLAUDE.md` (:13) — the one "spdd/" Structure
  bullet each, byte-identical between the files.
- `spdd/specs/versioning.md` — the docs-only-no-bump clause this
  sub-spec alone falls under (context only).

### 06-bump470.feature — domain: versioning (existing)
- `VERSION`, `CHANGELOG.md` — the bump artifacts.
- `spdd/specs/versioning.md` — governing policy + the bump440/450/460
  precedent features.
- `tests/bump470_test.sh` — new suite, `tests/bump460_test.sh` pattern.

## End-to-end QA

One suite for the whole change: `e2e-qa.feature` (ids e2e-qa-01..07) —
fresh-install surface (header markers + quoted descriptions), the backup
boundary and policy from the user's seat, `/antz-set-model` interop with
quoted frontmatter, the documented ANTZ_REF surface and local-provenance
precedence, the corrected docs line, and the 4.6.0 → 4.7.0 drift report.

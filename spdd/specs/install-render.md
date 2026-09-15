# Domain: install-render

## Origin
- Specced and delivered from change `hardening-installsh` (Cambio E of
  `docs/plan-revision-2026-09.md`, section 3). This domain covers the
  install-side rendering and detection logic in `install.sh`: the
  header-anchored marker detection, the quoted YAML description scalars,
  and the ANTZ_REF provenance-pinned source ref.
- Extended by direct application (2026-09-15, owner override, outside the
  flow): Pi joins as a third supported client — detection, `--pi`, the
  `render_pi`/`render_pi_command` sites, and `~/.pi/agent/{agents,prompts}`
  destinations. Recorded here by the same hand.

## Goal
`install.sh` renders deterministic, correct agent and command files for
Claude Code, OpenCode, and Pi. This domain covers three interrelated
contracts:

- **Header-anchored marker detection**: a file is antz-managed only when its
  content carries `# antz:generated ` as a line-start header comment. A
  mid-line, mid-body, or indented mention of the marker string does not
  count as managed. The `.bak.<ts>` backup policy is stated in the header
  comment and enforced by `install_file`.

- **Quoted YAML description scalars**: every rendered `description:` value is
  a double-quoted single-line YAML scalar (embedded `"` and `\` escaped),
  value-preserving, at `render_claude`, `render_opencode`, `render_pi`, and
  `render_set_model_command`. The `/antz` command renderers are out of scope.

- **ANTZ_REF source-ref pinning**: `ANTZ_REF`, when set non-empty, names the
  git ref (tag or branch) the fetched `install.sh` itself came from and
  drives every fetch URL; unset or empty keeps the documented `master`
  default. A local-checkout install reads from disk and never touches the
  network, with or without `ANTZ_REF`.

## Shared contracts

**Header-marker line** (defined here, consumed by the set-model domain):
a file is antz-managed when its content carries `# antz:generated ` as a
line-start header comment. The marker string and the rendered marker line's
format are unchanged — only the detection is anchored.

**renderinject-06 header-identity window** (retired by this domain's first
header-editing sub-spec): the base-vs-working header byte-identity assertion
is retired once for this change's legitimate header edits (the .bak policy
statement, the ANTZ_REF usage docs); its tracked-set sentence assertion
stays enforced.

**Rendered-output byte-identity gates** (re-scoped by this domain's quoting
sub-spec): `renderinject-01/02/05`'s base-render comparisons and
`skills-activation-render_test.sh`'s renderer comparisons are re-scoped
to the quoted descriptions.

## Feature: Header-anchored antz:generated marker detection and the .bak.<ts> backup policy

  Background:
    Given the repo's "install.sh"
    And the marker line install.sh renders into every installed file's
      frontmatter reads "# antz:generated version=<X.Y.Z> -- do not edit by
      hand; regenerate with install.sh" -- a line-start header comment whose
      format is unchanged by this change
    And an isolated HOME with staged destination paths, never the real
      "~/.claude" or "~/.config/opencode"

  # ADD - marker-01: managed-file overwrite-in-place preserved under
  # anchored detection
  Scenario: marker-01
    Given a destination file whose frontmatter carries the marker line
      "# antz:generated version=1.2.3 -- do not edit by hand; regenerate
      with install.sh" at line start
    When install.sh installs a generated file at that destination
    Then the destination is overwritten in place with the new render
    And no ".bak.<timestamp>" file is created for it

  # ADD - marker-02: the overwrite-without-backup hole is closed
  Scenario: marker-02
    Given a destination file that is not antz-generated and whose content
      mentions the text "antz:generated" only somewhere other than a
      line-start header comment (for example inside its body prose)
    When install.sh installs a generated file at that destination
    Then the pre-existing file is backed up to "<destination>.bak.<timestamp>"
      holding the original content byte-for-byte
    And the destination is then overwritten with the fresh managed render
    And the console output states the file was backed up as not
      antz-managed

  # ADD - marker-03: installed_version_of reads only the line-start header
  Scenario: marker-03
    Given the installed specifier agent file for a client carries no
      line-start header marker, but its body contains the text
      "antz:generated version=9.9.9"
    When the user runs "./install.sh --check"
    Then that client's report says the antz copy is a fresh install of the
      current VERSION, not "already up to date (antz 9.9.9)"
    And a file whose frontmatter does carry the line-start header marker
      still reports the version embedded in that header comment

  # ADD - marker-04: backup policy behavior
  Scenario: marker-04
    Given a destination with two pre-existing backups from earlier runs,
      "<destination>.bak.20260101010101" and "<destination>.bak.20260202020202"
    When install.sh runs twice in a row against a managed destination
    Then no new backup is created by either run
    And both pre-existing backups survive byte-for-byte under their
      original names
    And a run against an unmanaged destination still creates exactly one
      backup named "<destination>.bak.<YYYYMMDDHHMMSS>" of the content it
      overwrites

  # ADD - marker-05: backup policy documentation
  Scenario: marker-05
    When the reader reads install.sh's header comment
    Then it states that pre-existing unmanaged files are backed up as
      "<file>.bak.<timestamp>" before being overwritten
    And it states that install.sh never deletes or prunes those backups
      automatically -- accumulating them is accepted and their cleanup is
      the user's

  # ADD - marker-06: header comment completion
  Scenario: marker-06
    When the reader reads install.sh's header comment
    Then its description of what gets installed names antz-specifier,
      antz-coder, antz-verifier, and antz-orchestrator
    And it names the /antz command and the /antz-set-model command among
      what install.sh installs

## Feature: Description values are emitted as quoted YAML scalars in the rendered frontmatter

  Background:
    Given a staged checkout (install.sh, agents/, scripts/orchestration/,
      VERSION, CHANGELOG.md) and an isolated HOME, so renders never touch
      the real "~/.claude" or "~/.config/opencode"
    And the source descriptions in "agents/meta/*.yaml" and the hardcoded
      short description in render_set_model_command are unchanged -- only
      their rendered form gains quoting

  # ADD - quoting-01: all four agents' descriptions are quoted on every client
  Scenario: quoting-01
    When install.sh renders all four agents for every client
    Then every rendered agent file's frontmatter description line matches
      `description: "` and ends with `"` with no characters after it
    And the quoted value is the meta file's description for that role,
      byte-preserved inside the quotes

  # ADD - quoting-02: /antz-set-model command description is quoted too
  Scenario: quoting-02
    When install.sh renders the /antz-set-model command for each client
    Then each copy's frontmatter description line matches `description: "`
      and ends with `"` with no characters after it

  # ADD - quoting-03: embedded quotes and backslashes are escaped per YAML rules
  Scenario Outline: quoting-03
    When install.sh renders a staged meta description reading <raw>
    Then the rendered description line is exactly `description: <rendered>`

    Examples:
      | raw            | rendered               |
      | Says "hi"      | "Says \"hi\""          |
      | back\slash     | "back\\slash"          |
      | a "b" \ c      | "a \"b\" \\ c"         |

  # ADD - quoting-04: quoting is value-preserving
  Scenario: quoting-04
    When install.sh renders all agents and both command files
    Then for each rendered description line, stripping the outer quotes
      and YAML-unescape yields exactly the source description text

  # ADD - quoting-05: stale byte-identity test pins re-scoped
  Scenario: quoting-05
    When the repo's full unit suite runs
    Then tests/renderinject_test.sh's renderinject-01, renderinject-02,
      and renderinject-05 base-render byte-identity assertions are retired
      or re-scoped with a loud note for this change's legitimate rendered
      change (their structural assertions stay enforced)
    And tests/skills-activation-render_test.sh's render-03 and
      render-04-scoping renderer-comparison assertions are re-scoped to
      the current renderer behavior (no stale pre-quoting byte-identity)
    And no other suite fails on the quoted description lines

## Feature: The install source ref is pinned by provenance (ANTZ_REF), not hardcoded to master

  Background:
    Given install.sh resolves its sources either from a local checkout
      (LOCAL_ROOT, no network) or by fetching each file from RAW_BASE
    And RAW_BASE currently hardcodes "master" as the ref, so installing
      via a tagged install.sh URL would still read VERSION, CHANGELOG.md,
      prompts, meta, and scripts from master
    And for the remote-path scenarios: a recording curl stand-in on PATH
      that serves a fixture source tree and logs every requested URL --
      install.sh is run from a directory with no "agents/" next to it, so
      LOCAL_ROOT stays empty and every fetch is observable
    And "ANTZ_REF" is the ref-override environment variable: when set
      non-empty it names the git ref (tag or branch) the fetched install.sh
      itself came from, and RAW_BASE is built from that ref; when unset or
      empty the documented default ref ("master") applies

  # ADD - refpin-01: default master behavior unchanged
  Scenario: refpin-01
    When install.sh runs remotely with ANTZ_REF unset (and again with
      ANTZ_REF empty)
    Then every fetched URL is "<raw-root>/master/<relative-path>"
    And the install completes from the served tree

  # ADD - refpin-02: ANTZ_REF overrides the fetch ref
  Scenario: refpin-02
    When install.sh runs remotely with ANTZ_REF=v4.7.0
    Then every fetched URL carries /v4.7.0/ as the ref segment, covering
      VERSION, CHANGELOG.md, agents/meta/specifier.yaml,
      agents/prompts/orchestrator.prompt, and
      scripts/orchestration/antz-flow.sh among them
    And no fetched URL carries /master/
    And the rendered markers embed the fetched tree's VERSION

  # ADD - refpin-03: local provenance wins regardless of ANTZ_REF
  Scenario: refpin-03
    Given a staged checkout with a failing curl stub earlier on PATH (any
      fetch attempt would abort the install loudly)
    When install.sh runs from that checkout with ANTZ_REF=bogus-ref
    Then the install completes reading every file from the checkout
    And no fetch of any kind is attempted (the stub is never invoked)

  # ADD - refpin-04: mechanism is discoverable in docs
  Scenario: refpin-04
    When the reader reads README.md's install section, install.sh's header
      usage comment, and the AGENTS.md and CLAUDE.md Client Integration
      RAW_BASE bullets
    Then README.md documents how to install from a tag: fetch install.sh
      from the tag's raw URL and pass ANTZ_REF=<tag> to sh
    And install.sh's header usage comment documents ANTZ_REF with the
      same tagged-URL example
    And both policy docs state that the fetch ref defaults to master and
      is overridden by ANTZ_REF

  # ADD - refpin-05: fetch architecture preserved (one curl in fetch_file)
  # Re-scoped by change `deembed-orchestration-scripts` (libdirinstall-07):
  # subject changed from "include injection" to "script installation".
  Scenario: refpin-05
    When install.sh's executable code is inspected
    Then each of the four scripts is read or fetched through the one
      `fetch_file` helper (local checkout read, or RAW_BASE fetch honoring
      ANTZ_REF)
    And there is exactly one executable `curl -fsSL` invocation, inside
      fetch_file
    And the ref is substituted at the RAW_BASE construction, not per call
      site

## Out of scope
- Any change to `agents/prompts/` or `agents/meta/`.
- Quoting the `/antz` command descriptions (out of this change's scope).
- Auto-detecting provenance from the piped URL.
- A `--ref` CLI flag or ref validation against the remote.
- Automatic pruning, capping, or rotation of `.bak.<timestamp>` files.

## Feature: Pi is a third rendered client

  Background:
    Given the antz checkout under test and an isolated HOME
    And Pi's native surfaces: subagents at `~/.pi/agent/agents/<name>.md`
      and slash commands (prompt templates) at `~/.pi/agent/prompts/<name>.md`

  # ADD - pi-render-01: detection and flags
  Scenario: pi-render-01
    When install.sh runs with `--pi` (or `--all`)
    Then it installs the four `antz-*` agents under `~/.pi/agent/agents/`
      and the `/antz` and `/antz-set-model` prompt templates under
      `~/.pi/agent/prompts/`
    And a flag-less run detects Pi through `command -v pi` or an existing
      `~/.pi/agent` directory
    And every installed Pi file carries the unchanged `antz:generated`
      line-start marker

  # ADD - pi-render-02: the Pi agent frontmatter shape
  Scenario: pi-render-02
    When install.sh renders a role's meta for Pi
    Then the frontmatter carries `name`, a quoted `description`, and the
      lowercase tool allowlist for that access level (`read, grep, find, ls,
      bash` for readonly; plus `edit, write` for readwrite; plus `subagent`
      for orchestrateonly)
    And it carries `inheritProjectContext: true`, `systemPromptMode: replace`,
      and `defaultContext: fresh`
    And `inheritSkills:` is `true` exactly for the readwrite roles and
      `false` for readonly/orchestrateonly
    And the body is the role prompt verbatim

  # ADD - pi-render-03: the /antz prompt template
  Scenario: pi-render-03
    When install.sh renders the `/antz` prompt template for Pi
    Then it carries a `description` and an `argument-hint`, and its body
      delegates to the `antz-orchestrator` subagent via the pi-subagents
      `subagent` tool with the single `$ARGUMENTS` injection point

## Relevant files
- `install.sh` — `install_file`, `installed_version_of`, `yaml_quote_desc`,
  `render_claude`, `render_opencode`, `render_pi`, `render_set_model_command`,
  `pi_tools_for_access`, `pi_inherit_skills_for_access`, `fetch_file`,
  `RAW_BASE` construction, and the header comment.
- `tests/header-marker_test.sh`, `tests/description-quoting_test.sh`,
  `tests/refpin_test.sh` — self-contained test suites tagging the scenario ids.
- `tests/renderinject_test.sh`, `tests/skills-activation-render_test.sh` — re-scoped
  byte-identity assertions with loud notes.
- `README.md`, `AGENTS.md`, `CLAUDE.md` — documentation of ANTZ_REF and the
  backup policy.

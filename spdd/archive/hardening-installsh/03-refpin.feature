# Domain: install-render (new; third sub-spec into the same domain)

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

  # ADD - refpin-01: with no ref signal, the documented master invocation
  # behaves exactly as before: every fetch URL carries /master/. The
  # default is the documented master provenance, not a leftover hardcode
  # that overrides the signal.
  Scenario: refpin-01
    When install.sh runs remotely with ANTZ_REF unset (and again with
      ANTZ_REF empty)
    Then every fetched URL is "<raw-root>/master/<relative-path>"
    And the install completes from the served tree

  # ADD - refpin-02: with ANTZ_REF set, every remote fetch uses that ref:
  # VERSION, CHANGELOG.md, each agents/meta/*.yaml, each
  # agents/prompts/*.prompt, and each injected scripts/orchestration/*.sh
  # are fetched from "<raw-root>/<ref>/<relative-path>" -- nothing is
  # fetched from master. The ref is used verbatim: no validation, no
  # rewriting, no assumption it is a tag.
  Scenario: refpin-02
    When install.sh runs remotely with ANTZ_REF=v4.7.0
    Then every fetched URL carries /v4.7.0/ as the ref segment, covering
      VERSION, CHANGELOG.md, agents/meta/specifier.yaml,
      agents/prompts/orchestrator.prompt, and
      scripts/orchestration/antz-flow.sh among them
    And no fetched URL carries /master/
    And the rendered markers embed the fetched tree's VERSION

  # ADD - refpin-03: local provenance wins: when install.sh runs from a
  # checkout (LOCAL_ROOT resolves), every file is read from disk and the
  # network is never touched, regardless of ANTZ_REF. The variable only
  # governs the remote fetch path.
  Scenario: refpin-03
    Given a staged checkout with a failing curl stub earlier on PATH (any
      fetch attempt would abort the install loudly)
    When install.sh runs from that checkout with ANTZ_REF=bogus-ref
    Then the install completes reading every file from the checkout
    And no fetch of any kind is attempted (the stub is never invoked)

  # ADD - refpin-04: the mechanism is discoverable: README's install
  # section documents the tag-pinned invocation (the tagged install.sh URL
  # piped to sh with ANTZ_REF=<tag>), install.sh's header usage comment
  # documents ANTZ_REF and shows the tagged-URL example, and the
  # AGENTS.md/CLAUDE.md Client Integration bullet about RAW_BASE states
  # that the ref comes from ANTZ_REF (default master) instead of
  # describing master as the fixed source.
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

  # ADD - refpin-05: the fetch architecture is preserved: all remote reads
  # still route through the one fetch_file helper with exactly one
  # executable curl invocation inside it (renderinject-04's shared-path
  # pin stays valid, unmodified).
  Scenario: refpin-05
    When install.sh's executable code is inspected
    Then the include injection still fetches through `fetch_file "$rel"`
    And there is exactly one executable `curl -fsSL` invocation, inside
    fetch_file

### Invariants
- ANTZ_REF affects only the remote fetch path; a local-checkout install is
  byte-identical with and without it.
- The ref is consumer-supplied provenance: install.sh neither validates
  nor pins it to tag syntax; a branch name works the same way.
- With no signal, behavior is byte-for-byte the pre-change master behavior
  (default ref, same URLs, same report).
- Exactly one executable curl invocation exists, inside fetch_file; the
  ref substitution happens where RAW_BASE is built, not per call site.
- The refpin sub-spec's header/usage edits ride on the renderinject-06
  header-identity window retired by sub-spec 01 (shared contract; see
  README.md's shared-contracts section).

## Out of scope
- Auto-detecting provenance from the piped URL (POSIX sh piped via curl
  cannot see its own URL; the explicit ANTZ_REF signal is the decided
  mechanism).
- A CLI flag (--ref or similar) as a second mechanism, or ref validation
  against the remote (no round-trip check that the ref exists).
- Changing what happens when a fetch fails (the existing loud per-file
  failure stands).
- Any change to LOCAL_ROOT detection or the local-read path.

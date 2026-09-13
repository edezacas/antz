# Change: deembed-orchestration-scripts — sub-spec 01 (install side)
#
# install.sh today embeds nothing for the three orchestration scripts at
# install time — it INJECTS their content into the rendered orchestrator
# body via inject_includes() and the "# antz-include:" markers (retired by
# sub-spec 02) — and it embeds the set-model script in the two command
# files (retired by sub-spec 03). This sub-spec gives install.sh its new
# install duty: the three orchestration scripts plus the set-model script
# become four installed FILES in one shared, resolved library directory,
# with the same marker / backup / --check policy every other installed file
# has. The prompt and command bodies then invoke them by path (sub-specs
# 02/03); nothing here changes any script's behavior.
#
# Source of truth for the path: change decision 1 (2026-09-13) —
# "${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/", shared between
# clients; decision 7 — install.sh resolves it once and writes the concrete
# resolved path into what it renders, never hardcoding $HOME/.config while
# XDG_CONFIG_HOME is set.

Feature: libdirinstall — install.sh installs the four orchestration scripts as files in the resolved antz scripts libdir

  Background:
    Given a staged checkout (install.sh, agents/, scripts/orchestration/,
      VERSION, CHANGELOG.md) and an isolated HOME, so an install never
      touches the real "~/.claude", "~/.config/opencode", or a real antz
      libdir
    And the resolved libdir is "${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts",
      computed by install.sh at runtime and never hardcoded
    And the three orchestration scripts exist at
      "scripts/orchestration/antz-flow.sh", "scripts/orchestration/antz-probe.sh",
      and "scripts/orchestration/antz-skills.sh", and the set-model script
      text is emitted by install.sh itself (today inside emit_set_model_script)
    And the marker line install.sh renders reads "# antz:generated
      version=<X.Y.Z> -- do not edit by hand; regenerate with install.sh",
      unchanged in format

  # ADD - libdirinstall-01: the four scripts install as marked files in the
  # libdir; the three orchestration scripts are byte-faithful copies of
  # their sources plus one inserted marker line.
  Scenario: libdirinstall-01
    When install.sh runs an install for at least one client
    Then "antz-flow.sh", "antz-probe.sh", "antz-skills.sh", and
      "antz-set-model.sh" all exist under the resolved libdir
    And each of the four files carries the "antz:generated version=<current
      VERSION>" marker as a line-start header comment, inserted immediately
      after its "#!/bin/sh" shebang line
    And each of the three orchestration files is otherwise byte-for-byte
      its "scripts/orchestration/" source (the repo source files stay
      byte-unchanged by this change; only the installed copy gains the
      marker line)
    And running each installed file with "sh <path>" behaves exactly like
      running its source

  # ADD - libdirinstall-02: the libdir path is resolved once by install.sh,
  # honoring XDG_CONFIG_HOME.
  Scenario: libdirinstall-02
    When install.sh runs with XDG_CONFIG_HOME set to a non-default directory
    Then the four scripts install under "<that directory>/antz/scripts/"
    And the concrete resolved absolute path (no variable, no fallback
      token, no trailing slash) is what install.sh writes into every
      rendered prompt and command body that references a script
    When install.sh runs with XDG_CONFIG_HOME unset or empty
    Then the four scripts install under "$HOME/.config/antz/scripts/"

  # ADD - libdirinstall-03: the .bak.<ts> backup policy and the anchored
  # marker detection apply to libdir files unchanged.
  Scenario: libdirinstall-03
    Given a pre-existing file at a libdir script destination that does not
      carry the line-start "antz:generated" marker
    When install.sh installs the scripts
    Then that pre-existing file is backed up to "<file>.bak.<YYYYMMDDHHMMSS>"
      holding the original content byte-for-byte, before being overwritten
    And a pre-existing libdir file that does carry the marker is overwritten
      in place with no new backup, and its version marker is restamped
    And backups are never read, renamed, pruned, or deleted by install.sh

  # ADD - libdirinstall-04: --check (and the install-run report) also report
  # the installed scripts, keyed off each script's own marker version.
  Scenario: libdirinstall-04
    When the user runs "./install.sh --check"
    Then after the per-client report lines, the report carries one line per
      script artifact naming the script file and stating the same three
      outcomes the client lines state -- fresh install, already up to date,
      or "<old> -> <new>" drift -- each keyed off that installed script's
      own marker version versus the current VERSION
    And any intervening CHANGELOG.md entries print at most once for the
      whole report, never once per script
    And --check writes nothing: no libdir directory is created, no file is
      written or restamped, no backup appears
    And the same script report lines appear in an installing run

  # ADD - libdirinstall-05: fail-closed, atomic single-pass source read.
  Scenario: libdirinstall-05
    Given one of the four script sources cannot be read or fetched
      (missing file, failing curl stand-in on the remote path)
    When install.sh runs an install
    Then it exits non-zero naming the unreadable script, loudly
    And all four script sources are read or fetched before any destination
      file is written, so a failing source leaves the previous install
      (client files and libdir) completely intact -- one pass, no partial
      libdir from this run

  # ADD - libdirinstall-06: the libdir is client-independent and installs in
  # the same single pass; the invocation contract stays "sh <path>", with no
  # new CLI, hook, or plugin.
  Scenario: libdirinstall-06
    When install.sh runs for exactly one client
    Then the four scripts still install to the shared libdir (one libdir
      for both clients; a later install for the other client reuses and
      restamps it, last write wins, --check covers the mix)
    And one install.sh invocation writes the client agent files, the client
      command files, and the four libdir scripts together -- no second
      command, no post-install step
    And install.sh adds nothing to PATH, installs no hook or plugin, and
      does not require the exec bit: every invocation is
      "sh \"<resolved path>\" <arguments>"

  # MODIFY - libdirinstall-07: the fetch-architecture sentence is re-scoped
  # from the include injection to the script installation; the mechanism
  # survives, its subject changed.
  Scenario: libdirinstall-07
    When install.sh's executable code is inspected
    Then each of the four scripts is read or fetched through the one
      "fetch_file" helper (local checkout read, or RAW_BASE fetch honoring
      ANTZ_REF)
    And there is exactly one executable "curl -fsSL" invocation, inside
      fetch_file
    And the removed include-injection wording of install-render.md's
      refpin-05 ("the include injection still fetches through fetch_file")
      is re-scoped to this script-installation wording, with the one-curl
      and RAW_BASE-construction clauses unchanged

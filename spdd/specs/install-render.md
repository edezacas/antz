# Domain: install-render

## Goal
What `install.sh` renders and writes: the per-client agent files and the
`/antz` command, the shared scripts libdir, the `antz:generated` marker and
backup policy, and the `--check` report. The role prompts are not this file's
subject — they live verbatim in `agents/prompts/<role>.prompt`.

## Shared contracts
- **Source of truth**: `agents/prompts/<role>.prompt` (framework-agnostic,
  no client syntax) + `agents/meta/<role>.yaml` (`name`, `description`,
  `access`).
- **Agents**: `specifier`, `coder`, `verifier`, `orchestrator`.
- **Access levels** — `readonly`: read-only tools, no edit/write;
  `readwrite`: read-only plus edit/write (and the client's skill tool where
  one exists); `orchestrateonly`: read-only plus delegation. A rendering may
  grant the writer tools as pass-throughs so a delegated role keeps them, but
  the orchestrator never writes: that stays prompt-level.
- **Marker**: every installed file carries, as its first line after the
  frontmatter opener (scripts: immediately after the shebang), a line-start
  comment `# antz:generated version=<VERSION>`. A file counts as antz-managed
  only when the marker is at the line start.
- **Backup policy**: a pre-existing destination without that line-start marker
  is copied to `<file>.bak.<timestamp>` before being overwritten. Backups are
  never read, renamed, or deleted by `install.sh`.
- **Libdir**: `${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts`, resolved at
  runtime, shared by every client, holding the flow script.
- **Portability**: `install.sh` and every installed script are plain POSIX
  `sh` (no bash-only syntax), so they run under any POSIX shell, macOS
  `/bin/sh` in POSIX mode included. Scripts are invoked as
  `sh "<path>" <arguments>`: no exec bit is installed or required.

## Feature: Rendering and installation

  Background:
    Given the sources under "agents/" and "scripts/orchestration/", and one
      or more of Claude Code, OpenCode, and Pi detected or forced

  # ADD - installrender-01: each client gets native frontmatter
  Scenario: installrender-01
    When install.sh runs for a client
    Then every agent is written to that client's global agents directory
    And the rendered file carries that client's frontmatter fields (name and
      description; tools for Claude Code and Pi; mode and permission for
      OpenCode) followed by the role prompt body verbatim
    And the "/antz" command is written to that client's commands directory
    And the orchestrator body's "__ANTZ_SCRIPTS_DIR__" token is replaced by
      the resolved libdir, so no placeholder survives

  # ADD - installrender-02: the marker decides managed vs foreign
  Scenario: installrender-02
    When a destination file carries the marker as a line-start header comment
    Then it is overwritten in place with no backup
    And when it lacks that line-start marker (including a mid-line mention)
      it is backed up to "<file>.bak.<timestamp>" first

  # ADD - installrender-03: the flow script installs byte-faithfully
  Scenario: installrender-03
    When the flow script is installed
    Then the installed file is the source plus exactly one inserted line —
      the marker comment after the shebang — with every other byte untouched
    And a source that does not start with a "#!/bin/sh" shebang is refused
      loudly, leaving the previous install intact

  # ADD - installrender-04: --check reports without writing
  Scenario: installrender-04
    When install.sh runs with "--check"
    Then it prints the installed version versus the source VERSION and the
      intervening CHANGELOG.md entries, at most once per run
    And it writes nothing: no agent, no command, no libdir

  # ADD - installrender-05: the source ref is pinnable
  Scenario: installrender-05
    When ANTZ_REF names a tag or branch and no local checkout is available
    Then every fetched file comes from that ref
    And a local-checkout install reads from disk and ignores ANTZ_REF

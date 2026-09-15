# Domain: versioning

## Goal
The repo's versioning policy and how it is documented. `VERSION` (semver) and
`CHANGELOG.md` (Keep a Changelog) track changes to `agents/prompts/`,
`agents/meta/`, and `install.sh`. Any commit touching any of the three bumps
`VERSION` and adds a matching `CHANGELOG.md` entry in the same commit; grade a
multi-path commit by its most severe component — patch for wording or
refactor, minor for a role or rendered-behavior change, major for a workflow
or command-contract change. Changes to docs (`AGENTS.md`, `docs/`, `spdd/`)
and to `tests/` need no bump.

`install.sh` is tracked because it renders every installed file and embeds the
source `VERSION` in each marker comment, so an unbumped `install.sh`-only
change would leave installed copies stale while `--check` stays silent.

The policy lives in exactly one file, `AGENTS.md`; `CLAUDE.md` is a symlink to
it, so the two client conventions can never drift.

Enforcement is the maintainer's discipline plus the `--check` report: no
script, hook, or CI check verifies a bump. Every bump gets a local `vX.Y.Z` tag
on the bump commit, in the same change; tags push only on explicit request.

## Feature: Versioned surface and single-source policy

  # ADD - versioning-01: the tracked set
  Scenario: versioning-01
    When a commit changes "agents/prompts/", "agents/meta/", or "install.sh"
    Then "VERSION" is bumped and "CHANGELOG.md" gains a matching entry in the
      same commit
    And a commit that touches only docs or tests needs no bump
    And a mixed commit is still a bump commit, graded by its most severe
      component

  # ADD - versioning-02: the policy has one source
  Scenario: versioning-02
    When the reader opens "AGENTS.md"
    Then it states the tracked set, the same-commit rule, and the tag rule
    And "CLAUDE.md" resolves to the same bytes as "AGENTS.md" (a symlink, not
      a copy), so the two can never drift

  # ADD - versioning-03: the installed marker carries the version
  Scenario: versioning-03
    When install.sh writes any installed file
    Then the marker comment embeds the source "VERSION"
    And a later run reports the installed version against it, printing the
      intervening CHANGELOG.md entries when they differ

  # ADD - versioning-04: a bump is tagged locally
  Scenario: versioning-04
    When a bump commit is made
    Then a local tag "vX.Y.Z" for the new VERSION points at that commit
    And no tag is pushed without an explicit request

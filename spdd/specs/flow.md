# Domain: flow

## Goal
The machine-read contracts of one antz flow: the flow script's `start`
subcommand and its states, the working-tree layout a role reads and writes,
and the rejection counter the orchestrator routes on. Which role runs when,
and in which mode, is the orchestrator prompt's contract — not this file's.

## Shared contracts
- **Change directory**: `spdd/changes/<slug>/` — the sub-specs
  (`NN-<feature>.feature`), the change `README.md`, the single
  `e2e-qa.feature` when the change has one, `OPEN_QUESTIONS.md` when blocked,
  and `REJECTED.md` when the verifier rejected.
- **Archive directory**: `spdd/archive/<slug>/` — the change directory moved
  there unmodified on approval.
- **Domain specs**: `spdd/specs/<domain>.md`, one file per kebab-case domain.
- **Marker branch**: `antz/<slug>`, pointing at the commit the flow started
  from. The flow never commits to it; the work stays uncommitted in the main
  checkout, where the human owns every commit.

## Feature: The flow script's start subcommand

  Background:
    Given the installed flow script, invoked as "sh <path> start <slug>" from
      inside a git repository

  # ADD - flow-01: a valid slug on a new flow creates and checks out the marker branch
  Scenario: flow-01
    When the slug is lowercase letters, digits, and single hyphens, at most
      40 characters
    And the repository has at least one commit
    And no branch "antz/<slug>" exists
    And the working tree is clean while "spdd/changes/<slug>" does not exist
    Then the script prints exactly "state=started root=<absolute repo root>"
    And the branch "antz/<slug>" exists and is checked out

  # ADD - flow-02: re-invoking start on an existing flow reuses it
  Scenario: flow-02
    When the branch "antz/<slug>" already exists
    Then the script prints "state=reused root=<absolute repo root>"
    And it prints "dirty=yes" only when "git status --porcelain" is non-empty
    And nothing is created, moved, or deleted

  # ADD - flow-03: an invalid slug is rejected before any git work
  Scenario Outline: flow-03
    When the slug is "<slug>"
    Then the script prints exactly "state=bad_slug" and exits non-zero
    And no branch and no directory is created

    Examples:
      | slug                  |
      | (empty)               |
      | -leading              |
      | trailing-             |
      | double--hyphen        |
      | Uppercase             |
      | under_score           |
      | a-slug-longer-than-forty-characters |

  # ADD - flow-04: the preflight states stop before any mutation
  Scenario Outline: flow-04
    When <condition>
    Then the script prints exactly "<state>" and exits non-zero
    And nothing is created, moved, or checked out

    Examples:
      | condition                                    | state           |
      | git is not on PATH                           | state=no_git    |
      | the directory is not inside a git repository | state=no_repo   |
      | the repository has no commits                | state=no_commits |

  # ADD - flow-05: a new flow refuses a dirty tree, a resume does not
  Scenario: flow-05
    When no branch "antz/<slug>" and no "spdd/changes/<slug>" exist
    And "git status --porcelain" is non-empty
    Then the script prints exactly "state=tree_dirty" and exits non-zero
    And nothing is created, moved, or checked out
    And the same dirty tree proceeds with "state=started" once
      "spdd/changes/<slug>" exists

  # ADD - flow-06: a refused checkout is reported, never forced
  Scenario: flow-06
    When the switch onto "antz/<slug>" would overwrite uncommitted changes
    Then the script prints exactly "state=checkout_refused" and exits non-zero
    And nothing is stashed, reset, forced, or deleted

## Feature: The rejection counter

  Background:
    Given "spdd/changes/<slug>/REJECTED.md", appended to by the verifier on
      rejection and never overwritten

  # ADD - flow-07: the orchestrator's retry bound is the heading count
  Scenario: flow-07
    When the file holds one heading line reading exactly "## Rejection 1"
    Then the count is 1 and the flow relays the entry to the coder and lets
      the verifier run once more
    And when it holds "## Rejection 1" and "## Rejection 2" the count is 2 and
      the flow stops for good

  # ADD - flow-08: only the literal heading is counted
  Scenario: flow-08
    When a line mentions rejections without reading exactly "## Rejection <n>"
    Then it is not counted

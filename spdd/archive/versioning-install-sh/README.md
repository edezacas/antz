# Change: versioning-install-sh

## Goal

`AGENTS.md` and `CLAUDE.md` currently say `VERSION`/`CHANGELOG.md` track only
`agents/prompts/` and `agents/meta/`, and that "Changes elsewhere (`install.sh`,
docs) don't require a bump". That is wrong, per the user's decision (verbatim
intent, translated from Spanish):

> "En AGENTS.md y CLAUDE.md se dice que el cambio de versión es solo cuando se
> modifica agents/. Esto no es correcto. Se debe aumentar la versión siempre que
> se modifique algo de la carpeta agents o también install.sh ya que impacta
> directamente en los commands."

**New rule:** ANY commit that changes `agents/prompts/`, `agents/meta/`, **or
`install.sh`** must bump `VERSION` and add a matching `CHANGELOG.md` entry in
the same commit. Rationale: `install.sh` renders the installed commands/agents
directly and embeds `VERSION` in each installed file's marker comment
(`antz:generated version=X.Y.Z`); without a bump, `install.sh --check` cannot
report that installed command copies are out of date, so users get silently
stale commands after an install.sh-only change. The old exclusion sentence is
removed; the docs-only no-bump clause is preserved explicitly.

## Governing spec situation (for the verifier)

`spdd/specs/` contains only `set-model.md` — the `/antz-set-model` command
domain. **No governing spec covers repo policy/versioning docs.** This change
therefore defines a **new standalone spec domain**: at merge, the verifier
creates `spdd/specs/versioning.md` and merges every scenario from
`01-versioning.feature` and `e2e-qa.feature` into it as **ADD** (nothing
pre-exists, so there are no MODIFY/REMOVE tags anywhere in this change).

## Agreed design decisions (user-resolved)

1. **Tracked set = `agents/prompts/` + `agents/meta/` + `install.sh`.** Any
   commit touching any of the three bumps `VERSION` + matching `CHANGELOG.md`
   entry, same commit — regardless of what else the commit contains.
2. **Gradation mirrors the `agents/` scale, one rubric not two:**
   - **patch** — behavior-neutral/wording-only `install.sh` tweaks (comments,
     echo strings, internal refactors; no change to rendered output or reported
     behavior);
   - **minor** — behavior changes to install mechanics or the rendered
     commands/agents (rendered bodies, flags, install paths, detection,
     `--check` report);
   - **major** — breaking changes to the workflow contract or the rendered
     command contract (e.g. the `antz:generated` marker format that
     `/antz-set-model`'s management check depends on, the access→frontmatter
     mapping, install locations).
   Rationale: `install.sh`'s output *is* the shipped product surface (the
   installed agents and commands), so the same severity scale that already
   governs the sources it renders applies unchanged; a second, weaker rubric
   would invite under-bumping — the exact failure this rule exists to close.
   Mixed commits grade by their most severe component.
3. **Old sentence removed; docs-only clause preserved.** "Changes elsewhere
   (`install.sh`, docs) don't require a bump" is deleted from both files; the
   new text explicitly states that docs changes (`AGENTS.md`, `CLAUDE.md`,
   `docs/`, `spdd/`) and `tests/` require no bump.
4. **Non-goal: NO behavioral change to `install.sh` in this change.** Its
   existing marker/version/`--check` machinery already supports the new rule
   completely — with a bump, `--check` (keyed off the installed specifier
   agent file's embedded version, `install.sh:500-501`) reports the drift and
   prints the intervening changelog entries for *all* installed files, since
   every file is written with the same `$version`. This is a policy/docs
   change; `install.sh` is byte-for-byte untouched, including comments.

## Resolved specifier decisions (delegated; rationale documented)

1. **`install.sh` stays untouched entirely — including its stale line-21
   header comment.** `install.sh:21` restates the old scope ("VERSION +
   CHANGELOG.md track changes to agents/prompts/ and agents/meta/.") and will
   remain stale after this change. Editing it would drag `install.sh` into a
   commit that the new rule itself classifies as bump-mandatory, turning a
   clean docs-only change into a versioned one and muddying the "policy/docs
   change" framing; a comment fix ships for free inside the *next* change that
   legitimately touches `install.sh` (which must bump anyway). Recorded here
   as **accepted drift**; the next install.sh-touching change should correct
   line 21 as part of its mandatory-bump commit.
2. **`spdd/specs/set-model.md`'s versioning note (Invariants, lines ~623-626:
   "A change confined to `install.sh` ... does not require a
   `VERSION`/`CHANGELOG.md` bump") is left untouched.** Justification: (a) the
   statement was **true under the old rule at that change's merge time** — it
   records what was decided then, and the new rule is forward-looking;
   (b) the coder must not edit `spdd/specs/` by workflow rule, and the
   verifier's merge convention (scenario-by-scenario ADD/MODIFY/REMOVE) has no
   slot for rewriting an invariant bullet, so "fixing" it would mean
   out-of-convention surgery on a stable 839-line merged spec for zero
   behavioral effect; (c) the canonical home of the versioning policy is
   `AGENTS.md`/`CLAUDE.md`, which this change corrects. Risk accepted: a
   future specifier reading `set-model.md` may encounter the stale note; the
   supersession is recorded here and in `spdd/specs/versioning.md`'s origin
   once merged.
3. **`CHANGELOG.md:3` scope line is edited too** (extension of the user's
   two-file pin, flagged here for visibility): it reads "All notable changes to
   the antz agent definitions (`agents/prompts/`, `agents/meta/`) are
   documented here." Under the new rule, `install.sh` changes MUST add entries,
   so that sentence would contradict the rule at its point of use (a
   contributor following the header literally would skip the mandated entry).
   Editing it is free: `CHANGELOG.md` is an untracked path — docs-only, no
   bump — so this stays a docs-only change and the dogfooding story
   (e2e-qa-04) holds. Suggested wording (non-binding):
   "All notable changes to the antz agent definitions (`agents/prompts/`,
   `agents/meta/`) and to `install.sh` (which renders and installs them) are
   documented here." If the user disagrees, dropping this one edit leaves
   everything else in this change valid.
4. **`spdd/archive/` READMEs are historical records — never edited.** Their
   versioning notes were true under the old rule at their time:
   `spdd/archive/set-model-native-command/README.md:153-158` ("does not require
   a bump") and `spdd/archive/set-model-interactive-picker/README.md:196-206`
   ("no bump is required", plus its precedent note that native-command DID bump
   to 1.2.0 "presumably to surface its changelog entry via --check").
5. **Motivating example — the staleness `--check` cannot see today.** The
   `set-model-interactive-picker` change shipped an `install.sh` *behavior*
   change (the interactive-picker command rendering) **without a bump**:
   legal under the old rule, and visible right now — the change sits uncommitted
   in the working tree (`git status`: modified `install.sh`,
   `spdd/specs/set-model.md`, `tests/set-model-command_test.sh`; untracked
   `spdd/archive/set-model-interactive-picker/`) while `VERSION` still reads
   `1.2.0`. Consequence once shipped: an installed `/antz-set-model` copy from
   any `1.2.0` install carries marker `antz:generated version=1.2.0`, and the
   new source renders the *same* `version=1.2.0` — so `install.sh --check`
   reports "already up to date (antz 1.2.0)" while the installed command body
   lacks the picker entirely. Users who don't re-install are never told;
   users who do get no changelog narrative for what changed in their commands.
   (By contrast, `set-model-native-command` *did* bump to `1.2.0` — a
   maintainer courtesy the old rule didn't require, and the only reason
   `--check` had a changelog to print for that change.) e2e-qa-02 replays this
   staleness deterministically; e2e-qa-05 proves the bump closes it.
6. **Untracked complement.** Docs (`AGENTS.md`, `CLAUDE.md`, `docs/`, `spdd/`)
   and `tests/` require no bump; `VERSION`/`CHANGELOG.md` edits that ARE a bump
   are part of that bump, never separately tracked.
7. **This change itself requires NO bump** — its diff is docs-only, classified
   no-bump by the very clause it preserves. The repo's state at e2e-qa-04
   confirms it.

## Shared contracts

None required: this is a single docs-layer sub-spec (`01-versioning.feature`);
no other sub-spec depends on it. The only cross-file contract is internal to
the docs: `AGENTS.md` and `CLAUDE.md` must state the identical rule
(versioning-06).

## Suggested wording (non-binding; the contract is the scenario list)

Replacement for the first bullet of both `## Versioning` sections:

> - `VERSION` (semver) and `CHANGELOG.md` (Keep a Changelog format) track
>   changes to `agents/prompts/`, `agents/meta/`, and `install.sh`. Any commit
>   that changes any of those three must bump `VERSION` and add a matching
>   `CHANGELOG.md` entry in the same commit — patch for non-behavioral wording
>   tweaks (including comment/string-only `install.sh` tweaks), minor for
>   behavior changes (to the roles, or to `install.sh`'s install mechanics or
>   rendered commands/agents), major for breaking changes to the workflow
>   contract or the rendered command contract (directory layout, access model,
>   marker format, etc). Changes to docs (`AGENTS.md`, `CLAUDE.md`, `docs/`,
>   `spdd/`) and `tests/` don't require a bump — `install.sh` renders the
>   installed commands/agents directly and embeds `VERSION` in each installed
>   file's marker comment, so an unbumped `install.sh` change leaves installed
>   copies silently stale (`install.sh --check` would report them as up to
>   date).

The second and third bullets (marker/`--check` description; tag per bump) stay
as-is. A mixed agents/+install.sh commit grades by its most severe component.

## Files the coder will change (complete list, outside `spdd/changes/`)

1. `AGENTS.md` — `## Versioning` first bullet rewritten per the scenarios;
   other bullets preserved.
2. `CLAUDE.md` — identical edit (the two sections are byte-identical today and
   must remain in sync).
3. `CHANGELOG.md` — line 3 scope sentence only (see decision 3; one line).
4. No `VERSION` bump, no `CHANGELOG.md` entry, no other file.
5. Plus the coder's own new unit test suite asserting the documented content
   (e.g. `tests/versioning-rule_test.sh`; precedent:
   `tests/set-model-command_test.sh`), every test name tagged with its
   `versioning-<index>` scenario id.

## Relevant files found during investigation (pointers, not a walkthrough)

- `AGENTS.md:34-37` and `CLAUDE.md:34-37` — the `## Versioning` sections
  (three bullets, currently byte-identical across both files); line 35 of each
  holds the wrong sentence.
- `CHANGELOG.md:3` — stale scope line (decision 3).
- `install.sh:21` — stale header comment restating the old tracked set
  (accepted drift, decision 1; do NOT touch).
- `install.sh:148,157,163,169,436` — the five render sites embedding
  `$version` in the `antz:generated` marker (no change needed; the machinery
  the rule relies on).
- `install.sh:453-505` — `installed_version_of` / `changelog_since` /
  `report_version` and the `--check` path (`--check` is keyed off the
  installed specifier agent file, `install.sh:500-501`); fully supports the
  new rule as-is (non-goal decision 4).
- `spdd/specs/set-model.md:623-626` — the historical versioning invariant left
  untouched (decision 2).
- `spdd/archive/set-model-native-command/README.md:153-158` and
  `spdd/archive/set-model-interactive-picker/README.md:196-206` — historical
  versioning notes, immutable (decision 4).
- `VERSION` — reads `1.2.0`; unchanged by this change.
- `README.md:53` — describes the marker/`--check` machinery (accurate; not a
  policy-scope statement; no edit).

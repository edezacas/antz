# Domain: e2e-qa — bench-opencode-provider-config
#
# End-to-end QA at the user-visible CLI level: benching OpenCode models whose
# provider is declared in the host's "opencode.json", plus the corrected
# credential sourcing. benchcfg-01 and benchcfg-03 are fully executable
# hermetically (a recording stub OpenCode CLI stands in for the real one, per
# the repo's established e2e convention). benchcfg-02 is a live-session
# scenario judged by mechanism: the verifier observes one real repetition
# against a provider-declared model, since a real LLM answer cannot be made
# deterministic.

  Background:
    Given a checkout of antz with this change applied
    And an isolated environment (a controlled home and temp output paths) so
      QA never touches the real "~/.config/opencode" or
      "~/.local/share/opencode" and never writes outside its temp space

# ADD - benchcfg-01: the user's headline workflow -- bench an OpenCode model
# whose provider is declared in the host's opencode.json; the provider config
# and the data-dir credential reach every repetition's sandbox read-only.
Scenario: benchcfg-01
  Given the controlled home declares a custom provider in
    ".config/opencode/opencode.json" and holds its API key in
    ".local/share/opencode/auth.json"
  When the user runs "sh bench/antz-bench.sh --client opencode --model
    <provider>/<model> --repetitions 2 --jsonl <temp>/results.jsonl"
    (a recording stub OpenCode CLI standing in for the real one)
  Then the exit status is 0 and "<temp>/results.jsonl" holds exactly 2
    records, each with client "opencode" and model_pinned
    "<provider>/<model>"
  And each repetition's sandbox carried both files read-only and
    byte-identical
  And the host files keep their bytes and locations after the run

# ADD - benchcfg-02: the point of the change, observed live -- a
# provider-declared model answers inside the sandbox instead of erroring at
# model resolution.
Scenario: benchcfg-02
  Given OpenCode installed with its API key in the data dir and a provider
    declared in "opencode.json" whose models are unreachable without that
    file
  When the user runs "sh bench/antz-bench.sh --client opencode --model
    <provider>/<model> --repetitions 1 --jsonl <temp>/live.jsonl" with the
    real client
  Then the exit status is 0, the record exists, and its telemetry shows the
    client resolved the pinned model: models_used names it and the token
    totals are non-null -- not the all-null error pattern the missing
    config produced
  And the measurement wrote nothing outside its sandbox and results

# ADD - benchcfg-03: without a provider config the run still completes --
# the carry is skipped, never fabricated.
Scenario: benchcfg-03
  When the user runs "sh bench/antz-bench.sh --client opencode --repetitions
    1 --jsonl <temp>/noconfig.jsonl" from a controlled home holding no
    "opencode.json" (a recording stub OpenCode CLI standing in)
  Then the exit status is 0, "<temp>/noconfig.jsonl" holds exactly one
    record, and no "opencode.json" appeared in the sandbox

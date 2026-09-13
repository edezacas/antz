# Domain: install-render (new; second sub-spec into the same domain)

## Feature: Description values are emitted as quoted YAML scalars in the rendered frontmatter

  Background:
    Given a staged checkout (install.sh, agents/, scripts/orchestration/,
      VERSION, CHANGELOG.md) and an isolated HOME, so renders never touch
      the real "~/.claude" or "~/.config/opencode"
    And the source descriptions in "agents/meta/*.yaml" and the hardcoded
      short description in render_set_model_command are unchanged -- only
      their rendered form gains quoting

  # ADD - quoting-01: the role agents' rendered frontmatter quotes the
  # description value, on both clients, for all four roles. Every rendered
  # agent file's description line starts with `description: "` and ends
  # with `"` -- a double-quoted YAML scalar, robust to colons, leading
  # characters, and other YAML-hostile text.
  Scenario: quoting-01
    When install.sh renders all four agents for both clients
    Then every rendered agent file's frontmatter description line matches
      `description: "` and ends with `"` with no characters after it
    And the quoted value is the meta file's description for that role,
      byte-preserved inside the quotes

  # ADD - quoting-02: the /antz-set-model command's rendered frontmatter
  # quotes its description too (render_set_model_command's short_desc) --
  # the third quoting site the plan's first pass omitted.
  Scenario: quoting-02
    When install.sh renders the /antz-set-model command for each client
    Then each copy's frontmatter description line matches `description: "`
      and ends with `"` with no characters after it

  # ADD - quoting-03: quoting is real YAML quoting, not just wrapping: an
  # embedded double quote or backslash in a source description is escaped
  # per YAML double-quoted-scalar rules, so the rendered line stays a
  # valid single-line scalar.
  Scenario Outline: quoting-03
    When install.sh renders a staged meta description reading <raw>
    Then the rendered description line is exactly `description: <rendered>`

    Examples:
      | raw            | rendered               |
      | Says "hi"      | "Says \"hi\""          |
      | back\slash     | "back\\slash"          |
      | a "b" \ c      | "a \"b\" \\ c"         |

  # ADD - quoting-04: quoting is value-preserving: for every rendered
  # description line, removing the outer double quotes and undoing the
  # escaping reproduces the source description byte-for-byte. Quoting must
  # never alter what a client reads as the description.
  Scenario: quoting-04
    When install.sh renders all agents and both command files
    Then for each rendered description line, stripping the outer quotes
      and YAML-unescape yields exactly the source description text

  # ADD - quoting-05: the suites that pin pre-change rendered byte-identity
  # are updated within this change, under the repo's loud-retirement
  # convention, so the full unit suite passes with the quoted renders.
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

### Invariants
- No description VALUE changes anywhere: agents/meta/*.yaml is untouched;
  quoting transforms only the rendered frontmatter line. The rendered
  value a client parses is byte-identical to the source description.
- Only the three sites the plan names gain quoting: render_claude,
  render_opencode, and render_set_model_command's short_desc. The /antz
  command renderers (render_claude_command / render_opencode_command) and
  their hardcoded descriptions are out of scope.
- Marker line, name/mode/permission/tools frontmatter, and rendered bodies
  are unchanged by this sub-spec.
- All rendered output stays deterministic (a second render is
  byte-identical), and install.sh stays parseable POSIX sh.

## Out of scope
- Changing any description text itself (agents/meta/*.yaml and the
  hardcoded command descriptions are read-only inputs here).
- Quoting other frontmatter fields or the /antz command descriptions.
- Multi-line or block-scalar description handling (meta_field reads
  single-line values only; the quoted form is a single-line scalar).
- Any change to the marker/backup machinery (sub-spec 01) or the ref
  mechanism (sub-spec 03).

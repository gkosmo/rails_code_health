# Accuracy v1: Trustworthy Rails Checks

**Status:** Design approved, awaiting implementation plan
**Target release:** v0.3.0
**Date:** 2026-05-12

## Context

`rails_code_health` v0.2.0 is a working gem with AST-based Ruby analysis and Rails-specific checks for controllers, models, views, helpers, migrations, services, interactors, and serializers. It cites Tornhill & Borg's "Code Red: The Business Impact of Code Quality" research as inspiration.

Today, many Rails-specific checks are implemented as regex matches against the entire file source rather than AST-scoped analysis. This produces false positives that erode trust in the tool. Several methods also contain inverted logic, hard-coded thresholds, or admitted simplifications. Together these undermine the gem's core promise: a credible health score.

This spec covers the first of two planned accuracy improvements: **fixing the existing checks so they actually do what they claim.** A follow-up spec ("Accuracy v2") will add hotspot/churn analysis from git history and re-align scoring with the cited research.

## Goals

- Eliminate the most common sources of false positives in Rails-specific checks by replacing regex-on-source with AST-scoped analysis.
- Fix specific known bugs where current behavior contradicts its stated intent.
- Ship the changes as v0.3.0 with a clear CHANGELOG entry. Scores on existing projects will change; that is expected and accepted.
- Every changed or new check is backed by fixture-based RSpec tests: at least one fixture that should trip it, at least one that should not.

## Non-goals (deferred to Accuracy v2 or later)

- Hotspot / churn analysis from git history.
- Re-aligning scoring weights with the Tornhill/Borg paper methodology.
- HTML reports, GitHub Action, CI integration.
- Any new file-type analyzer (mailers, jobs, channels, etc.).
- Refactoring duplication beyond what these fixes require.
- Adding new code smells. The point is to make existing ones correct, not add more.

## The specific problems to fix

### A. Rails-analyzer false positives from file-wide regex

**A1. `has_direct_model_access?` (rails_analyzer.rb:125)**
Matches model-like calls anywhere in the file. Triggers on calls inside `private` helper methods that legitimately do data access. Fix: walk public defs only and only inspect their bodies.

**A2. `has_business_logic?` (rails_analyzer.rb:147)**
The regex `/if.*&&.*/` matches any compound conditional, including authorization checks like `if logged_in? && admin?`. Also fires on any `.each do`. Fix: examine action-method bodies only; use stricter signals (arithmetic, calls to model writers, nested loops with conditionals).

**A3. `count_controller_actions` (rails_analyzer.rb:103) + `private_controller_method?` (rails_analyzer.rb:707)**
Logic is inverted: `private_controller_method?` returns true for `show`, `new`, `edit`, `create`, `update`, `destroy`, and any `*_params` — but those are the canonical *public* RESTful actions. The seven standard actions are currently excluded from the action count, while `before_action`-targeted private helpers may be counted. Fix: parse `private` / `protected` keyword nodes and only count public defs as actions.

**A4. Model macro counts: `count_associations`, `count_validations`, `count_callbacks`, `count_scopes` (rails_analyzer.rb:196–231)**
All regex-based. Count occurrences inside comments, strings, `concerns/` blocks, anywhere. Fix: AST send-node walk scoped to the class body, matching the actual macro calls.

**A5. `has_fat_model_smell?` (rails_analyzer.rb:233)**
Uses `@source.lines.count` (total lines including blank/comments) and `find_nodes(@ast, :def)` (file-scoped, descends into nested classes). Fix: use code-line count and class-scoped method count.

**A6. Migration `has_data_changes?` (rails_analyzer.rb:354)**
Misses `Model.find_each`, `Model.update`, `reversible do`, and raw SQL via `ActiveRecord::Base.connection.execute`. Fix: AST + targeted source patterns. Document the remaining limitation rather than overpromising.

**A7. View `count_view_logic_lines` (rails_analyzer.rb:274)**
The regex `/<%((?!%>).)*if|unless|case|for|while/` is malformed: the `if|unless|...` alternation is outside the `<%...%>` group, so it matches any line containing those keywords — including HTML text and attribute values. Fix: extract each `<% %>` fragment and inspect its Ruby content.

**A8. Service `detect_service_dependencies` (rails_analyzer.rb:434)**
Same file-wide regex problem. The `File.` check matches `Profile.` etc. Fix: AST const + send node inspection, or at minimum word-boundary regex.

### B. Ruby-analyzer bugs

**B1. `count_public_methods_in_class` (ruby_analyzer.rb:247)**
Comment admits it returns the same as `count_methods_in_class`. Fix: track `private` / `protected` / `public` visibility modifier nodes while walking the class body, plus inline forms (`private def foo`).

**B2. `count_parameters` (ruby_analyzer.rb:252)**
Counts all `args_node.children`, which may include block-pass nodes and splat metadata. Verify with fixtures (positional, keyword, splat, double-splat, block) and tighten.

**B3. `calculate_max_nesting_depth` (ruby_analyzer.rb:118)**
`nesting_node?` treats `:begin` and `:block` as nesting. `:begin` is just sequence grouping and counting it inflates depth. Fix: precise definition — count only true control-flow scopes (`:if`, `:case`, `:while`, `:until`, `:for`, and `:block` only when its body contains control flow). Document the chosen rule.

**B4. Duplicated `find_nodes` recursion (ruby_analyzer.rb:93, rails_analyzer.rb:697)**
Two copies. Neither stops at class/module/def boundaries, which contributes to A4 and A5 inaccuracies. Fix: extract to a shared `ASTHelpers` module and add a scoped variant.

### C. Configuration / scoring edges

**C1. Hard-coded thresholds inside detectors**
`detect_god_classes` (ruby_analyzer.rb:173), `detect_high_complexity_methods` (line 190), `detect_too_many_parameters` (line 206), and `detect_nested_conditionals` (line 222) use inline literals (`400`, `20`, `15`, `5`, `4`). Fix: read from `RailsCodeHealth.configuration.thresholds`. Add any missing threshold keys.

## Architecture

The fixes touch many methods but introduce only one structural change.

### New internal module: `ASTHelpers`

Location: `lib/rails_code_health/ast_helpers.rb`

Public interface:
- `find_nodes(node, type, &block)` — current behavior (descends everything).
- `find_nodes_in_scope(node, type, &block)` — same, but does not descend into nested `:class`, `:module`, or `:def` nodes. Powers class-scoped counts.
- `public_defs(class_node)` / `private_defs(class_node)` — walk a class body tracking `:send` nodes for `private` / `protected` / `public` modifiers, plus inline `private def foo` forms; return defs grouped by visibility. Powers B1, A3, A1.
- `class_body_sends(class_node, method_name)` — find direct `:send` nodes in the class body whose method is `method_name` (e.g., `has_many`, `validates`), without descending into method bodies. Powers A4.
- `erb_ruby_fragments(source)` — iterator yielding the Ruby code inside each `<% %>` / `<%= %>` tag, handling multi-line tags greedily. Powers A7.

Both analyzers `include ASTHelpers`. No behavior change beyond what each individual fix introduces.

**Why a module, not a base class?** The two analyzers have different jobs and shouldn't share inheritance for the sake of code reuse. A module of pure functions is the lightest touch and preserves their independence.

### Changes per file

```
lib/rails_code_health/
  ast_helpers.rb          # NEW
  ruby_analyzer.rb        # changed: uses ASTHelpers, fixes B1-B4, C1
  rails_analyzer.rb       # changed: uses ASTHelpers, fixes A1-A8
  configuration.rb        # changed: add missing threshold keys for C1
  # everything else unchanged
```

The shape of every hash returned by the analyzers (the keys consumed by `HealthCalculator` and `ReportGenerator`) is preserved. We are changing the values inside, not the contract.

## Testing strategy

Validation is fixture-based RSpec tests, not real-app smoke runs. For every changed check, write paired expectations: at least one fixture that should trip it, at least one that should not.

### Fixture layout

```
spec/
  fixtures/
    code_samples/                                       # NEW
      controllers/
        thin_restful_controller.rb                      # no smells
        controller_with_business_logic.rb               # A2 should fire
        controller_with_direct_model_in_action.rb       # A1 should fire
        controller_with_model_in_private_helper.rb      # A1 should NOT fire
        controller_with_private_helpers.rb              # A3: action count is N, not N+helpers
      models/
        thin_model.rb
        fat_model.rb
        model_with_concerns_block.rb                    # A4: included do block
        model_with_validations_in_comments.rb           # A4: regex would miscount
      views/
        simple_view.html.erb
        view_with_logic.html.erb
        view_with_keyword_in_text.html.erb              # A7: 'if' in plain text
      migrations/
        schema_only_migration.rb
        migration_with_find_each.rb                     # A6
        migration_with_raw_sql.rb                       # A6
      services/
        plain_service.rb
        service_with_profile_model.rb                   # A8: 'File.' / 'Profile.' false positive
      ruby/
        class_with_private_methods.rb                   # B1
        class_with_inline_private.rb                    # B1: inline `private def foo`
        method_with_kwargs.rb                           # B2
        method_with_begin_rescue.rb                     # B3: :begin should not inflate depth
```

### Spec structure

For each changed analyzer method, paired expectations:

```ruby
describe '#has_direct_model_access?' do
  it 'returns true when a model call is in a controller action' do
    result = analyze('controllers/controller_with_direct_model_in_action.rb', :controller)
    expect(result[:has_direct_model_access]).to be true
  end

  it 'returns false when the model call is only inside a private helper' do
    result = analyze('controllers/controller_with_model_in_private_helper.rb', :controller)
    expect(result[:has_direct_model_access]).to be false
  end
end
```

### Existing tests

Keep them passing where they reflect intended behavior. For any test that currently asserts broken behavior (e.g., relies on `private_controller_method?` excluding `:create`), update the test and call out the change in the implementation plan.

### What we are not automating

Running against a real open-source Rails app. That is a one-shot human check before release, not an automated test. The release checklist will include it.

## Risks

1. **Scores will move on real codebases.** Decided: accept it, bump to v0.3.0, document in CHANGELOG. Risk is communication, not implementation.

2. **AST visibility tracking is the trickiest piece.** `private` has bare and inline forms; `private_class_method` and `class << self` add edge cases. Mitigation: dedicated fixtures for each form. `class << self` is best-effort, not exhaustive — documented as such.

3. **ERB parsing is regex-based, not a real parser.** Multi-line `<% %>` blocks could be misread. Mitigation: greedy multi-line extraction plus a multi-line fixture. Accept that some ERB edge cases will not be handled — this is a heuristic tool.

4. **Scope creep.** Many small fixes invite "while I'm here" refactors. The implementation plan must explicitly forbid unrelated changes.

## Implementation sequencing (for the plan)

1. Land `ASTHelpers` module + tests, no behavior change yet.
2. RubyAnalyzer fixes (B1–B4, C1) — independent of Rails analyzer.
3. RailsAnalyzer controller fixes (A1–A3).
4. RailsAnalyzer model fixes (A4–A5).
5. RailsAnalyzer view fixes (A7).
6. RailsAnalyzer migration + service fixes (A6, A8).
7. CHANGELOG, README note, version bump to 0.3.0.

Each step has its own fixtures and a passing test run before moving to the next.

## Success criteria

- All new fixture-paired tests pass.
- Full existing RSpec suite passes (with documented intentional updates).
- A manual smoke run against one open-source Rails app produces a report with no obviously wrong findings.
- CHANGELOG has a "Changed (may affect scores)" section listing every smell whose firing rules moved.
- Version bumped to 0.3.0 in `lib/rails_code_health/version.rb`.

## Behavior changes summary (preview of CHANGELOG)

For v0.3.0 "Changed (may affect scores)":
- Controller action count now correctly excludes private/protected methods and `*_params` helpers, and includes the standard RESTful actions.
- Direct model access in controllers is now only flagged inside public action methods.
- Business logic detection in controllers uses stricter signals (no longer fires on any compound `if` or any `.each do`).
- Model association/validation/callback/scope counts no longer match occurrences inside comments, strings, or nested scopes.
- Fat model detection uses code lines and class-scoped method count.
- View logic line count no longer mismatches plain HTML containing keywords like `if`.
- Service dependency detection uses word boundaries to prevent false positives like `Profile.` matching the `File.` check.
- Migration data-change detection covers `find_each`, `Model.update`, `reversible`, and raw connection SQL.
- Nesting-depth calculation no longer counts `:begin` as a nesting level.
- Public-method counts in classes now correctly account for `private` / `protected` modifiers (bare and inline forms).
- God class / high complexity / parameter / nesting thresholds are now read from configuration instead of hard-coded.

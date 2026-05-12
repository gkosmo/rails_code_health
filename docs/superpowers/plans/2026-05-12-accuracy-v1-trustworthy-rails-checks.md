# Accuracy v1: Trustworthy Rails Checks — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace regex-on-source Rails checks in `rails_code_health` with AST-scoped analysis, fix specific known bugs, and ship as v0.3.0 with fixture-based RSpec tests.

**Architecture:** Introduce one shared module (`ASTHelpers`) for scoped AST traversal and visibility-aware def collection. Rewrite the affected methods in `RubyAnalyzer` and `RailsAnalyzer` to use it. Public hash shapes returned by the analyzers stay the same — only the values change.

**Tech Stack:** Ruby (gem), `parser` gem for AST, RSpec for tests, RuboCop AST (already a dep).

**Spec:** `docs/superpowers/specs/2026-05-12-accuracy-v1-trustworthy-rails-checks-design.md`

---

## Engineer prerequisites

If you have never worked in this gem before, read these first:

- `lib/rails_code_health/ruby_analyzer.rb` — generic Ruby AST analysis
- `lib/rails_code_health/rails_analyzer.rb` — Rails-specific checks (this is where most fixes land)
- `lib/rails_code_health/configuration.rb` — threshold lookup
- `spec/spec_helper.rb` — SimpleCov + RSpec config
- `spec/lib/rails_code_health/rails_analyzer_spec.rb` — current test style (uses `Tempfile`; we'll add a fixture loader alongside)

**Test runner:** `bundle exec rspec` (from the project root). Run a single file with `bundle exec rspec spec/lib/rails_code_health/<file>_spec.rb`.

**Commit style:** present-tense conventional-ish, e.g., `feat: add ASTHelpers module`, `fix: count controller actions by visibility`. The repo doesn't have a strict format; keep messages short and accurate.

**Branch / scope discipline:** This plan is bounded. Do not:
- Refactor unrelated code "while you're here."
- Add new code smells.
- Touch `HealthCalculator` or `ReportGenerator` — the data contract is preserved.
- Fix the misspelled `config/tresholds.json` file (real bug, but explicitly out of scope; flag it but don't touch).

---

## Task 1: Add fixture-loader support and an empty fixtures directory

**Files:**
- Create: `spec/support/fixture_loader.rb`
- Create: `spec/fixtures/code_samples/.keep`
- Modify: `spec/spec_helper.rb` (add support file require)

- [ ] **Step 1: Write the failing test**

Create `spec/lib/rails_code_health/fixture_loader_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe RailsCodeHealthFixtures do
  describe '.path_for' do
    it 'returns an absolute path under spec/fixtures/code_samples' do
      path = described_class.path_for('ruby/method_with_kwargs.rb')
      expect(path.to_s).to end_with('spec/fixtures/code_samples/ruby/method_with_kwargs.rb')
      expect(path).to be_an_instance_of(Pathname)
    end

    it 'raises a clear error when fixture is missing' do
      expect { described_class.path_for('does_not_exist.rb') }
        .to raise_error(ArgumentError, /fixture not found/)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/fixture_loader_spec.rb`
Expected: FAIL — `uninitialized constant RailsCodeHealthFixtures`.

- [ ] **Step 3: Create the fixture loader**

Create `spec/support/fixture_loader.rb`:

```ruby
require 'pathname'

module RailsCodeHealthFixtures
  ROOT = Pathname.new(File.expand_path('../fixtures/code_samples', __dir__))

  def self.path_for(relative_path)
    path = ROOT.join(relative_path)
    raise ArgumentError, "fixture not found: #{relative_path}" unless path.exist?
    path
  end
end
```

- [ ] **Step 4: Wire the support file into spec_helper**

Edit `spec/spec_helper.rb`. After `require_relative '../lib/rails_code_health'`, add:

```ruby
Dir[File.expand_path('support/**/*.rb', __dir__)].sort.each { |f| require f }
```

- [ ] **Step 5: Create the fixtures directory placeholder**

Create empty file `spec/fixtures/code_samples/.keep` (just so git tracks the directory).

- [ ] **Step 6: Run the test to verify it passes**

Run: `bundle exec rspec spec/lib/rails_code_health/fixture_loader_spec.rb`
Expected: PASS (both examples).

- [ ] **Step 7: Run the full suite to confirm nothing else broke**

Run: `bundle exec rspec`
Expected: existing examples all pass (some may already be failing on `main` due to the bugs we're about to fix — note any pre-existing failures, do not "fix" them yet).

- [ ] **Step 8: Commit**

```bash
git add spec/support/fixture_loader.rb spec/spec_helper.rb spec/fixtures/code_samples/.keep spec/lib/rails_code_health/fixture_loader_spec.rb
git commit -m "test: add RailsCodeHealthFixtures loader and fixtures directory"
```

---

## Task 2: Introduce `ASTHelpers` module (find_nodes + find_nodes_in_scope)

**Files:**
- Create: `lib/rails_code_health/ast_helpers.rb`
- Create: `spec/lib/rails_code_health/ast_helpers_spec.rb`
- Create: `spec/fixtures/code_samples/ruby/nested_class.rb`

- [ ] **Step 1: Create the nested-class fixture**

Create `spec/fixtures/code_samples/ruby/nested_class.rb`:

```ruby
class Outer
  def outer_method
    1
  end

  class Inner
    def inner_method
      2
    end
  end
end
```

- [ ] **Step 2: Write the failing test**

Create `spec/lib/rails_code_health/ast_helpers_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe RailsCodeHealth::ASTHelpers do
  let(:dummy) do
    Class.new { include RailsCodeHealth::ASTHelpers }.new
  end

  let(:ast) do
    source = File.read(RailsCodeHealthFixtures.path_for('ruby/nested_class.rb'))
    Parser::CurrentRuby.parse(source)
  end

  describe '#find_nodes' do
    it 'descends into nested classes' do
      defs = []
      dummy.find_nodes(ast, :def) { |n| defs << n.children[0] }
      expect(defs).to contain_exactly(:outer_method, :inner_method)
    end
  end

  describe '#find_nodes_in_scope' do
    it 'stops at nested class boundaries' do
      outer_class = ast # the top-level node IS the outer class
      defs = []
      dummy.find_nodes_in_scope(outer_class, :def) { |n| defs << n.children[0] }
      expect(defs).to contain_exactly(:outer_method)
    end

    it 'stops at nested module boundaries' do
      source = <<~RUBY
        class Foo
          def a; end
          module Bar
            def b; end
          end
        end
      RUBY
      node = Parser::CurrentRuby.parse(source)
      defs = []
      dummy.find_nodes_in_scope(node, :def) { |n| defs << n.children[0] }
      expect(defs).to contain_exactly(:a)
    end

    it 'stops at nested def boundaries when type would otherwise match' do
      source = <<~RUBY
        class Foo
          def a
            # If this were a real lambda or defs, we'd skip it.
            puts "x"
          end
        end
      RUBY
      node = Parser::CurrentRuby.parse(source)
      sends = []
      dummy.find_nodes_in_scope(node, :send) { |n| sends << n.children[1] }
      # We only want sends at the class body level, not inside the method.
      expect(sends).to be_empty
    end
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/ast_helpers_spec.rb`
Expected: FAIL — `uninitialized constant RailsCodeHealth::ASTHelpers`.

- [ ] **Step 4: Implement ASTHelpers**

Create `lib/rails_code_health/ast_helpers.rb`:

```ruby
module RailsCodeHealth
  module ASTHelpers
    SCOPE_BOUNDARY_TYPES = %i[class module def defs sclass].freeze

    # Yields every descendant (and the node itself) of the given type.
    # Descends into all children.
    def find_nodes(node, type, &block)
      return unless node.is_a?(Parser::AST::Node)

      yield(node) if node.type == type
      node.children.each { |child| find_nodes(child, type, &block) }
    end

    # Like find_nodes, but does not descend into nested class/module/def/defs/sclass
    # nodes. The starting node itself is inspected; its body is walked, but nested
    # scope-introducing constructs are not entered.
    def find_nodes_in_scope(node, type, &block)
      return unless node.is_a?(Parser::AST::Node)

      yield(node) if node.type == type

      node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)

        if SCOPE_BOUNDARY_TYPES.include?(child.type) && child != node
          # Don't descend into nested scopes.
          next
        end

        find_nodes_in_scope(child, type, &block)
      end
    end
  end
end
```

Wire it up in `lib/rails_code_health.rb`. Edit the file: after the `require_relative 'rails_code_health/version'` line, add:

```ruby
require_relative 'rails_code_health/ast_helpers'
```

(The other `require_relative`s come after; ASTHelpers must load before the analyzers.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/lib/rails_code_health/ast_helpers_spec.rb`
Expected: PASS (all four examples).

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: no new failures vs. Task 1 baseline.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/ast_helpers.rb lib/rails_code_health.rb \
        spec/lib/rails_code_health/ast_helpers_spec.rb \
        spec/fixtures/code_samples/ruby/nested_class.rb
git commit -m "feat: add ASTHelpers with find_nodes and find_nodes_in_scope"
```

---

## Task 3: Add visibility-aware helpers to `ASTHelpers`

**Files:**
- Modify: `lib/rails_code_health/ast_helpers.rb`
- Modify: `spec/lib/rails_code_health/ast_helpers_spec.rb`
- Create: `spec/fixtures/code_samples/ruby/class_with_private_methods.rb`
- Create: `spec/fixtures/code_samples/ruby/class_with_inline_private.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/ruby/class_with_private_methods.rb`:

```ruby
class Example
  def pub_one
    1
  end

  def pub_two
    2
  end

  private

  def priv_one
    3
  end

  def priv_two
    4
  end

  protected

  def prot_one
    5
  end

  public

  def pub_three
    6
  end
end
```

`spec/fixtures/code_samples/ruby/class_with_inline_private.rb`:

```ruby
class Example
  def pub_one
    1
  end

  private def priv_one
    2
  end

  def pub_two
    3
  end
end
```

- [ ] **Step 2: Write the failing tests**

Append to `spec/lib/rails_code_health/ast_helpers_spec.rb` (inside the existing `describe RailsCodeHealth::ASTHelpers do ... end` block):

```ruby
  describe '#defs_by_visibility' do
    it 'classifies bare modifier blocks (private/protected/public)' do
      source = File.read(RailsCodeHealthFixtures.path_for('ruby/class_with_private_methods.rb'))
      class_node = Parser::CurrentRuby.parse(source) # top-level is the class
      result = dummy.defs_by_visibility(class_node)

      expect(result[:public].map { |n| n.children[0] }).to contain_exactly(:pub_one, :pub_two, :pub_three)
      expect(result[:private].map { |n| n.children[0] }).to contain_exactly(:priv_one, :priv_two)
      expect(result[:protected].map { |n| n.children[0] }).to contain_exactly(:prot_one)
    end

    it 'classifies inline `private def foo` correctly' do
      source = File.read(RailsCodeHealthFixtures.path_for('ruby/class_with_inline_private.rb'))
      class_node = Parser::CurrentRuby.parse(source)
      result = dummy.defs_by_visibility(class_node)

      expect(result[:public].map { |n| n.children[0] }).to contain_exactly(:pub_one, :pub_two)
      expect(result[:private].map { |n| n.children[0] }).to contain_exactly(:priv_one)
    end

    it 'returns empty groups for a class with no methods' do
      class_node = Parser::CurrentRuby.parse("class Empty\nend")
      result = dummy.defs_by_visibility(class_node)
      expect(result[:public]).to eq([])
      expect(result[:private]).to eq([])
      expect(result[:protected]).to eq([])
    end
  end

  describe '#class_body_sends' do
    it 'returns top-level sends in the class body, not inside methods' do
      source = <<~RUBY
        class Foo
          has_many :bars
          validates :name, presence: true
          def go
            has_many :ignored # this is inside a method body
          end
        end
      RUBY
      class_node = Parser::CurrentRuby.parse(source)

      has_many_sends = dummy.class_body_sends(class_node, :has_many)
      validates_sends = dummy.class_body_sends(class_node, :validates)

      expect(has_many_sends.size).to eq(1)
      expect(validates_sends.size).to eq(1)
    end

    it 'does not match calls inside nested classes/modules' do
      source = <<~RUBY
        class Foo
          has_many :outers
          class Bar
            has_many :inners
          end
        end
      RUBY
      class_node = Parser::CurrentRuby.parse(source)
      expect(dummy.class_body_sends(class_node, :has_many).size).to eq(1)
    end
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec rspec spec/lib/rails_code_health/ast_helpers_spec.rb`
Expected: the new examples fail with `NoMethodError: undefined method 'defs_by_visibility'` / `'class_body_sends'`.

- [ ] **Step 4: Implement the helpers**

Edit `lib/rails_code_health/ast_helpers.rb`. Inside `module ASTHelpers`, append:

```ruby
    VISIBILITY_MODIFIERS = %i[public private protected].freeze

    # Returns a hash { public: [def_nodes], private: [def_nodes], protected: [def_nodes] }
    # for the given class node. Handles bare modifier blocks and inline `private def foo`.
    # `class << self` is best-effort: any defs inside it are NOT included here.
    def defs_by_visibility(class_node)
      result = { public: [], private: [], protected: [] }
      return result unless class_node.is_a?(Parser::AST::Node)
      return result unless %i[class module].include?(class_node.type)

      current = :public
      body = class_body_children(class_node)

      body.each do |child|
        next unless child.is_a?(Parser::AST::Node)

        if child.type == :send && child.children[0].nil? &&
           VISIBILITY_MODIFIERS.include?(child.children[1])
          modifier = child.children[1]
          if child.children.length == 2
            # bare modifier — changes default for subsequent defs
            current = modifier
          else
            # inline form: `private def foo` or `private :foo`
            inline_target = child.children[2]
            if inline_target.is_a?(Parser::AST::Node) && inline_target.type == :def
              result[modifier] << inline_target
            end
          end
        elsif child.type == :def
          result[current] << child
        end
      end

      result
    end

    # Returns direct `:send` nodes in the class body matching the given method name.
    # Does not descend into nested classes, modules, or method bodies.
    def class_body_sends(class_node, method_name)
      matches = []
      return matches unless class_node.is_a?(Parser::AST::Node)
      return matches unless %i[class module].include?(class_node.type)

      class_body_children(class_node).each do |child|
        next unless child.is_a?(Parser::AST::Node)
        next unless child.type == :send
        # Receiver-less send only (e.g., `has_many :foo`, not `MyMod.has_many :foo`)
        next unless child.children[0].nil?
        matches << child if child.children[1] == method_name
      end

      matches
    end

    private

    # The body of a `class` node is its third child; for `module`, the second.
    # The body may be a single node or a `:begin` containing a sequence of nodes.
    def class_body_children(class_or_module_node)
      body =
        case class_or_module_node.type
        when :class then class_or_module_node.children[2]
        when :module then class_or_module_node.children[1]
        end

      return [] if body.nil?
      return body.children if body.is_a?(Parser::AST::Node) && body.type == :begin
      [body]
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/ast_helpers_spec.rb`
Expected: PASS for all examples (including the previous ones from Task 2).

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: no new failures.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/ast_helpers.rb \
        spec/lib/rails_code_health/ast_helpers_spec.rb \
        spec/fixtures/code_samples/ruby/class_with_private_methods.rb \
        spec/fixtures/code_samples/ruby/class_with_inline_private.rb
git commit -m "feat: add visibility-aware helpers to ASTHelpers"
```

---

## Task 4: Add `erb_ruby_fragments` to ASTHelpers

**Files:**
- Modify: `lib/rails_code_health/ast_helpers.rb`
- Modify: `spec/lib/rails_code_health/ast_helpers_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/lib/rails_code_health/ast_helpers_spec.rb` inside the existing describe block:

```ruby
  describe '#erb_ruby_fragments' do
    it 'extracts code from <% %> and <%= %>' do
      source = "<p>Hello <%= name %></p>\n<% if signed_in? %>welcome<% end %>"
      fragments = dummy.erb_ruby_fragments(source).to_a
      expect(fragments).to contain_exactly(' name ', ' if signed_in? ', ' end ')
    end

    it 'handles multi-line tags' do
      source = "<% users.each do |u|\n  next if u.banned\n %><p><%= u.name %></p>"
      fragments = dummy.erb_ruby_fragments(source).to_a
      expect(fragments.first).to include("users.each do |u|")
      expect(fragments.first).to include("next if u.banned")
    end

    it 'returns no fragments for plain HTML' do
      source = "<p>Just text mentioning if and unless and case in prose.</p>"
      fragments = dummy.erb_ruby_fragments(source).to_a
      expect(fragments).to be_empty
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/ast_helpers_spec.rb -e erb_ruby_fragments`
Expected: FAIL — `NoMethodError: undefined method 'erb_ruby_fragments'`.

- [ ] **Step 3: Implement the helper**

Edit `lib/rails_code_health/ast_helpers.rb`. Add this public method (before the `private` keyword):

```ruby
    # Yields each Ruby code fragment inside <% %> / <%= %> / <%- %> tags.
    # Multi-line tags are handled. Returns an Enumerator if no block given.
    def erb_ruby_fragments(source)
      return enum_for(:erb_ruby_fragments, source) unless block_given?

      source.scan(/<%=?-?(.*?)-?%>/m) do |match|
        yield match[0]
      end
    end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bundle exec rspec spec/lib/rails_code_health/ast_helpers_spec.rb`
Expected: PASS for all examples.

- [ ] **Step 5: Commit**

```bash
git add lib/rails_code_health/ast_helpers.rb spec/lib/rails_code_health/ast_helpers_spec.rb
git commit -m "feat: add erb_ruby_fragments to ASTHelpers"
```

---

## Task 5: Fix `count_public_methods_in_class` (B1)

**Files:**
- Modify: `lib/rails_code_health/ruby_analyzer.rb`
- Create: `spec/lib/rails_code_health/ruby_analyzer_spec.rb` (if it doesn't already exist; check first)

- [ ] **Step 1: Check whether a ruby_analyzer_spec exists**

Run: `ls spec/lib/rails_code_health/ruby_analyzer_spec.rb 2>/dev/null || echo MISSING`
If MISSING, you'll create it in Step 2.

- [ ] **Step 2: Write the failing test**

Create or append to `spec/lib/rails_code_health/ruby_analyzer_spec.rb`:

```ruby
require 'spec_helper'

RSpec.describe RailsCodeHealth::RubyAnalyzer do
  describe 'public method counts' do
    it 'distinguishes public from private methods in classes' do
      fixture = RailsCodeHealthFixtures.path_for('ruby/class_with_private_methods.rb')
      result = described_class.new(fixture).analyze

      example_class = result[:class_metrics].find { |c| c[:name] == :Example }
      expect(example_class[:method_count]).to eq(6) # all defs
      expect(example_class[:public_method_count]).to eq(3) # pub_one, pub_two, pub_three
    end

    it 'handles inline private def' do
      fixture = RailsCodeHealthFixtures.path_for('ruby/class_with_inline_private.rb')
      result = described_class.new(fixture).analyze

      example_class = result[:class_metrics].find { |c| c[:name] == :Example }
      expect(example_class[:method_count]).to eq(3)
      expect(example_class[:public_method_count]).to eq(2)
    end
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/ruby_analyzer_spec.rb`
Expected: FAIL — `public_method_count` equals `method_count`.

- [ ] **Step 4: Update `RubyAnalyzer` to use ASTHelpers**

Edit `lib/rails_code_health/ruby_analyzer.rb`. At the top of `class RubyAnalyzer`, add:

```ruby
    include RailsCodeHealth::ASTHelpers
```

Replace the existing `count_public_methods_in_class` method (currently at line 247) with:

```ruby
    def count_public_methods_in_class(class_node)
      defs_by_visibility(class_node)[:public].size
    end
```

Delete the now-duplicated `find_nodes` method (currently at line 93) — it's provided by `ASTHelpers` now.

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/lib/rails_code_health/ruby_analyzer_spec.rb`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: no new failures. (Existing tests that asserted public_method_count == method_count for classes with private methods may now fail; if any do, that's an intended behavior change — note them and update in the next task.)

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/ruby_analyzer.rb spec/lib/rails_code_health/ruby_analyzer_spec.rb
git commit -m "fix: count public methods by visibility (B1)"
```

---

## Task 6: Fix `count_parameters` (B2)

**Files:**
- Modify: `lib/rails_code_health/ruby_analyzer.rb`
- Create: `spec/fixtures/code_samples/ruby/method_with_kwargs.rb`
- Modify: `spec/lib/rails_code_health/ruby_analyzer_spec.rb`

- [ ] **Step 1: Create the fixture**

`spec/fixtures/code_samples/ruby/method_with_kwargs.rb`:

```ruby
class Example
  def positional_only(a, b, c)
  end

  def with_kwargs(a, b:, c: 1)
  end

  def with_splat(*args, **opts, &block)
  end

  def empty_method
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/ruby_analyzer_spec.rb`:

```ruby
  describe 'parameter counts' do
    let(:methods) do
      fixture = RailsCodeHealthFixtures.path_for('ruby/method_with_kwargs.rb')
      result = described_class.new(fixture).analyze
      result[:method_metrics].each_with_object({}) { |m, h| h[m[:name]] = m }
    end

    it 'counts positional parameters' do
      expect(methods[:positional_only][:parameter_count]).to eq(3)
    end

    it 'counts required and optional keyword parameters' do
      expect(methods[:with_kwargs][:parameter_count]).to eq(3) # a, b:, c:
    end

    it 'counts splat, double-splat, and block as parameters' do
      expect(methods[:with_splat][:parameter_count]).to eq(3)
    end

    it 'returns 0 for empty argument list' do
      expect(methods[:empty_method][:parameter_count]).to eq(0)
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/ruby_analyzer_spec.rb -e "parameter counts"`
Expected: at least one example fails. (The current implementation counts `args_node.children`, which is usually correct but verify each case.)

- [ ] **Step 4: Tighten count_parameters**

Replace `count_parameters` in `lib/rails_code_health/ruby_analyzer.rb` (currently at line 252) with:

```ruby
    PARAM_TYPES = %i[arg optarg restarg kwarg kwoptarg kwrestarg blockarg].freeze

    def count_parameters(method_node)
      args_node = method_node.children[1]
      return 0 unless args_node.is_a?(Parser::AST::Node)

      args_node.children.count { |c| c.is_a?(Parser::AST::Node) && PARAM_TYPES.include?(c.type) }
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/ruby_analyzer_spec.rb -e "parameter counts"`
Expected: PASS for all four examples.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: no new failures.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/ruby_analyzer.rb \
        spec/fixtures/code_samples/ruby/method_with_kwargs.rb \
        spec/lib/rails_code_health/ruby_analyzer_spec.rb
git commit -m "fix: count only true parameter nodes in count_parameters (B2)"
```

---

## Task 7: Fix `calculate_max_nesting_depth` to ignore `:begin` (B3)

**Files:**
- Modify: `lib/rails_code_health/ruby_analyzer.rb`
- Create: `spec/fixtures/code_samples/ruby/method_with_begin_rescue.rb`
- Modify: `spec/lib/rails_code_health/ruby_analyzer_spec.rb`

- [ ] **Step 1: Create the fixture**

`spec/fixtures/code_samples/ruby/method_with_begin_rescue.rb`:

```ruby
class Example
  def shallow
    begin
      do_thing
    rescue StandardError
      log
    end
  end

  def deep
    if cond_a
      if cond_b
        if cond_c
          do_thing
        end
      end
    end
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/ruby_analyzer_spec.rb`:

```ruby
  describe 'nesting depth' do
    let(:methods) do
      fixture = RailsCodeHealthFixtures.path_for('ruby/method_with_begin_rescue.rb')
      result = described_class.new(fixture).analyze
      result[:method_metrics].each_with_object({}) { |m, h| h[m[:name]] = m }
    end

    it 'does not count :begin as a nesting level' do
      # A bare begin/rescue should not inflate depth — the method body itself
      # plus the rescue is depth 1 max, not 2 or 3.
      expect(methods[:shallow][:nesting_depth]).to be <= 1
    end

    it 'counts true control-flow nesting' do
      expect(methods[:deep][:nesting_depth]).to be >= 3
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/ruby_analyzer_spec.rb -e "nesting depth"`
Expected: the `shallow` example fails because `:begin` and `:block` are currently counted.

- [ ] **Step 4: Update `nesting_node?`**

Edit `lib/rails_code_health/ruby_analyzer.rb`. Replace `nesting_node?` (currently at line 309) with:

```ruby
    NESTING_TYPES = %i[if case while until for].freeze

    def nesting_node?(node)
      NESTING_TYPES.include?(node.type)
    end
```

(`:begin` is removed entirely — it's sequence grouping. `:block` is also removed; iteration blocks are counted via the cyclomatic complexity score, not nesting depth.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/lib/rails_code_health/ruby_analyzer_spec.rb -e "nesting depth"`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: existing nesting-depth tests may now produce lower numbers. If any existing test asserts a specific nesting_depth value that depended on counting `:begin`/`:block`, update it to match the new definition and note it.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/ruby_analyzer.rb \
        spec/fixtures/code_samples/ruby/method_with_begin_rescue.rb \
        spec/lib/rails_code_health/ruby_analyzer_spec.rb
git commit -m "fix: exclude :begin and :block from nesting depth calculation (B3)"
```

---

## Task 8: Move hard-coded thresholds into configuration (C1)

**Files:**
- Modify: `lib/rails_code_health/configuration.rb`
- Modify: `lib/rails_code_health/ruby_analyzer.rb`
- Modify: `spec/lib/rails_code_health/configuration_spec.rb`

- [ ] **Step 1: Write the failing test**

Append to `spec/lib/rails_code_health/configuration_spec.rb`:

```ruby
  describe 'smell detection thresholds' do
    let(:thresholds) { RailsCodeHealth::Configuration.new.thresholds }

    it 'exposes god_class line and method thresholds' do
      expect(thresholds.dig('smell_thresholds', 'god_class_lines')).to eq(400)
      expect(thresholds.dig('smell_thresholds', 'god_class_methods')).to eq(20)
    end

    it 'exposes high_complexity_method threshold' do
      expect(thresholds.dig('smell_thresholds', 'high_complexity_method')).to eq(15)
    end

    it 'exposes too_many_parameters threshold' do
      expect(thresholds.dig('smell_thresholds', 'too_many_parameters')).to eq(5)
    end

    it 'exposes nested_conditionals threshold' do
      expect(thresholds.dig('smell_thresholds', 'nested_conditionals')).to eq(4)
    end
  end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/configuration_spec.rb -e "smell detection thresholds"`
Expected: FAIL — `smell_thresholds` key missing.

- [ ] **Step 3: Add the new threshold group**

Edit `lib/rails_code_health/configuration.rb`. Inside `default_hardcoded_thresholds`, add a new top-level key (after `'service_thresholds'`):

```ruby
          'smell_thresholds' => {
            'god_class_lines' => 400,
            'god_class_methods' => 20,
            'high_complexity_method' => 15,
            'too_many_parameters' => 5,
            'nested_conditionals' => 4
          },
```

- [ ] **Step 4: Update `RubyAnalyzer` to read from configuration**

Edit `lib/rails_code_health/ruby_analyzer.rb`. Replace the four detectors:

`detect_god_classes` (currently line 167):

```ruby
    def detect_god_classes
      classes = []
      t = RailsCodeHealth.configuration.thresholds['smell_thresholds']
      find_nodes(@ast, :class) do |node|
        line_count = count_lines_in_node(node)
        method_count = count_methods_in_class(node)

        if line_count > t['god_class_lines'] && method_count > t['god_class_methods']
          classes << {
            type: :god_class,
            class_name: extract_class_name(node),
            line_count: line_count,
            method_count: method_count,
            severity: :high
          }
        end
      end
      classes
    end
```

`detect_high_complexity_methods` (currently line 186):

```ruby
    def detect_high_complexity_methods
      methods = []
      threshold = RailsCodeHealth.configuration.thresholds['smell_thresholds']['high_complexity_method']
      find_nodes(@ast, :def) do |node|
        complexity = calculate_cyclomatic_complexity(node)
        if complexity > threshold
          methods << {
            type: :high_complexity,
            method_name: node.children[0],
            complexity: complexity,
            severity: :high
          }
        end
      end
      methods
    end
```

`detect_too_many_parameters` (currently line 202):

```ruby
    def detect_too_many_parameters
      methods = []
      threshold = RailsCodeHealth.configuration.thresholds['smell_thresholds']['too_many_parameters']
      find_nodes(@ast, :def) do |node|
        param_count = count_parameters(node)
        if param_count > threshold
          methods << {
            type: :too_many_parameters,
            method_name: node.children[0],
            parameter_count: param_count,
            severity: :medium
          }
        end
      end
      methods
    end
```

`detect_nested_conditionals` (currently line 218):

```ruby
    def detect_nested_conditionals
      methods = []
      threshold = RailsCodeHealth.configuration.thresholds['smell_thresholds']['nested_conditionals']
      find_nodes(@ast, :def) do |node|
        max_depth = calculate_max_nesting_depth(node)
        if max_depth > threshold
          methods << {
            type: :nested_conditionals,
            method_name: node.children[0],
            nesting_depth: max_depth,
            severity: :medium
          }
        end
      end
      methods
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/configuration_spec.rb`
Expected: PASS.

Run: `bundle exec rspec`
Expected: no new failures.

- [ ] **Step 6: Commit**

```bash
git add lib/rails_code_health/configuration.rb lib/rails_code_health/ruby_analyzer.rb \
        spec/lib/rails_code_health/configuration_spec.rb
git commit -m "refactor: read smell detector thresholds from configuration (C1)"
```

---

## Task 9: Have `RailsAnalyzer` include `ASTHelpers` and delete its duplicated find_nodes (B4)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`

- [ ] **Step 1: Include the module and delete the duplicate**

Edit `lib/rails_code_health/rails_analyzer.rb`. Inside `class RailsAnalyzer`, near the top, add:

```ruby
    include RailsCodeHealth::ASTHelpers
```

Delete the existing `find_nodes` definition (currently at line 697) and the `private_controller_method?` helper (line 707) — we'll re-introduce a correctly-named helper in Task 10.

- [ ] **Step 2: Run the full suite**

Run: `bundle exec rspec`
Expected: anything that depended on `private_controller_method?` now fails. Note them; they'll be addressed in Task 10.

- [ ] **Step 3: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb
git commit -m "refactor: have RailsAnalyzer use shared ASTHelpers (B4)"
```

---

## Task 10: Fix controller action counting (A3)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/controllers/controller_with_private_helpers.rb`
- Create: `spec/fixtures/code_samples/controllers/thin_restful_controller.rb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/controllers/thin_restful_controller.rb`:

```ruby
class UsersController < ApplicationController
  def index
    @users = User.all
  end

  def show
    @user = User.find(params[:id])
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    if @user.save
      redirect_to @user
    else
      render :new
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    if @user.update(user_params)
      redirect_to @user
    else
      render :edit
    end
  end

  def destroy
    User.find(params[:id]).destroy
    redirect_to users_url
  end

  private

  def user_params
    params.require(:user).permit(:name, :email)
  end

  def authorize_user
    redirect_to root_path unless current_user.admin?
  end
end
```

`spec/fixtures/code_samples/controllers/controller_with_private_helpers.rb`:

```ruby
class ReportsController < ApplicationController
  before_action :load_report, only: [:show, :download]

  def index
    @reports = Report.all
  end

  def show
  end

  def download
    send_data @report.to_csv
  end

  private

  def load_report
    @report = Report.find(params[:id])
  end

  def report_params
    params.require(:report).permit(:title)
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'controller action counting (A3)' do
    it 'counts all seven canonical RESTful actions in a thin controller' do
      path = RailsCodeHealthFixtures.path_for('controllers/thin_restful_controller.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:action_count]).to eq(7)
    end

    it 'excludes private methods from the action count' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_private_helpers.rb')
      result = described_class.new(path, :controller).analyze
      # public: index, show, download = 3
      # private: load_report, report_params (should NOT count)
      expect(result[:action_count]).to eq(3)
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "controller action counting"`
Expected: FAIL — currently `private_controller_method?` excluded the wrong set.

- [ ] **Step 4: Rewrite `count_controller_actions`**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace `count_controller_actions` (currently at line 103) with:

```ruby
    def count_controller_actions
      return 0 unless @ast

      action_count = 0
      find_nodes(@ast, :class) do |class_node|
        defs_by_visibility(class_node)[:public].each do |def_node|
          name = def_node.children[0].to_s
          action_count += 1 unless name.start_with?('_')
        end
      end
      action_count
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "controller action counting"`
Expected: PASS for both examples.

- [ ] **Step 6: Run the full suite, expect breakage in old controller tests**

Run: `bundle exec rspec`
Expected: any existing test that asserted `action_count` based on the inverted logic will fail. Inspect each failure: if the new value is the *correct* count, update the assertion and note the change in the task body of Task 18 (CHANGELOG). Do NOT update tests blindly — read the fixture, confirm by hand what the right answer is, then update.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/controllers/thin_restful_controller.rb \
        spec/fixtures/code_samples/controllers/controller_with_private_helpers.rb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: count controller actions by visibility (A3)"
```

---

## Task 11: Fix `has_direct_model_access?` to inspect only action bodies (A1)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/controllers/controller_with_direct_model_in_action.rb`
- Create: `spec/fixtures/code_samples/controllers/controller_with_model_in_private_helper.rb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/controllers/controller_with_direct_model_in_action.rb`:

```ruby
class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
  end
end
```

`spec/fixtures/code_samples/controllers/controller_with_model_in_private_helper.rb`:

```ruby
class UsersController < ApplicationController
  def show
    @user = current_user_record
  end

  private

  def current_user_record
    # Acceptable: model access lives in a private helper, not in the action.
    User.find(session[:user_id])
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'has_direct_model_access? (A1)' do
    it 'flags model access inside a public action' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_direct_model_in_action.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:has_direct_model_access]).to be true
    end

    it 'does NOT flag model access only inside a private helper' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_model_in_private_helper.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:has_direct_model_access]).to be false
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "has_direct_model_access"`
Expected: the second example fails — the file-wide regex matches the helper too.

- [ ] **Step 4: Rewrite `has_direct_model_access?`**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace `has_direct_model_access?` (currently at line 125) with:

```ruby
    DIRECT_MODEL_METHODS = %i[find find_by where create create! update update! all first last destroy_all].freeze

    def has_direct_model_access?
      return false unless @ast

      found = false
      find_nodes(@ast, :class) do |class_node|
        defs_by_visibility(class_node)[:public].each do |def_node|
          find_nodes(def_node, :send) do |send_node|
            receiver = send_node.children[0]
            method_name = send_node.children[1]
            # Receiver must be a constant (a likely model class) and the method must be an AR method.
            next unless receiver.is_a?(Parser::AST::Node) && receiver.type == :const
            next unless DIRECT_MODEL_METHODS.include?(method_name)
            found = true
          end
        end
      end
      found
    end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "has_direct_model_access"`
Expected: PASS for both examples.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: existing tests for `has_direct_model_access` may behave differently. Audit each; update fixtures or assertions as needed.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/controllers/controller_with_direct_model_in_action.rb \
        spec/fixtures/code_samples/controllers/controller_with_model_in_private_helper.rb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: scope has_direct_model_access? to controller actions (A1)"
```

---

## Task 12: Fix `has_business_logic?` with stricter signals (A2)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/controllers/controller_with_business_logic.rb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

The new definition: a controller action contains "business logic" if any of these are true *inside a public def body*:

1. A loop containing a conditional (`each` block with an `if`/`unless`/`case` inside).
2. Arithmetic on local/instance vars (`+`, `-`, `*`, `/`, `%`) with two non-literal operands.
3. A call to a known business-y verb on a model receiver: `calculate`, `compute`, `process`, `charge`, `refund`, `transition`.
4. A `Model.transaction do` block.

Authorization checks (`if logged_in? && admin?`) and simple guard conditionals do not count.

- [ ] **Step 1: Create the fixture**

`spec/fixtures/code_samples/controllers/controller_with_business_logic.rb`:

```ruby
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)
    @order.calculate_total
    @order.charge!
    redirect_to @order
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'has_business_logic? (A2)' do
    it 'flags business-verb calls on model receivers' do
      path = RailsCodeHealthFixtures.path_for('controllers/controller_with_business_logic.rb')
      result = described_class.new(path, :controller).analyze
      expect(result[:has_business_logic]).to be true
    end

    it 'does NOT flag a controller that only does compound authorization checks' do
      # This used to trigger because the old regex matched `if x && y`.
      source = <<~RUBY
        class PostsController < ApplicationController
          def show
            if logged_in? && current_user.admin?
              @post = Post.find(params[:id])
            else
              redirect_to root_path
            end
          end
        end
      RUBY
      file = Tempfile.new(['ctrl', '.rb']).tap { |f| f.write(source); f.rewind }
      result = described_class.new(Pathname.new(file.path), :controller).analyze
      expect(result[:has_business_logic]).to be false
    ensure
      file&.close
    end

    it 'does NOT flag plain iteration without a conditional inside' do
      source = <<~RUBY
        class UsersController < ApplicationController
          def index
            @users = User.all
            @users.each { |u| u.touch }
          end
        end
      RUBY
      file = Tempfile.new(['ctrl', '.rb']).tap { |f| f.write(source); f.rewind }
      result = described_class.new(Pathname.new(file.path), :controller).analyze
      expect(result[:has_business_logic]).to be false
    ensure
      file&.close
    end
  end
```

(`Tempfile` is already required at the top of the existing spec file.)

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "has_business_logic"`
Expected: the second and third examples fail under the old regex.

- [ ] **Step 4: Rewrite `has_business_logic?`**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace `has_business_logic?` (currently at line 147) with:

```ruby
    BUSINESS_VERBS = %i[calculate compute process charge refund transition].freeze
    BUSINESS_VERB_PREFIXES = %w[calculate_ compute_ process_].freeze

    def has_business_logic?
      return false unless @ast

      found = false
      find_nodes(@ast, :class) do |class_node|
        defs_by_visibility(class_node)[:public].each do |def_node|
          found = true if action_has_business_logic?(def_node)
        end
      end
      found
    end

    def action_has_business_logic?(def_node)
      return true if business_verb_call?(def_node)
      return true if transaction_block?(def_node)
      return true if loop_with_conditional?(def_node)
      false
    end

    def business_verb_call?(def_node)
      found = false
      find_nodes(def_node, :send) do |send_node|
        method_name = send_node.children[1].to_s
        if BUSINESS_VERBS.include?(method_name.to_sym) ||
           BUSINESS_VERB_PREFIXES.any? { |p| method_name.start_with?(p) }
          found = true
        end
      end
      found
    end

    def transaction_block?(def_node)
      found = false
      find_nodes(def_node, :block) do |block_node|
        send_node = block_node.children[0]
        next unless send_node.is_a?(Parser::AST::Node) && send_node.type == :send
        found = true if send_node.children[1] == :transaction
      end
      found
    end

    def loop_with_conditional?(def_node)
      found = false
      find_nodes(def_node, :block) do |block_node|
        send_node = block_node.children[0]
        next unless send_node.is_a?(Parser::AST::Node) && send_node.type == :send
        next unless %i[each map select reject].include?(send_node.children[1])
        # Look for conditionals inside the block body.
        find_nodes(block_node.children[2], :if) { found = true }
        find_nodes(block_node.children[2], :case) { found = true }
      end
      found
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "has_business_logic"`
Expected: PASS for all three examples.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: existing `controller analysis > with business logic detection` tests in `rails_analyzer_spec.rb` need review. Several specifically assert the old too-loose behavior (e.g., the "detects iteration patterns" test that expects `has_business_logic` to be true for plain `.each do`). Audit each, and where the new behavior is correct, update the existing test's assertion or its fixture. List each updated test in the commit message and remember to add a CHANGELOG bullet in Task 18.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/controllers/controller_with_business_logic.rb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: detect business logic via stricter signals, not file-wide regex (A2)"
```

---

## Task 13: Fix model macro counts (A4)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/models/model_with_validations_in_comments.rb`
- Create: `spec/fixtures/code_samples/models/model_with_concerns_block.rb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/models/model_with_validations_in_comments.rb`:

```ruby
class Post < ApplicationRecord
  # validates :title, presence: true  -- commented out for now
  # validates :body
  belongs_to :user
  has_many :comments
  validates :title, presence: true
end
```

`spec/fixtures/code_samples/models/model_with_concerns_block.rb`:

```ruby
class Article < ApplicationRecord
  included do
    has_many :revisions
    validates :slug, presence: true
  end

  has_many :tags
  validates :title, presence: true
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'model macro counts (A4)' do
    it 'does not count commented-out macros' do
      path = RailsCodeHealthFixtures.path_for('models/model_with_validations_in_comments.rb')
      result = described_class.new(path, :model).analyze
      expect(result[:validation_count]).to eq(1)
      expect(result[:association_count]).to eq(2) # belongs_to :user, has_many :comments
    end

    it 'counts macros only at the class body level' do
      # `included do ... end` blocks live inside the class body but their contents
      # are inside a block, so we don't descend into them.
      path = RailsCodeHealthFixtures.path_for('models/model_with_concerns_block.rb')
      result = described_class.new(path, :model).analyze
      # Top-level: has_many :tags (1 association), validates :title (1 validation).
      # The `included do` content is NOT counted.
      expect(result[:association_count]).to eq(1)
      expect(result[:validation_count]).to eq(1)
    end
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "model macro counts"`
Expected: FAIL — regex counts commented and nested occurrences.

- [ ] **Step 4: Rewrite the four model count methods**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace these four (currently lines 196–231):

```ruby
    ASSOCIATION_MACROS = %i[belongs_to has_one has_many has_and_belongs_to_many].freeze
    VALIDATION_MACROS = %i[validates validates_presence_of validates_uniqueness_of validates_format_of validates_length_of validates_numericality_of validates_inclusion_of validates_exclusion_of validates_acceptance_of validates_confirmation_of].freeze
    CALLBACK_MACROS = %i[before_save after_save before_create after_create before_update after_update before_destroy after_destroy after_commit after_rollback before_validation after_validation].freeze

    def count_associations
      total = 0
      find_nodes(@ast, :class) do |class_node|
        ASSOCIATION_MACROS.each do |macro|
          total += class_body_sends(class_node, macro).size
        end
      end
      total
    end

    def count_validations
      total = 0
      find_nodes(@ast, :class) do |class_node|
        VALIDATION_MACROS.each do |macro|
          total += class_body_sends(class_node, macro).size
        end
      end
      total
    end

    def count_callbacks
      total = 0
      find_nodes(@ast, :class) do |class_node|
        CALLBACK_MACROS.each do |macro|
          total += class_body_sends(class_node, macro).size
        end
      end
      total
    end

    def count_scopes
      total = 0
      find_nodes(@ast, :class) do |class_node|
        total += class_body_sends(class_node, :scope).size
      end
      total
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "model macro counts"`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: existing tests for these counts should still pass since the old regex was lenient (more matches, not fewer) in many cases. Audit any failures.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/models/model_with_validations_in_comments.rb \
        spec/fixtures/code_samples/models/model_with_concerns_block.rb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: count model macros via AST at class body level (A4)"
```

---

## Task 14: Fix `has_fat_model_smell?` (A5)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/models/fat_model.rb`
- Create: `spec/fixtures/code_samples/models/thin_model.rb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/models/thin_model.rb`:

```ruby
class Tag < ApplicationRecord
  belongs_to :post
  validates :name, presence: true
end
```

`spec/fixtures/code_samples/models/fat_model.rb`:

```ruby
class User < ApplicationRecord
  # A deliberately fat model: 16+ public methods, >200 code lines.

  has_many :posts
  has_many :comments
  validates :email, presence: true

  def one; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def two; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def three; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def four; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def five; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def six; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def seven; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def eight; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def nine; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def ten; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def eleven; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def twelve; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def thirteen; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def fourteen; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def fifteen; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
  def sixteen; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; do_thing; end
end
```

If that's awkward (it is), make the file a more natural large file with one-line methods that puts it over the threshold; key requirement: it should have `> 200` code lines and `> 15` methods. Adjust as you write — the fixture is just an example, not load-bearing.

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'has_fat_model_smell? (A5)' do
    it 'does not flag a thin model' do
      path = RailsCodeHealthFixtures.path_for('models/thin_model.rb')
      result = described_class.new(path, :model).analyze
      expect(result[:has_fat_model_smell]).to be false
    end

    it 'flags a model that exceeds thresholds in class-scoped lines AND methods' do
      path = RailsCodeHealthFixtures.path_for('models/fat_model.rb')
      result = described_class.new(path, :model).analyze
      expect(result[:has_fat_model_smell]).to be true
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails or passes accordingly**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "has_fat_model_smell"`
Expected: behavior may already be close. Verify both examples produce the right answer; if one fails, proceed to Step 4.

- [ ] **Step 4: Rewrite `has_fat_model_smell?`**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace `has_fat_model_smell?` (currently at line 233) with:

```ruby
    def has_fat_model_smell?
      return false unless @ast

      class_node = nil
      find_nodes(@ast, :class) { |n| class_node ||= n }
      return false unless class_node

      code_lines = code_line_count(class_node)
      method_count = 0
      find_nodes_in_scope(class_node, :def) { method_count += 1 }

      code_lines > 200 && method_count > 15
    end

    def code_line_count(node)
      return 0 unless node.respond_to?(:loc) && node.loc.respond_to?(:expression)
      expr = node.loc.expression
      return 0 unless expr

      lines = expr.source.lines
      lines.count { |line| line.strip != '' && !line.strip.start_with?('#') }
    end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "has_fat_model_smell"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/models/fat_model.rb \
        spec/fixtures/code_samples/models/thin_model.rb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: fat model uses class-scoped code lines and method count (A5)"
```

---

## Task 15: Fix view logic line counting (A7)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/views/simple_view.html.erb`
- Create: `spec/fixtures/code_samples/views/view_with_logic.html.erb`
- Create: `spec/fixtures/code_samples/views/view_with_keyword_in_text.html.erb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/views/simple_view.html.erb`:

```erb
<h1>Hello, <%= @user.name %></h1>
<p>Welcome back.</p>
```

`spec/fixtures/code_samples/views/view_with_logic.html.erb`:

```erb
<% if signed_in? %>
  <p>Hello, <%= current_user.name %></p>
<% else %>
  <p>Please sign in.</p>
<% end %>

<% @posts.each do |post| %>
  <%= render post %>
<% end %>
```

`spec/fixtures/code_samples/views/view_with_keyword_in_text.html.erb`:

```erb
<h1>What if we choose otherwise?</h1>
<p>Some prose: unless you want to wait, you can leave. The case for X is strong.</p>
<p>For all intents and purposes, while reading, consider this.</p>
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'view logic counting (A7)' do
    it 'counts ERB tags containing control flow as logic lines' do
      path = RailsCodeHealthFixtures.path_for('views/view_with_logic.html.erb')
      result = described_class.new(path, :view).analyze
      # 4 tags contain control flow: if, else, end (twice in pairs), each ... + 2 ends
      # Acceptable to assert "> 0 and >= 4" rather than exact, since semantics
      # of "end" tags are debatable.
      expect(result[:logic_lines]).to be >= 4
    end

    it 'does NOT count plain HTML lines with keywords in prose' do
      path = RailsCodeHealthFixtures.path_for('views/view_with_keyword_in_text.html.erb')
      result = described_class.new(path, :view).analyze
      expect(result[:logic_lines]).to eq(0)
    end

    it 'returns zero logic for a plain view with only output ERB' do
      path = RailsCodeHealthFixtures.path_for('views/simple_view.html.erb')
      result = described_class.new(path, :view).analyze
      # `<%= @user.name %>` is output-only, no control flow.
      expect(result[:logic_lines]).to eq(0)
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "view logic counting"`
Expected: the "keyword in prose" example fails because the malformed regex matches plain HTML.

- [ ] **Step 4: Rewrite `count_view_logic_lines`**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace `count_view_logic_lines` (currently at line 274) with:

```ruby
    VIEW_CONTROL_FLOW_KEYWORDS = %w[if unless case for while end].freeze

    def count_view_logic_lines(_lines)
      count = 0
      erb_ruby_fragments(@source).each do |ruby|
        tokens = ruby.scan(/\b\w+\b/)
        count += 1 if (tokens & VIEW_CONTROL_FLOW_KEYWORDS).any?
      end
      count
    end
```

(Parameter `lines` is kept for signature stability — `analyze_view` passes it in. We don't use it.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "view logic counting"`
Expected: PASS for all three examples.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: existing view tests audited.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/views/simple_view.html.erb \
        spec/fixtures/code_samples/views/view_with_logic.html.erb \
        spec/fixtures/code_samples/views/view_with_keyword_in_text.html.erb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: parse ERB fragments to count view logic lines (A7)"
```

---

## Task 16: Fix migration `has_data_changes?` (A6)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/migrations/schema_only_migration.rb`
- Create: `spec/fixtures/code_samples/migrations/migration_with_find_each.rb`
- Create: `spec/fixtures/code_samples/migrations/migration_with_raw_sql.rb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/migrations/schema_only_migration.rb`:

```ruby
class AddEmailToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :email, :string
    add_index :users, :email, unique: true
  end
end
```

`spec/fixtures/code_samples/migrations/migration_with_find_each.rb`:

```ruby
class BackfillUserEmails < ActiveRecord::Migration[7.0]
  def up
    User.find_each do |user|
      user.update_columns(email: "#{user.username}@example.com")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
```

`spec/fixtures/code_samples/migrations/migration_with_raw_sql.rb`:

```ruby
class FixUserEmails < ActiveRecord::Migration[7.0]
  def up
    ActiveRecord::Base.connection.execute("UPDATE users SET email = LOWER(email)")
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'migration data changes (A6)' do
    it 'does not flag a schema-only migration' do
      path = RailsCodeHealthFixtures.path_for('migrations/schema_only_migration.rb')
      result = described_class.new(path, :migration).analyze
      expect(result[:has_data_changes]).to be false
    end

    it 'flags a migration that uses find_each + update_columns' do
      path = RailsCodeHealthFixtures.path_for('migrations/migration_with_find_each.rb')
      result = described_class.new(path, :migration).analyze
      expect(result[:has_data_changes]).to be true
    end

    it 'flags a migration that runs raw SQL via connection.execute' do
      path = RailsCodeHealthFixtures.path_for('migrations/migration_with_raw_sql.rb')
      result = described_class.new(path, :migration).analyze
      expect(result[:has_data_changes]).to be true
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "migration data changes"`
Expected: the `find_each` example fails — the current implementation doesn't recognize it.

- [ ] **Step 4: Rewrite `has_data_changes?`**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace `has_data_changes?` (currently at line 354) with:

```ruby
    DATA_CHANGE_METHODS = %i[
      execute update_all delete_all
      find_each update update_columns update_column
      update! save save!
    ].freeze

    def has_data_changes?
      return false unless @ast

      found = false
      find_nodes(@ast, :send) do |send_node|
        method_name = send_node.children[1]
        found = true if DATA_CHANGE_METHODS.include?(method_name)
      end
      found
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "migration data changes"`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: existing migration tests audited.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/migrations/schema_only_migration.rb \
        spec/fixtures/code_samples/migrations/migration_with_find_each.rb \
        spec/fixtures/code_samples/migrations/migration_with_raw_sql.rb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: broaden has_data_changes? to find_each, update_columns, raw SQL (A6)"
```

---

## Task 17: Fix service dependency word-boundary bug (A8)

**Files:**
- Modify: `lib/rails_code_health/rails_analyzer.rb`
- Create: `spec/fixtures/code_samples/services/plain_service.rb`
- Create: `spec/fixtures/code_samples/services/service_with_profile_model.rb`
- Modify: `spec/lib/rails_code_health/rails_analyzer_spec.rb`

- [ ] **Step 1: Create the fixtures**

`spec/fixtures/code_samples/services/plain_service.rb`:

```ruby
class PlainService
  def call
    do_thing
  end
end
```

`spec/fixtures/code_samples/services/service_with_profile_model.rb`:

```ruby
class ProfileFetcher
  # Uses ActiveRecord on the Profile model. Must NOT be flagged as file-system.
  def call
    Profile.find_by(slug: "x")
  end
end
```

- [ ] **Step 2: Write the failing test**

Append to `spec/lib/rails_code_health/rails_analyzer_spec.rb`:

```ruby
  describe 'service dependency detection (A8)' do
    it 'returns no dependencies for a trivial service' do
      path = RailsCodeHealthFixtures.path_for('services/plain_service.rb')
      result = described_class.new(path, :service).analyze
      expect(result[:dependencies]).to eq([])
    end

    it 'does NOT mistake Profile. for File.' do
      path = RailsCodeHealthFixtures.path_for('services/service_with_profile_model.rb')
      result = described_class.new(path, :service).analyze
      expect(result[:dependencies]).to include(:active_record)
      expect(result[:dependencies]).not_to include(:file_system)
    end
  end
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "service dependency detection"`
Expected: the Profile example fails — `'Profile.'` matches the `'File.'` substring check.

- [ ] **Step 4: Rewrite `detect_service_dependencies`**

Edit `lib/rails_code_health/rails_analyzer.rb`. Replace `detect_service_dependencies` (currently at line 434) with:

```ruby
    def detect_service_dependencies
      deps = []

      if @source.match?(/\b(?:[A-Z]\w*)\.(?:find|find_by|where|create|create!|update|update!|all|first|last)\b/)
        deps << :active_record
      end

      if @source.match?(/\b(?:Net::HTTP|HTTParty|Faraday|RestClient|Typhoeus)\b/)
        deps << :external_api
      end

      if @source.match?(/\b(?:File|Dir|FileUtils|Pathname)\.\w+/)
        deps << :file_system
      end

      if @source.match?(/\b(?:Mailer|ActionMailer)\b/) || @source.match?(/\.deliver(?:_now|_later)?\b/)
        deps << :email
      end

      if @source.match?(/\bRails\.cache\b/) || @source.match?(/\bRedis\b/) || @source.match?(/\bcache_store\b/)
        deps << :cache
      end

      deps.uniq
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec rspec spec/lib/rails_code_health/rails_analyzer_spec.rb -e "service dependency detection"`
Expected: PASS.

- [ ] **Step 6: Run the full suite**

Run: `bundle exec rspec`
Expected: existing service tests that depended on the old over-eager matching may need updates. Audit and adjust.

- [ ] **Step 7: Commit**

```bash
git add lib/rails_code_health/rails_analyzer.rb \
        spec/fixtures/code_samples/services/plain_service.rb \
        spec/fixtures/code_samples/services/service_with_profile_model.rb \
        spec/lib/rails_code_health/rails_analyzer_spec.rb
git commit -m "fix: word-boundary checks in service dependency detection (A8)"
```

---

## Task 18: Release prep — version bump, CHANGELOG, README note

**Files:**
- Modify: `lib/rails_code_health/version.rb`
- Modify: `CHANGELOG.md`
- Modify: `README.md`

- [ ] **Step 1: Bump version**

Edit `lib/rails_code_health/version.rb`:

```ruby
module RailsCodeHealth
  VERSION = "0.3.0"
end
```

- [ ] **Step 2: Update CHANGELOG**

Edit `CHANGELOG.md`. Under `## [Unreleased]`, add a new `## [0.3.0] - 2026-05-12` section:

```markdown
## [0.3.0] - 2026-05-12

### Added
- `RailsCodeHealth::ASTHelpers` module: shared AST traversal with scoped variants and visibility-aware def collection.
- Fixture-based RSpec test suite under `spec/fixtures/code_samples/`.
- New configuration group `smell_thresholds` for previously hard-coded values.

### Fixed
- `RubyAnalyzer#count_public_methods_in_class` now actually distinguishes public from private methods (including inline `private def foo`).
- `RubyAnalyzer#count_parameters` now counts only true parameter nodes.
- `RubyAnalyzer` nesting depth calculation no longer counts `:begin` and `:block` as nesting levels.
- `RailsAnalyzer#count_controller_actions` no longer inverts public/private; the seven canonical RESTful actions are correctly counted, and private helpers are excluded.
- `RailsAnalyzer#has_direct_model_access?` only fires when model calls appear inside public controller actions.
- `RailsAnalyzer#has_business_logic?` uses stricter signals (business-verb calls on model receivers, transactions, loops with conditionals) instead of matching any compound `if` or any `.each do`.
- Model `count_associations`, `count_validations`, `count_callbacks`, `count_scopes` count only top-level class body macros — no comments, strings, or nested-class matches.
- `has_fat_model_smell?` uses class-scoped code-line count and class-scoped method count.
- View `count_view_logic_lines` parses ERB fragments and no longer flags plain HTML that happens to contain `if`, `unless`, etc., in text.
- Migration `has_data_changes?` recognizes `find_each`, `update`, `update_columns`, raw `connection.execute`, and other data-mutation methods.
- Service `detect_service_dependencies` uses word boundaries — `Profile.` no longer matches the `File.` check.
- God class, high complexity, parameter, and nesting smell thresholds are now read from configuration instead of inlined.

### Changed (may affect scores)
- Score changes are expected on any project where the above false positives or false negatives applied. Re-baseline before comparing to v0.2.0 reports.
```

Also update the link footer at the bottom:

```markdown
[Unreleased]: https://github.com/gkosmo/rails_code_health/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/gkosmo/rails_code_health/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gkosmo/rails_code_health/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gkosmo/rails_code_health/releases/tag/v0.1.0
```

- [ ] **Step 3: Add note to README**

Edit `README.md`. After the "## Health Score Calculation" section, before "## Configuration", insert:

```markdown
> **Note on v0.3.0 scores:** v0.3.0 fixes several false positives and false negatives in the Rails-specific checks. Scores on the same codebase will move compared to v0.2.0. See the CHANGELOG for the list of changed checks.
```

- [ ] **Step 4: Run the full suite**

Run: `bundle exec rspec`
Expected: all examples pass.

- [ ] **Step 5: Commit**

```bash
git add lib/rails_code_health/version.rb CHANGELOG.md README.md
git commit -m "chore: release v0.3.0 — trustworthy Rails checks"
```

- [ ] **Step 6: Tag (do NOT push)**

Tagging is the user's call. Do not push or publish; only run:

```bash
git tag v0.3.0
git log --oneline -10
```

Confirm the v0.3.0 tag is in place. Stop here — the user will push, publish to RubyGems, and write the release notes.

---

## Final verification checklist

- [ ] `bundle exec rspec` — all examples pass.
- [ ] No file in `lib/rails_code_health/` has a duplicate `find_nodes` definition.
- [ ] `lib/rails_code_health/ast_helpers.rb` exists and is required from `lib/rails_code_health.rb`.
- [ ] Every changed Rails-analyzer method has at least one positive and one negative fixture-backed test.
- [ ] `CHANGELOG.md` v0.3.0 section lists every changed check.
- [ ] `lib/rails_code_health/version.rb` reads `"0.3.0"`.
- [ ] `git tag v0.3.0` exists locally; nothing has been pushed.

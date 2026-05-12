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

    it 'yields scope-boundary children that match the target type' do
      # nested_class.rb defines Outer with a nested Inner class.
      # Searching for :class nodes inside the outer class should find Inner
      # (it IS a scope boundary, but it matches the target type and is at
      # this scope's level). It should be yielded, but not descended into.
      source = File.read(RailsCodeHealthFixtures.path_for('ruby/nested_class.rb'))
      outer_class = Parser::CurrentRuby.parse(source)

      class_names = []
      dummy.find_nodes_in_scope(outer_class, :class) do |class_node|
        # Extract the class name. For a :class node, children[0] is a :const node
        # whose last child is the class name symbol.
        const_node = class_node.children[0]
        class_names << const_node.children.last
      end

      # The starting node IS the outer class — find_nodes_in_scope yields the
      # node itself if it matches the type (top of method). So we expect Outer
      # AND Inner: both classes are in scope, but we don't descend into Inner.
      expect(class_names).to contain_exactly(:Outer, :Inner)
    end
  end

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

    it 'excludes defs inside class << self' do
      source = <<~RUBY
        class Foo
          class << self
            def class_method; end
          end
          def instance_method; end
        end
      RUBY
      node = Parser::CurrentRuby.parse(source)
      result = dummy.defs_by_visibility(node)
      expect(result[:public].map { |n| n.children[0] }).to contain_exactly(:instance_method)
      expect(result[:private]).to eq([])
      expect(result[:protected]).to eq([])
    end

    it 'works on a module node' do
      node = Parser::CurrentRuby.parse("module M; def a; end; private; def b; end; end")
      result = dummy.defs_by_visibility(node)
      expect(result[:public].map { |n| n.children[0] }).to eq([:a])
      expect(result[:private].map { |n| n.children[0] }).to eq([:b])
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
end

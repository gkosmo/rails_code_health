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
end

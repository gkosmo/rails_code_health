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
    # nodes. The starting node itself is inspected; all children are inspected, but
    # nested scope-introducing constructs are not recursed into.
    def find_nodes_in_scope(node, type, &block)
      return unless node.is_a?(Parser::AST::Node)

      yield(node) if node.type == type

      node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)

        # Scope-boundary children get yielded if they match the target type,
        # but we do not recurse into them.
        if SCOPE_BOUNDARY_TYPES.include?(child.type)
          yield(child) if child.type == type
          next
        end

        find_nodes_in_scope(child, type, &block)
      end
    end
  end
end

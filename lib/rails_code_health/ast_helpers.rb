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

        # If the child is a scope boundary AND is not the starting node itself,
        # yield it if it matches the target type but do not recurse into it.
        if SCOPE_BOUNDARY_TYPES.include?(child.type) && child != node
          yield(child) if child.type == type
          next
        end

        find_nodes_in_scope(child, type, &block)
      end
    end
  end
end

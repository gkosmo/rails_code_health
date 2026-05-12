module RailsCodeHealth
  module ASTHelpers
    SCOPE_BOUNDARY_TYPES = %i[class module def defs sclass].freeze
    VISIBILITY_MODIFIERS = %i[public private protected].freeze

    # Yields every descendant (and the node itself) of the given type.
    # Descends into all children.
    def find_nodes(node, type, &block)
      return unless node.is_a?(Parser::AST::Node)

      yield(node) if node.type == type
      node.children.each { |child| find_nodes(child, type, &block) }
    end

    # Returns a hash { public: [def_nodes], private: [def_nodes], protected: [def_nodes] }
    # for the given class node. Handles bare modifier blocks and inline `private def foo`.
    # Defs inside `class << self` are excluded (the :sclass node is not descended into).
    #
    # NOTE: `private :symbol_name` / `private :a, :b` forms are NOT handled —
    # methods so marked stay classified as :public. Only bare modifier blocks
    # (`private` on its own line) and inline `private def foo` are recognized.
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
    #
    # NOTE: calls wrapped in a block (e.g., `included do ... end` in concerns)
    # are NOT matched — the wrapping :block node is not a :send. Use
    # class_body_children directly and inspect :block nodes if you need to find
    # macro calls inside such wrappers.
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
  end
end

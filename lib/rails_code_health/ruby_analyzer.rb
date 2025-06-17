module RailsCodeHealth
  class RubyAnalyzer
    def initialize(file_path)
      @file_path = file_path
      @source = File.read(file_path)
      @ast = Parser::CurrentRuby.parse(@source)
    rescue Parser::SyntaxError => e
      @parse_error = e
      @ast = nil
    end

    def analyze
      return { parse_error: @parse_error.message } if @parse_error

      {
        file_metrics: analyze_file,
        class_metrics: analyze_classes,
        method_metrics: analyze_methods,
        complexity_metrics: analyze_complexity,
        code_smells: detect_code_smells
      }
    end

    private

    def analyze_file
      lines = @source.lines
      {
        total_lines: lines.count,
        code_lines: lines.reject { |line| line.strip.empty? || line.strip.start_with?('#') }.count,
        comment_lines: lines.count { |line| line.strip.start_with?('#') },
        blank_lines: lines.count { |line| line.strip.empty? }
      }
    end

    def analyze_classes
      return [] unless @ast

      classes = []
      find_nodes(@ast, :class) do |node|
        classes << {
          name: extract_class_name(node),
          line_count: count_lines_in_node(node),
          method_count: count_methods_in_class(node),
          public_method_count: count_public_methods_in_class(node),
          inheritance: extract_inheritance(node),
          complexity_score: calculate_class_complexity(node)
        }
      end
      classes
    end

    def analyze_methods
      return [] unless @ast

      methods = []
      find_nodes(@ast, :def) do |node|
        methods << {
          name: node.children[0],
          line_count: count_lines_in_node(node),
          parameter_count: count_parameters(node),
          cyclomatic_complexity: calculate_cyclomatic_complexity(node),
          nesting_depth: calculate_max_nesting_depth(node),
          abc_score: calculate_abc_score(node),
          has_rescue: has_rescue_block?(node)
        }
      end
      methods
    end

    def analyze_complexity
      return {} unless @ast

      {
        overall_complexity: calculate_overall_complexity,
        max_nesting_depth: find_max_nesting_depth(@ast),
        conditional_complexity: count_conditionals(@ast),
        loop_complexity: count_loops(@ast)
      }
    end

    def detect_code_smells
      smells = []
      smells.concat(detect_long_methods)
      smells.concat(detect_god_classes)
      smells.concat(detect_high_complexity_methods)
      smells.concat(detect_too_many_parameters)
      smells.concat(detect_nested_conditionals)
      smells
    end

    # AST traversal helper
    def find_nodes(node, type, &block)
      return unless node.is_a?(Parser::AST::Node)

      yield(node) if node.type == type

      node.children.each do |child|
        find_nodes(child, type, &block)
      end
    end

    # Complexity calculations
    def calculate_cyclomatic_complexity(node)
      complexity = 1 # Base complexity
      
      find_nodes(node, :if) { complexity += 1 }
      find_nodes(node, :case) { complexity += 1 }
      find_nodes(node, :while) { complexity += 1 }
      find_nodes(node, :until) { complexity += 1 }
      find_nodes(node, :for) { complexity += 1 }
      find_nodes(node, :rescue) { complexity += 1 }
      find_nodes(node, :when) { complexity += 1 }
      
      complexity
    end

    def calculate_max_nesting_depth(node, depth = 0)
      return depth unless node.is_a?(Parser::AST::Node)

      max_depth = depth
      
      if nesting_node?(node)
        depth += 1
        max_depth = depth
      end

      node.children.each do |child|
        child_depth = calculate_max_nesting_depth(child, depth)
        max_depth = [max_depth, child_depth].max
      end

      max_depth
    end

    def calculate_abc_score(node)
      assignments = 0
      branches = 0
      conditions = 0

      find_nodes(node, :lvasgn) { assignments += 1 }
      find_nodes(node, :ivasgn) { assignments += 1 }
      find_nodes(node, :send) { branches += 1 }
      find_nodes(node, :if) { conditions += 1 }
      find_nodes(node, :case) { conditions += 1 }

      Math.sqrt(assignments**2 + branches**2 + conditions**2).round(2)
    end

    # Code smell detection
    def detect_long_methods
      methods = []
      find_nodes(@ast, :def) do |node|
        line_count = count_lines_in_node(node)
        if line_count > RailsCodeHealth.configuration.thresholds['ruby_thresholds']['method_length']['red']
          methods << {
            type: :long_method,
            method_name: node.children[0],
            line_count: line_count,
            severity: :high
          }
        end
      end
      methods
    end

    def detect_god_classes
      classes = []
      find_nodes(@ast, :class) do |node|
        line_count = count_lines_in_node(node)
        method_count = count_methods_in_class(node)
        
        if line_count > 400 && method_count > 20
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

    def detect_high_complexity_methods
      methods = []
      find_nodes(@ast, :def) do |node|
        complexity = calculate_cyclomatic_complexity(node)
        if complexity > 15
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

    def detect_too_many_parameters
      methods = []
      find_nodes(@ast, :def) do |node|
        param_count = count_parameters(node)
        if param_count > 5
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

    def detect_nested_conditionals
      methods = []
      find_nodes(@ast, :def) do |node|
        max_depth = calculate_max_nesting_depth(node)
        if max_depth > 4
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

    # Helper methods
    def count_lines_in_node(node)
      return 0 unless node.respond_to?(:loc) && node.loc.respond_to?(:last_line)
      
      node.loc.last_line - node.loc.first_line + 1
    end

    def count_methods_in_class(class_node)
      method_count = 0
      find_nodes(class_node, :def) { method_count += 1 }
      method_count
    end

    def count_public_methods_in_class(class_node)
      # This is a simplified version - in reality, you'd need to track visibility modifiers
      count_methods_in_class(class_node)
    end

    def count_parameters(method_node)
      args_node = method_node.children[1]
      return 0 unless args_node
      
      args_node.children.count
    end

    def extract_class_name(class_node)
      class_node.children[0]&.children&.last || 'Unknown'
    end

    def extract_inheritance(class_node)
      superclass_node = class_node.children[1]
      return nil unless superclass_node
      
      if superclass_node.type == :const
        superclass_node.children.last
      else
        'Unknown'
      end
    end

    def calculate_class_complexity(class_node)
      total_complexity = 0
      find_nodes(class_node, :def) do |method_node|
        total_complexity += calculate_cyclomatic_complexity(method_node)
      end
      total_complexity
    end

    def calculate_overall_complexity
      total = 0
      find_nodes(@ast, :def) do |node|
        total += calculate_cyclomatic_complexity(node)
      end
      total
    end

    def find_max_nesting_depth(node)
      calculate_max_nesting_depth(node)
    end

    def count_conditionals(node)
      count = 0
      find_nodes(node, :if) { count += 1 }
      find_nodes(node, :case) { count += 1 }
      count
    end

    def count_loops(node)
      count = 0
      find_nodes(node, :while) { count += 1 }
      find_nodes(node, :until) { count += 1 }
      find_nodes(node, :for) { count += 1 }
      count
    end

    def nesting_node?(node)
      [:if, :case, :while, :until, :for, :begin, :block].include?(node.type)
    end

    def has_rescue_block?(node)
      has_rescue = false
      find_nodes(node, :rescue) { has_rescue = true }
      has_rescue
    end
  end
end
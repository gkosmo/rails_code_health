module RailsCodeHealth
  class RailsAnalyzer
    def initialize(file_path, file_type)
      @file_path = file_path
      @file_type = file_type
      @source = File.read(file_path)
      @ast = Parser::CurrentRuby.parse(@source) if file_path.extname == '.rb'
    rescue Parser::SyntaxError
      @ast = nil
    end

    def analyze
      case @file_type
      when :controller
        analyze_controller
      when :model
        analyze_model
      when :view
        analyze_view
      when :helper
        analyze_helper
      when :migration
        analyze_migration
      else
        {}
      end
    end

    private

    def analyze_controller
      return {} unless @ast

      {
        rails_type: :controller,
        action_count: count_controller_actions,
        has_before_actions: has_before_actions?,
        uses_strong_parameters: uses_strong_parameters?,
        has_direct_model_access: has_direct_model_access?,
        response_formats: detect_response_formats,
        rails_smells: detect_controller_smells
      }
    end

    def analyze_model
      return {} unless @ast

      {
        rails_type: :model,
        association_count: count_associations,
        validation_count: count_validations,
        callback_count: count_callbacks,
        scope_count: count_scopes,
        has_fat_model_smell: has_fat_model_smell?,
        rails_smells: detect_model_smells
      }
    end

    def analyze_view
      lines = @source.lines
      logic_lines = count_view_logic_lines(lines)
      
      {
        rails_type: :view,
        total_lines: lines.count,
        logic_lines: logic_lines,
        has_inline_styles: has_inline_styles?,
        has_inline_javascript: has_inline_javascript?,
        rails_smells: detect_view_smells(lines, logic_lines)
      }
    end

    def analyze_helper
      return {} unless @ast

      {
        rails_type: :helper,
        method_count: count_helper_methods,
        rails_smells: detect_helper_smells
      }
    end

    def analyze_migration
      return {} unless @ast

      {
        rails_type: :migration,
        has_data_changes: has_data_changes?,
        has_index_changes: has_index_changes?,
        complexity_score: calculate_migration_complexity,
        rails_smells: detect_migration_smells
      }
    end

    # Controller analysis methods
    def count_controller_actions
      return 0 unless @ast

      action_count = 0
      find_nodes(@ast, :def) do |node|
        method_name = node.children[0].to_s
        # Skip private methods and Rails internal methods
        unless method_name.start_with?('_') || private_controller_method?(method_name)
          action_count += 1
        end
      end
      action_count
    end

    def has_before_actions?
      @source.include?('before_action') || @source.include?('before_filter')
    end

    def uses_strong_parameters?
      @source.include?('params.require') || @source.include?('params.permit')
    end

    def has_direct_model_access?
      # Look for direct ActiveRecord calls in controller actions
      model_patterns = [
        /\w+\.find\(/,
        /\w+\.where\(/,
        /\w+\.create\(/,
        /\w+\.update\(/,
        /\w+\.all/
      ]
      
      model_patterns.any? { |pattern| @source.match?(pattern) }
    end

    def detect_response_formats
      formats = []
      formats << :html if @source.include?('format.html')
      formats << :json if @source.include?('format.json')
      formats << :xml if @source.include?('format.xml')
      formats << :js if @source.include?('format.js')
      formats
    end

    def detect_controller_smells
      smells = []
      
      action_count = count_controller_actions
      if action_count > 10
        smells << {
          type: :too_many_actions,
          count: action_count,
          severity: :high
        }
      end

      unless uses_strong_parameters?
        smells << {
          type: :missing_strong_parameters,
          severity: :medium
        }
      end

      if has_direct_model_access?
        smells << {
          type: :direct_model_access,
          severity: :medium
        }
      end

      smells
    end

    # Model analysis methods
    def count_associations
      associations = 0
      association_methods = %w[belongs_to has_one has_many has_and_belongs_to_many]
      
      association_methods.each do |method|
        associations += @source.scan(/#{method}\s+:/).count
      end
      
      associations
    end

    def count_validations
      validations = 0
      validation_methods = %w[validates validates_presence_of validates_uniqueness_of validates_format_of]
      
      validation_methods.each do |method|
        validations += @source.scan(/#{method}\s+/).count
      end
      
      validations
    end

    def count_callbacks
      callbacks = 0
      callback_methods = %w[before_save after_save before_create after_create before_update after_update before_destroy after_destroy]
      
      callback_methods.each do |method|
        callbacks += @source.scan(/#{method}\s+/).count
      end
      
      callbacks
    end

    def count_scopes
      @source.scan(/scope\s+:/).count
    end

    def has_fat_model_smell?
      return false unless @ast

      line_count = @source.lines.count
      method_count = 0
      find_nodes(@ast, :def) { method_count += 1 }
      
      line_count > 200 && method_count > 15
    end

    def detect_model_smells
      smells = []
      
      if has_fat_model_smell?
        smells << {
          type: :fat_model,
          severity: :high
        }
      end

      callback_count = count_callbacks
      if callback_count > 5
        smells << {
          type: :callback_hell,
          count: callback_count,
          severity: :medium
        }
      end

      validation_count = count_validations
      if validation_count == 0
        smells << {
          type: :missing_validations,
          severity: :low
        }
      end

      smells
    end

    # View analysis methods
    def count_view_logic_lines(lines)
      logic_count = 0
      
      lines.each do |line|
        # Count Ruby code blocks in ERB
        logic_count += 1 if line.match?(/<%((?!%>).)*%>/) || line.match?(/<%((?!%>).)*if|unless|case|for|while/)
      end
      
      logic_count
    end

    def has_inline_styles?
      @source.include?('style=') || @source.include?('<style>')
    end

    def has_inline_javascript?
      @source.include?('<script>') || @source.include?('onclick=') || @source.include?('onload=')
    end

    def detect_view_smells(lines, logic_lines)
      smells = []
      
      if lines.count > 50
        smells << {
          type: :long_view,
          line_count: lines.count,
          severity: :medium
        }
      end

      if logic_lines > 10
        smells << {
          type: :logic_in_view,
          logic_lines: logic_lines,
          severity: :high
        }
      end

      if has_inline_styles?
        smells << {
          type: :inline_styles,
          severity: :low
        }
      end

      if has_inline_javascript?
        smells << {
          type: :inline_javascript,
          severity: :medium
        }
      end

      smells
    end

    # Helper analysis methods
    def count_helper_methods
      return 0 unless @ast

      method_count = 0
      find_nodes(@ast, :def) { method_count += 1 }
      method_count
    end

    def detect_helper_smells
      smells = []
      
      method_count = count_helper_methods
      if method_count > 15
        smells << {
          type: :fat_helper,
          method_count: method_count,
          severity: :medium
        }
      end

      smells
    end

    # Migration analysis methods
    def has_data_changes?
      data_methods = %w[execute update_all delete_all]
      data_methods.any? { |method| @source.include?(method) }
    end

    def has_index_changes?
      @source.include?('add_index') || @source.include?('remove_index')
    end

    def calculate_migration_complexity
      complexity = 0
      
      # Count different types of operations
      complexity += @source.scan(/create_table/).count * 2
      complexity += @source.scan(/drop_table/).count * 2
      complexity += @source.scan(/add_column/).count * 1
      complexity += @source.scan(/remove_column/).count * 1
      complexity += @source.scan(/change_column/).count * 2
      complexity += @source.scan(/add_index/).count * 1
      complexity += @source.scan(/remove_index/).count * 1
      complexity += @source.scan(/execute/).count * 3
      
      complexity
    end

    def detect_migration_smells
      smells = []
      
      if has_data_changes?
        smells << {
          type: :data_changes_in_migration,
          severity: :high
        }
      end

      complexity = calculate_migration_complexity
      if complexity > 20
        smells << {
          type: :complex_migration,
          complexity: complexity,
          severity: :medium
        }
      end

      smells
    end

    # Helper methods
    def find_nodes(node, type, &block)
      return unless node.is_a?(Parser::AST::Node)

      yield(node) if node.type == type

      node.children.each do |child|
        find_nodes(child, type, &block)
      end
    end

    def private_controller_method?(method_name)
      %w[show new edit create update destroy].include?(method_name) ||
        method_name.end_with?('_params')
    end
  end
end
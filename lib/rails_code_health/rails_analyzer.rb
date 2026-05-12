module RailsCodeHealth
  class RailsAnalyzer
    include RailsCodeHealth::ASTHelpers

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
      when :service
        analyze_service
      when :interactor
        analyze_interactor
      when :serializer
        analyze_serializer
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
        has_business_logic: has_business_logic?,
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
      find_nodes(@ast, :class) do |class_node|
        defs_by_visibility(class_node)[:public].each do |def_node|
          name = def_node.children[0].to_s
          action_count += 1 unless name.start_with?('_')
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

    def detect_response_formats
      formats = []
      formats << :html if @source.include?('format.html')
      formats << :json if @source.include?('format.json')
      formats << :xml if @source.include?('format.xml')
      formats << :js if @source.include?('format.js')
      formats
    end

    BUSINESS_VERBS = %i[calculate compute process charge refund transition].freeze
    # Methods with these prefixes likely indicate business logic.
    # `process_` was previously included but removed because of false positives
    # on common AR attributes like `process_id`.
    BUSINESS_VERB_PREFIXES = %w[calculate_ compute_].freeze

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

      if has_business_logic?
        smells << {
          type: :business_logic_in_controller,
          severity: :high
        }
      end

      smells
    end

    def action_has_business_logic?(def_node)
      # NOTE: arithmetic signal (plan A2 item 2) intentionally not implemented —
      # accuracy of detecting "two non-literal operands" was deemed not worth
      # the false positive risk in v0.3.0.
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

    ASSOCIATION_MACROS = %i[belongs_to has_one has_many has_and_belongs_to_many].freeze
    VALIDATION_MACROS = %i[validates validates_presence_of validates_uniqueness_of validates_format_of validates_length_of validates_numericality_of validates_inclusion_of validates_exclusion_of validates_acceptance_of validates_confirmation_of].freeze
    CALLBACK_MACROS = %i[before_save after_save before_create after_create before_update after_update before_destroy after_destroy after_commit after_rollback before_validation after_validation].freeze

    # Model analysis methods
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

    VIEW_CONTROL_FLOW_KEYWORDS = %w[if unless elsif else case for while end].freeze

    # View analysis methods
    def count_view_logic_lines(_lines)
      count = 0
      erb_ruby_fragments(@source).each do |ruby|
        tokens = ruby.scan(/\b\w+\b/)
        count += 1 if (tokens & VIEW_CONTROL_FLOW_KEYWORDS).any?
      end
      count
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

    DATA_CHANGE_METHODS = %i[
      execute update_all delete_all
      find_each update update_columns update_column
      update! save save!
    ].freeze

    # Migration analysis methods
    def has_data_changes?
      return false unless @ast

      found = false
      find_nodes(@ast, :send) do |send_node|
        method_name = send_node.children[1]
        found = true if DATA_CHANGE_METHODS.include?(method_name)
      end
      found
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

    # Service analysis methods
    def analyze_service
      return {} unless @ast

      {
        rails_type: :service,
        has_call_method: has_call_method?,
        dependencies: detect_service_dependencies,
        error_handling: detect_error_handling,
        complexity_score: calculate_service_complexity,
        rails_smells: detect_service_smells
      }
    end

    def has_call_method?
      return false unless @ast
      
      has_instance_call = false
      has_class_call = false
      
      find_nodes(@ast, :def) do |node|
        method_name = node.children[0].to_s
        has_instance_call = true if method_name == 'call'
      end
      
      find_nodes(@ast, :defs) do |node|
        method_name = node.children[1].to_s
        has_class_call = true if method_name == 'call'
      end
      
      has_instance_call || has_class_call
    end

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

    def detect_error_handling
      error_handling = {
        rescue_blocks: @source.scan(/rescue/).count,
        raise_statements: @source.scan(/raise/).count
      }
      
      error_handling[:has_error_handling] = error_handling[:rescue_blocks] > 0 || error_handling[:raise_statements] > 0
      error_handling
    end

    def calculate_service_complexity
      complexity = 0
      
      # Base complexity from dependencies
      complexity += detect_service_dependencies.count * 2
      
      # Conditional complexity
      complexity += @source.scan(/\bif\b/).count
      complexity += @source.scan(/\bunless\b/).count
      complexity += @source.scan(/\bcase\b/).count
      
      # Error handling complexity
      error_handling = detect_error_handling
      complexity += error_handling[:rescue_blocks] * 2
      complexity += error_handling[:raise_statements]
      
      complexity
    end

    def detect_service_smells
      smells = []
      
      unless has_call_method?
        smells << {
          type: :missing_call_method,
          severity: :high
        }
      end
      
      complexity = calculate_service_complexity
      if complexity > 15
        smells << {
          type: :fat_service,
          complexity: complexity,
          severity: :high
        }
      end
      
      error_handling = detect_error_handling
      unless error_handling[:has_error_handling]
        smells << {
          type: :missing_error_handling,
          severity: :medium
        }
      end
      
      smells
    end

    # Interactor analysis methods
    def analyze_interactor
      return {} unless @ast

      {
        rails_type: :interactor,
        has_call_method: has_call_method?,
        context_usage: detect_context_usage,
        fail_usage: detect_fail_usage,
        is_organizer: is_organizer?,
        complexity_score: calculate_interactor_complexity,
        rails_smells: detect_interactor_smells
      }
    end

    def detect_context_usage
      {
        context_references: @source.scan(/(?<!@)\bcontext\./).count,
        instance_context_references: @source.scan(/@context/).count
      }
    end

    def detect_fail_usage
      {
        context_fail: @source.scan(/context\.fail/).count,
        fail_bang: @source.scan(/fail!/).count
      }
    end

    def is_organizer?
      @source.include?('organize') || @source.include?('Interactor::Organizer')
    end

    def calculate_interactor_complexity
      complexity = 0
      
      # Base complexity for organizers
      complexity += 5 if is_organizer?
      
      # Context usage complexity
      context_usage = detect_context_usage
      complexity += context_usage[:context_references]
      complexity += context_usage[:instance_context_references]
      
      # Conditional complexity
      complexity += @source.scan(/\bif\b/).count
      complexity += @source.scan(/\bunless\b/).count
      
      # Fail usage adds complexity
      fail_usage = detect_fail_usage
      complexity += fail_usage[:context_fail] * 2
      complexity += fail_usage[:fail_bang] * 2
      
      complexity
    end

    def detect_interactor_smells
      smells = []
      
      unless has_call_method?
        smells << {
          type: :missing_call_method,
          severity: :high
        }
      end
      
      if is_organizer?
        complexity = calculate_interactor_complexity
        if complexity > 20
          smells << {
            type: :complex_organizer,
            complexity: complexity,
            severity: :high
          }
        end
      end
      
      fail_usage = detect_fail_usage
      if fail_usage[:context_fail] == 0 && fail_usage[:fail_bang] == 0
        smells << {
          type: :missing_failure_handling,
          severity: :medium
        }
      end
      
      smells
    end

    # Serializer analysis methods
    def analyze_serializer
      return {} unless @ast

      {
        rails_type: :serializer,
        attribute_count: count_serializer_attributes,
        association_count: count_serializer_associations,
        custom_method_count: count_custom_serializer_methods,
        has_conditional_attributes: has_conditional_attributes?,
        rails_smells: detect_serializer_smells
      }
    end

    def count_serializer_attributes
      # Count attributes declarations (lines starting with attributes/attribute)
      @source.scan(/^\s*attributes?\s+/).count + @source.scan(/^\s*attribute\s+/).count
    end

    def count_serializer_associations
      associations = 0
      association_methods = %w[has_one has_many belongs_to]
      
      association_methods.each do |method|
        associations += @source.scan(/^\s*#{method}\s+/).count
      end
      
      associations
    end

    def count_custom_serializer_methods
      return 0 unless @ast
      
      method_count = 0
      standard_methods = %w[initialize attributes serialize serializable_hash]
      
      find_nodes(@ast, :def) do |node|
        method_name = node.children[0].to_s
        unless standard_methods.include?(method_name) || method_name.start_with?('_')
          method_count += 1
        end
      end
      
      method_count
    end

    def has_conditional_attributes?
      @source.include?('if:') || @source.include?('unless:') || @source.include?('condition:')
    end

    def detect_serializer_smells
      smells = []
      
      attribute_count = count_serializer_attributes
      association_count = count_serializer_associations
      total_fields = attribute_count + association_count
      
      if total_fields > 20
        smells << {
          type: :fat_serializer,
          field_count: total_fields,
          severity: :high
        }
      end
      
      custom_method_count = count_custom_serializer_methods
      if custom_method_count > 10
        smells << {
          type: :complex_serializer,
          method_count: custom_method_count,
          severity: :medium
        }
      end
      
      if attribute_count == 0 && association_count == 0
        smells << {
          type: :empty_serializer,
          severity: :low
        }
      end
      
      smells
    end

  end
end
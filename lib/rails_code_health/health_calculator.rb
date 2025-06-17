module RailsCodeHealth
  class HealthCalculator
    def initialize
      @config = RailsCodeHealth.configuration
      @thresholds = @config.thresholds
      @weights = @thresholds['scoring_weights']
    end

    def calculate_scores(analysis_results)
      analysis_results.map do |file_result|
        health_score = calculate_file_health_score(file_result)
        file_result.merge(
          health_score: health_score,
          health_category: categorize_health(health_score),
          recommendations: generate_recommendations(file_result)
        )
      end
    end

    private

    def calculate_file_health_score(file_result)
      # Start with a perfect score of 10
      base_score = 10.0
      
      # Apply penalties based on different factors
      penalties = []
      
      # Ruby-specific penalties
      penalties.concat(calculate_ruby_penalties(file_result))
      
      # Rails-specific penalties
      penalties.concat(calculate_rails_penalties(file_result))
      
      # Code smell penalties
      penalties.concat(calculate_code_smell_penalties(file_result))
      
      # Apply file type multiplier
      file_type_multiplier = get_file_type_multiplier(file_result[:file_type])
      
      # Calculate weighted penalty
      total_penalty = penalties.sum * file_type_multiplier
      
      # Ensure score doesn't go below 1
      final_score = [base_score - total_penalty, 1.0].max
      
      final_score.round(1)
    end

    def calculate_ruby_penalties(file_result)
      return [] unless file_result[:ruby_analysis]

      penalties = []
      ruby_data = file_result[:ruby_analysis]
      
      # Method length penalties
      if ruby_data[:method_metrics]
        ruby_data[:method_metrics].each do |method|
          penalty = calculate_method_length_penalty(method[:line_count])
          penalties << penalty * @weights['method_length'] if penalty > 0
        end
      end
      
      # Class length penalties
      if ruby_data[:class_metrics]
        ruby_data[:class_metrics].each do |klass|
          penalty = calculate_class_length_penalty(klass[:line_count])
          penalties << penalty * @weights['class_length'] if penalty > 0
        end
      end
      
      # Complexity penalties
      if ruby_data[:method_metrics]
        ruby_data[:method_metrics].each do |method|
          # Cyclomatic complexity
          complexity_penalty = calculate_complexity_penalty(method[:cyclomatic_complexity])
          penalties << complexity_penalty * @weights['cyclomatic_complexity'] if complexity_penalty > 0
          
          # Nesting depth
          nesting_penalty = calculate_nesting_penalty(method[:nesting_depth])
          penalties << nesting_penalty * @weights['nesting_depth'] if nesting_penalty > 0
          
          # Parameter count
          param_penalty = calculate_parameter_penalty(method[:parameter_count])
          penalties << param_penalty * @weights['parameter_count'] if param_penalty > 0
        end
      end
      
      penalties
    end

    def calculate_rails_penalties(file_result)
      return [] unless file_result[:rails_analysis]

      penalties = []
      rails_data = file_result[:rails_analysis]
      file_type = rails_data[:rails_type]
      
      case file_type
      when :controller
        penalties.concat(calculate_controller_penalties(rails_data))
      when :model
        penalties.concat(calculate_model_penalties(rails_data))
      when :view
        penalties.concat(calculate_view_penalties(rails_data))
      when :helper
        penalties.concat(calculate_helper_penalties(rails_data))
      when :migration
        penalties.concat(calculate_migration_penalties(rails_data))
      end
      
      penalties
    end

    def calculate_controller_penalties(controller_data)
      penalties = []
      
      # Too many actions
      action_count = controller_data[:action_count] || 0
      if action_count > @thresholds['rails_specific']['controller_actions']['yellow']
        severity = action_count > @thresholds['rails_specific']['controller_actions']['red'] ? 2.0 : 1.0
        penalties << severity * @weights['rails_conventions']
      end
      
      # Missing strong parameters
      unless controller_data[:uses_strong_parameters]
        penalties << 1.0 * @weights['rails_conventions']
      end
      
      # Direct model access
      if controller_data[:has_direct_model_access]
        penalties << 1.5 * @weights['rails_conventions']
      end
      
      penalties
    end

    def calculate_model_penalties(model_data)
      penalties = []
      
      # Fat model
      if model_data[:has_fat_model_smell]
        penalties << 2.0 * @weights['rails_conventions']
      end
      
      # Missing validations
      validation_count = model_data[:validation_count] || 0
      if validation_count == 0
        penalties << 0.5 * @weights['rails_conventions']
      end
      
      # Too many callbacks
      callback_count = model_data[:callback_count] || 0
      if callback_count > 5
        penalties << 1.0 * @weights['rails_conventions']
      end
      
      penalties
    end

    def calculate_view_penalties(view_data)
      penalties = []
      
      # Long views
      total_lines = view_data[:total_lines] || 0
      if total_lines > @thresholds['rails_specific']['view_length']['yellow']
        severity = total_lines > @thresholds['rails_specific']['view_length']['red'] ? 2.0 : 1.0
        penalties << severity * @weights['rails_conventions']
      end
      
      # Logic in views
      logic_lines = view_data[:logic_lines] || 0
      if logic_lines > 5
        penalties << (logic_lines / 5.0) * @weights['rails_conventions']
      end
      
      # Inline styles/JavaScript
      if view_data[:has_inline_styles]
        penalties << 0.5 * @weights['rails_conventions']
      end
      
      if view_data[:has_inline_javascript]
        penalties << 1.0 * @weights['rails_conventions']
      end
      
      penalties
    end

    def calculate_helper_penalties(helper_data)
      penalties = []
      
      method_count = helper_data[:method_count] || 0
      if method_count > 15
        penalties << 1.0 * @weights['rails_conventions']
      end
      
      penalties
    end

    def calculate_migration_penalties(migration_data)
      penalties = []
      
      if migration_data[:has_data_changes]
        penalties << 2.0 * @weights['rails_conventions']
      end
      
      complexity = migration_data[:complexity_score] || 0
      if complexity > 20
        penalties << 1.0 * @weights['rails_conventions']
      end
      
      penalties
    end

    def calculate_code_smell_penalties(file_result)
      penalties = []
      
      # Ruby code smells
      if file_result[:ruby_analysis] && file_result[:ruby_analysis][:code_smells]
        file_result[:ruby_analysis][:code_smells].each do |smell|
          penalty = case smell[:severity]
                   when :high then 2.0
                   when :medium then 1.0
                   when :low then 0.5
                   else 0.5
                   end
          penalties << penalty * @weights['code_smells']
        end
      end
      
      # Rails code smells
      if file_result[:rails_analysis] && file_result[:rails_analysis][:rails_smells]
        file_result[:rails_analysis][:rails_smells].each do |smell|
          penalty = case smell[:severity]
                   when :high then 2.0
                   when :medium then 1.0
                   when :low then 0.5
                   else 0.5
                   end
          penalties << penalty * @weights['code_smells']
        end
      end
      
      penalties
    end

    # Individual penalty calculation methods
    def calculate_method_length_penalty(line_count)
      thresholds = @thresholds['ruby_thresholds']['method_length']
      return 0 if line_count <= thresholds['green']
      return 1.0 if line_count <= thresholds['yellow']
      return 2.0 if line_count <= thresholds['red']
      3.0 # Extremely long methods
    end

    def calculate_class_length_penalty(line_count)
      thresholds = @thresholds['ruby_thresholds']['class_length']
      return 0 if line_count <= thresholds['green']
      return 1.0 if line_count <= thresholds['yellow']
      return 2.0 if line_count <= thresholds['red']
      3.0 # Extremely long classes
    end

    def calculate_complexity_penalty(complexity)
      thresholds = @thresholds['ruby_thresholds']['cyclomatic_complexity']
      return 0 if complexity <= thresholds['green']
      return 1.0 if complexity <= thresholds['yellow']
      return 2.0 if complexity <= thresholds['red']
      3.0 # Extremely complex methods
    end

    def calculate_nesting_penalty(depth)
      thresholds = @thresholds['ruby_thresholds']['nesting_depth']
      return 0 if depth <= thresholds['green']
      return 1.0 if depth <= thresholds['yellow']
      return 2.0 if depth <= thresholds['red']
      3.0 # Extremely nested code
    end

    def calculate_parameter_penalty(param_count)
      thresholds = @thresholds['ruby_thresholds']['parameter_count']
      return 0 if param_count <= thresholds['green']
      return 0.5 if param_count <= thresholds['yellow']
      return 1.0 if param_count <= thresholds['red']
      2.0 # Too many parameters
    end

    def get_file_type_multiplier(file_type)
      @thresholds['file_type_multipliers'][file_type.to_s] || 1.0
    end

    def categorize_health(score)
      case score
      when 8.0..10.0
        :healthy
      when 4.0...8.0
        :warning
      when 1.0...4.0
        :alert
      else
        :critical
      end
    end

    def generate_recommendations(file_result)
      recommendations = []
      
      # Add recommendations based on analysis results
      if file_result[:ruby_analysis]
        recommendations.concat(generate_ruby_recommendations(file_result[:ruby_analysis]))
      end
      
      if file_result[:rails_analysis]
        recommendations.concat(generate_rails_recommendations(file_result[:rails_analysis]))
      end
      
      recommendations.uniq
    end

    def generate_ruby_recommendations(ruby_analysis)
      recommendations = []
      
      if ruby_analysis[:code_smells]
        ruby_analysis[:code_smells].each do |smell|
          case smell[:type]
          when :long_method
            recommendations << "Break down the #{smell[:method_name]} method (#{smell[:line_count]} lines) into smaller, focused methods"
          when :god_class
            recommendations << "Refactor #{smell[:class_name]} class into smaller, more focused classes"
          when :high_complexity
            recommendations << "Reduce complexity of #{smell[:method_name]} method (complexity: #{smell[:complexity]})"
          when :too_many_parameters
            recommendations << "Reduce parameter count for #{smell[:method_name]} method or introduce parameter objects"
          when :nested_conditionals
            recommendations << "Reduce nesting depth in #{smell[:method_name]} method using guard clauses or extraction"
          end
        end
      end
      
      recommendations
    end

    def generate_rails_recommendations(rails_analysis)
      recommendations = []
      
      if rails_analysis[:rails_smells]
        rails_analysis[:rails_smells].each do |smell|
          case smell[:type]
          when :too_many_actions
            recommendations << "Consider splitting this controller - it has #{smell[:count]} actions"
          when :missing_strong_parameters
            recommendations << "Implement strong parameters for security"
          when :direct_model_access
            recommendations << "Move model logic to the model layer or service objects"
          when :fat_model
            recommendations << "Extract business logic into service objects or concerns"
          when :logic_in_view
            recommendations << "Move view logic to helpers or presenters (#{smell[:logic_lines]} logic lines found)"
          when :callback_hell
            recommendations << "Reduce model callbacks (#{smell[:count]} found) - consider service objects"
          when :data_changes_in_migration
            recommendations << "Avoid data changes in migrations - use rake tasks instead"
          end
        end
      end
      
      recommendations
    end
  end
end
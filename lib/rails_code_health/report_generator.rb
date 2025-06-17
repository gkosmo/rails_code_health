module RailsCodeHealth
  class ReportGenerator
    def initialize(scored_results)
      @results = scored_results
    end

    def generate
      puts generate_summary_report
      puts "\n" + "="*80 + "\n"
      puts generate_detailed_report
      puts "\n" + "="*80 + "\n"
      puts generate_recommendations_report
    end

    def generate_json_report
      {
        summary: generate_summary_data,
        files: @results.map { |result| format_file_result(result) },
        recommendations: collect_all_recommendations,
        generated_at: Time.now.iso8601
      }.to_json
    end

    private

    def generate_summary_report
      summary = []
      summary << "Rails Code Health Report"
      summary << "=" * 50
      summary << ""
      
      total_files = @results.count
      healthy_files = @results.count { |r| r[:health_category] == :healthy }
      warning_files = @results.count { |r| r[:health_category] == :warning }
      alert_files = @results.count { |r| r[:health_category] == :alert }
      critical_files = @results.count { |r| r[:health_category] == :critical }
      
      summary << "📊 Overall Health Summary:"
      summary << "  Total files analyzed: #{total_files}"
      summary << "  🟢 Healthy files (8.0-10.0): #{healthy_files} (#{percentage(healthy_files, total_files)}%)"
      summary << "  🟡 Warning files (4.0-7.9): #{warning_files} (#{percentage(warning_files, total_files)}%)"
      summary << "  🔴 Alert files (1.0-3.9): #{alert_files} (#{percentage(alert_files, total_files)}%)"
      summary << "  ⚫ Critical files (<1.0): #{critical_files} (#{percentage(critical_files, total_files)}%)" if critical_files > 0
      summary << ""
      
      average_score = (@results.sum { |r| r[:health_score] || 0 } / total_files.to_f).round(1)
      summary << "📈 Average Health Score: #{average_score}/10.0"
      
      summary << ""
      summary << generate_file_type_breakdown
      
      summary.join("\n")
    end

    def generate_file_type_breakdown
      breakdown = []
      breakdown << "📂 Breakdown by File Type:"
      
      file_types = @results.group_by { |r| r[:file_type] }
      
      file_types.each do |type, files|
        next if files.empty?
        
        avg_score = (files.sum { |f| f[:health_score] || 0 } / files.count.to_f).round(1)
        healthy_count = files.count { |f| f[:health_category] == :healthy }
        
        breakdown << "  #{type.to_s.capitalize}: #{files.count} files, avg score: #{avg_score}, #{healthy_count} healthy"
      end
      
      breakdown.join("\n")
    end

    def generate_detailed_report
      detailed = []
      detailed << "📋 Detailed File Analysis"
      detailed << "=" * 50
      detailed << ""
      
      # Sort by health score (worst first)
      sorted_results = @results.sort_by { |r| r[:health_score] || 0 }
      
      # Show worst 10 files
      worst_files = sorted_results.first(10)
      
      detailed << "🚨 Files Needing Most Attention (Bottom 10):"
      detailed << ""
      
      worst_files.each_with_index do |result, index|
        detailed << format_file_summary(result, index + 1)
        detailed << ""
      end
      
      # Show best files if we have healthy ones
      healthy_files = @results.select { |r| r[:health_category] == :healthy }
      if healthy_files.any?
        detailed << "✅ Top Performing Files:"
        detailed << ""
        
        best_files = healthy_files.sort_by { |r| -(r[:health_score] || 0) }.first(5)
        best_files.each_with_index do |result, index|
          detailed << format_file_summary(result, index + 1, prefix: "👍")
          detailed << ""
        end
      end
      
      detailed.join("\n")
    end

    def generate_recommendations_report
      recommendations = []
      recommendations << "💡 Key Recommendations"
      recommendations << "=" * 50
      recommendations << ""
      
      # Collect and categorize all recommendations
      all_recommendations = collect_all_recommendations
      
      if all_recommendations.empty?
        recommendations << "🎉 Great job! No major issues found."
        return recommendations.join("\n")
      end
      
      # Group recommendations by frequency
      recommendation_counts = Hash.new(0)
      all_recommendations.each { |rec| recommendation_counts[rec] += 1 }
      
      # Sort by frequency (most common first)
      sorted_recommendations = recommendation_counts.sort_by { |_, count| -count }
      
      recommendations << "📈 Most Common Issues (by frequency):"
      recommendations << ""
      
      sorted_recommendations.first(10).each_with_index do |(rec, count), index|
        recommendations << "#{index + 1}. #{rec} (#{count} occurrence#{'s' if count > 1})"
      end
      
      recommendations << ""
      recommendations << "🎯 Priority Actions:"
      recommendations << ""
      
      # Find files with lowest scores and their recommendations
      critical_files = @results.select { |r| r[:health_score] && r[:health_score] < 4.0 }
      if critical_files.any?
        recommendations << "1. 🚨 Address critical files immediately:"
        critical_files.first(3).each do |file|
          recommendations << "   - #{file[:relative_path]} (score: #{file[:health_score]})"
          if file[:recommendations] && file[:recommendations].any?
            file[:recommendations].first(2).each do |rec|
              recommendations << "     • #{rec}"
            end
          end
        end
        recommendations << ""
      end
      
      recommendations << "2. 🔧 Focus on these improvement areas:"
      recommendations << "   - Reduce method and class lengths"
      recommendations << "   - Lower cyclomatic complexity"
      recommendations << "   - Follow Rails conventions"
      recommendations << "   - Extract business logic from controllers and views"
      
      recommendations.join("\n")
    end

    def format_file_summary(result, rank, prefix: "🔍")
      summary = []
      
      health_emoji = case result[:health_category]
                    when :healthy then "🟢"
                    when :warning then "🟡"
                    when :alert then "🔴"
                    when :critical then "⚫"
                    else "❓"
                    end
      
      summary << "#{rank}. #{prefix} #{health_emoji} #{result[:relative_path]}"
      summary << "   Score: #{result[:health_score]}/10.0 | Type: #{result[:file_type]} | Size: #{format_file_size(result[:file_size])}"
      
      # Add key metrics if available
      if result[:ruby_analysis]
        metrics = []
        if result[:ruby_analysis][:method_metrics]
          method_count = result[:ruby_analysis][:method_metrics].count
          avg_complexity = result[:ruby_analysis][:method_metrics].map { |m| m[:cyclomatic_complexity] }.sum.to_f / method_count
          metrics << "#{method_count} methods"
          metrics << "avg complexity: #{avg_complexity.round(1)}"
        end
        
        if result[:ruby_analysis][:class_metrics]
          class_count = result[:ruby_analysis][:class_metrics].count
          metrics << "#{class_count} class#{'es' if class_count != 1}"
        end
        
        summary << "   Metrics: #{metrics.join(', ')}" if metrics.any?
      end
      
      # Add Rails-specific info
      if result[:rails_analysis]
        rails_info = []
        case result[:rails_analysis][:rails_type]
        when :controller
          rails_info << "#{result[:rails_analysis][:action_count]} actions"
        when :model
          rails_info << "#{result[:rails_analysis][:association_count]} associations" if result[:rails_analysis][:association_count]
          rails_info << "#{result[:rails_analysis][:validation_count]} validations" if result[:rails_analysis][:validation_count]
        when :view
          rails_info << "#{result[:rails_analysis][:logic_lines]} logic lines" if result[:rails_analysis][:logic_lines]
        end
        
        summary << "   Rails: #{rails_info.join(', ')}" if rails_info.any?
      end
      
      # Add top recommendations
      if result[:recommendations] && result[:recommendations].any?
        summary << "   Top issues:"
        result[:recommendations].first(2).each do |rec|
          summary << "     • #{rec}"
        end
      end
      
      summary.join("\n")
    end

    def collect_all_recommendations
      @results.flat_map { |r| r[:recommendations] || [] }.uniq
    end

    def generate_summary_data
      total_files = @results.count
      {
        total_files: total_files,
        healthy_files: @results.count { |r| r[:health_category] == :healthy },
        warning_files: @results.count { |r| r[:health_category] == :warning },
        alert_files: @results.count { |r| r[:health_category] == :alert },
        critical_files: @results.count { |r| r[:health_category] == :critical },
        average_score: (@results.sum { |r| r[:health_score] || 0 } / total_files.to_f).round(1),
        file_types: generate_file_type_summary
      }
    end

    def generate_file_type_summary
      file_types = @results.group_by { |r| r[:file_type] }
      
      file_types.transform_values do |files|
        {
          count: files.count,
          average_score: (files.sum { |f| f[:health_score] || 0 } / files.count.to_f).round(1),
          healthy_count: files.count { |f| f[:health_category] == :healthy }
        }
      end
    end

    def format_file_result(result)
      {
        file_path: result[:relative_path],
        file_type: result[:file_type],
        health_score: result[:health_score],
        health_category: result[:health_category],
        file_size: result[:file_size],
        last_modified: result[:last_modified],
        recommendations: result[:recommendations] || [],
        metrics: extract_key_metrics(result)
      }
    end

    def extract_key_metrics(result)
      metrics = {}
      
      if result[:ruby_analysis]
        ruby_metrics = result[:ruby_analysis]
        
        if ruby_metrics[:file_metrics]
          metrics[:lines_of_code] = ruby_metrics[:file_metrics][:code_lines]
          metrics[:total_lines] = ruby_metrics[:file_metrics][:total_lines]
        end
        
        if ruby_metrics[:method_metrics]
          methods = ruby_metrics[:method_metrics]
          metrics[:method_count] = methods.count
          metrics[:average_method_length] = methods.map { |m| m[:line_count] }.sum.to_f / methods.count if methods.any?
          metrics[:average_complexity] = methods.map { |m| m[:cyclomatic_complexity] }.sum.to_f / methods.count if methods.any?
          metrics[:max_complexity] = methods.map { |m| m[:cyclomatic_complexity] }.max
        end
        
        if ruby_metrics[:class_metrics]
          classes = ruby_metrics[:class_metrics]
          metrics[:class_count] = classes.count
          metrics[:average_class_length] = classes.map { |c| c[:line_count] }.sum.to_f / classes.count if classes.any?
        end
      end
      
      if result[:rails_analysis]
        rails_metrics = result[:rails_analysis]
        
        case rails_metrics[:rails_type]
        when :controller
          metrics[:controller_actions] = rails_metrics[:action_count]
          metrics[:uses_strong_parameters] = rails_metrics[:uses_strong_parameters]
        when :model
          metrics[:associations] = rails_metrics[:association_count]
          metrics[:validations] = rails_metrics[:validation_count]
          metrics[:callbacks] = rails_metrics[:callback_count]
        when :view
          metrics[:view_logic_lines] = rails_metrics[:logic_lines]
          metrics[:has_inline_styles] = rails_metrics[:has_inline_styles]
        end
      end
      
      # Round float values
      metrics.transform_values do |value|
        value.is_a?(Float) ? value.round(2) : value
      end
    end

    def percentage(part, total)
      return 0 if total.zero?
      ((part.to_f / total) * 100).round(1)
    end

    def format_file_size(size_in_bytes)
      return "0 B" if size_in_bytes.nil? || size_in_bytes.zero?
      
      units = %w[B KB MB GB]
      size = size_in_bytes.to_f
      unit_index = 0
      
      while size >= 1024 && unit_index < units.length - 1
        size /= 1024
        unit_index += 1
      end
      
      "#{size.round(1)} #{units[unit_index]}"
    end
  end
end
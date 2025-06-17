require 'parser/current'
require 'ast'
require 'rubocop/ast'
require 'active_support'
require 'json'
require 'pathname'

require_relative 'rails_code_health/version'
require_relative 'rails_code_health/configuration'
require_relative 'rails_code_health/project_detector'
require_relative 'rails_code_health/file_analyzer'
require_relative 'rails_code_health/ruby_analyzer'
require_relative 'rails_code_health/rails_analyzer'
require_relative 'rails_code_health/health_calculator'
require_relative 'rails_code_health/report_generator'
require_relative 'rails_code_health/cli'

module RailsCodeHealth
  class Error < StandardError; end

  class << self
    def analyze(path = '.')
      project_path = Pathname.new(path).expand_path
      
      unless ProjectDetector.rails_project?(project_path)
        raise Error, "Not a Rails project directory: #{project_path}"
      end

      analyzer = FileAnalyzer.new(project_path)
      results = analyzer.analyze_all

      health_calculator = HealthCalculator.new
      scored_results = health_calculator.calculate_scores(results)

      ReportGenerator.new(scored_results).generate
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end
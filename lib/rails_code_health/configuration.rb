module RailsCodeHealth
  class Configuration
    attr_accessor :thresholds, :excluded_paths, :output_format

    def initialize
      @thresholds = load_default_thresholds
      @excluded_paths = default_excluded_paths
      @output_format = :console
    end

    def thresholds
      @thresholds ||= load_default_thresholds
    end

    def load_thresholds_from_file(file_path)
      if File.exist?(file_path)
        @thresholds = JSON.parse(File.read(file_path))
      else
        raise Error, "Thresholds file not found: #{file_path}"
      end
    end

    private

    def load_default_thresholds
      config_file = File.join(File.dirname(__FILE__), '..', '..', 'config', 'thresholds.json')
      if File.exist?(config_file)
        JSON.parse(File.read(config_file))
      else
        # Fallback to hardcoded defaults if config file is missing
        default_hardcoded_thresholds
      end
    end

    def default_excluded_paths
      [
        'vendor/**/*',
        'tmp/**/*',
        'log/**/*',
        'node_modules/**/*',
        'coverage/**/*',
        '.git/**/*',
        'public/assets/**/*',
        'db/schema.rb',
        'spec/**/*',
        'test/**/*'
      ]
    end

    def default_hardcoded_thresholds
      {
        'ruby_thresholds' => {
          'method_length' => { 'green' => 15, 'yellow' => 25, 'red' => 40 },
          'class_length' => { 'green' => 100, 'yellow' => 200, 'red' => 400 },
          'cyclomatic_complexity' => { 'green' => 6, 'yellow' => 10, 'red' => 15 },
          'abc_complexity' => { 'green' => 15, 'yellow' => 25, 'red' => 40 },
          'nesting_depth' => { 'green' => 3, 'yellow' => 5, 'red' => 8 },
          'parameter_count' => { 'green' => 3, 'yellow' => 5, 'red' => 8 }
        },
        'rails_specific' => {
          'controller_actions' => { 'green' => 5, 'yellow' => 10, 'red' => 20 },
          'controller_length' => { 'green' => 50, 'yellow' => 100, 'red' => 200 },
          'model_public_methods' => { 'green' => 7, 'yellow' => 12, 'red' => 20 },
          'view_length' => { 'green' => 30, 'yellow' => 50, 'red' => 100 },
          'migration_complexity' => { 'green' => 10, 'yellow' => 20, 'red' => 40 }
        },
        'file_type_multipliers' => {
          'controllers' => 1.2,
          'models' => 1.0,
          'views' => 0.8,
          'helpers' => 0.9,
          'lib' => 1.1,
          'specs' => 0.7,
          'migrations' => 0.6
        },
        'scoring_weights' => {
          'method_length' => 0.15,
          'class_length' => 0.12,
          'cyclomatic_complexity' => 0.20,
          'nesting_depth' => 0.18,
          'parameter_count' => 0.10,
          'duplication' => 0.25,
          'rails_conventions' => 0.15,
          'code_smells' => 0.25
        }
      }
    end
  end
end
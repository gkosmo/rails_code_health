module RailsCodeHealth
  class FileAnalyzer
    def initialize(project_path)
      @project_path = Pathname.new(project_path)
    end

    def analyze_all
      ruby_files = find_ruby_files
      view_files = find_view_files
      
      all_files = ruby_files + view_files
      
      all_files.map do |file_path|
        analyze_file(file_path)
      end.compact
    end

    def analyze_file(file_path)
      file_path = Pathname.new(file_path) unless file_path.is_a?(Pathname)
      
      return nil unless file_path.exist?

      file_type = ProjectDetector.detect_file_type(file_path, @project_path)
      return nil unless file_type

      result = {
        file_path: file_path.to_s,
        relative_path: file_path.relative_path_from(@project_path).to_s,
        file_type: file_type,
        file_size: file_path.size,
        last_modified: file_path.mtime
      }

      # Analyze Ruby code if it's a Ruby file
      if file_path.extname == '.rb'
        ruby_analyzer = RubyAnalyzer.new(file_path)
        result[:ruby_analysis] = ruby_analyzer.analyze
      end

      # Add Rails-specific analysis
      rails_analyzer = RailsAnalyzer.new(file_path, file_type)
      rails_analysis = rails_analyzer.analyze
      result[:rails_analysis] = rails_analysis unless rails_analysis.empty?

      result
    rescue => e
      {
        file_path: file_path.to_s,
        relative_path: file_path.relative_path_from(@project_path).to_s,
        file_type: file_type,
        error: "Analysis failed: #{e.message}"
      }
    end

    private

    def find_ruby_files
      ruby_patterns = [
        @project_path + 'app/**/*.rb',
        @project_path + 'lib/**/*.rb',
        @project_path + 'config/**/*.rb',
        @project_path + 'db/migrate/*.rb'
      ]

      files = []
      ruby_patterns.each do |pattern|
        files.concat(Dir.glob(pattern))
      end

      # Filter out files we don't want to analyze
      files.reject! do |file|
        relative_path = Pathname.new(file).relative_path_from(@project_path).to_s
        should_skip_file?(relative_path)
      end

      files.map { |f| Pathname.new(f) }
    end

    def find_view_files
      view_patterns = [
        @project_path + 'app/views/**/*.erb',
        @project_path + 'app/views/**/*.haml',
        @project_path + 'app/views/**/*.slim'
      ]

      files = []
      view_patterns.each do |pattern|
        files.concat(Dir.glob(pattern))
      end

      files.map { |f| Pathname.new(f) }
    end

    def should_skip_file?(relative_path)
      skip_patterns = [
        %r{^vendor/},
        %r{^tmp/},
        %r{^log/},
        %r{^node_modules/},
        %r{^coverage/},
        %r{\.git/},
        %r{^public/assets/},
        %r{^db/schema\.rb$},
        %r{^config/routes\.rb$}, # Often auto-generated and long
        %r{^config/application\.rb$}, # Framework boilerplate
        %r{^config/environment\.rb$}, # Framework boilerplate
        %r{^config/environments/}, # Environment configs
        %r{^config/initializers/devise\.rb$}, # Often very long generated files
        %r{^app/assets/},
        %r{_test\.rb$},
        %r{_spec\.rb$}
      ]

      skip_patterns.any? { |pattern| relative_path.match?(pattern) }
    end
  end
end
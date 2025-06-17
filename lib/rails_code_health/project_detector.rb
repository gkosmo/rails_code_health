module RailsCodeHealth
  class ProjectDetector
    RAILS_INDICATORS = [
      'config/application.rb',
      'config/environment.rb',
      'Gemfile'
    ].freeze

    RAILS_DIRECTORIES = [
      'app/controllers',
      'app/models',
      'app/views',
      'config'
    ].freeze

    class << self
      def rails_project?(path)
        path = Pathname.new(path) unless path.is_a?(Pathname)
        
        has_rails_files?(path) && has_rails_structure?(path) && has_rails_gemfile?(path)
      end

      def detect_file_type(file_path, project_root)
        relative_path = file_path.relative_path_from(project_root).to_s

        case relative_path
        when %r{^app/controllers/.*_controller\.rb$}
          :controller
        when %r{^app/models/.*\.rb$}
          :model
        when %r{^app/views/.*\.(erb|haml|slim)$}
          :view
        when %r{^app/helpers/.*_helper\.rb$}
          :helper
        when %r{^lib/.*\.rb$}
          :lib
        when %r{^db/migrate/.*\.rb$}
          :migration
        when %r{^spec/.*_spec\.rb$}, %r{^test/.*_test\.rb$}
          :test
        when %r{^config/.*\.rb$}
          :config
        else
          :ruby if file_path.extname == '.rb'
        end
      end

      private

      def has_rails_files?(path)
        RAILS_INDICATORS.any? { |file| (path + file).exist? }
      end

      def has_rails_structure?(path)
        RAILS_DIRECTORIES.all? { |dir| (path + dir).directory? }
      end

      def has_rails_gemfile?(path)
        gemfile_path = path + 'Gemfile'
        return false unless gemfile_path.exist?

        begin
          gemfile_content = gemfile_path.read
          gemfile_content.include?('rails') || 
          gemfile_content.include?('railties') ||
          gemfile_content.include?('activesupport')
        rescue => e
          # If we can't read the Gemfile, assume it's not Rails
          false
        end
      end
    end
  end
end
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
        when %r{^app/.*/controllers/.*_controller\.rb$}, %r{^app/controllers/.*_controller\.rb$}
          :controller
        when %r{^app/models/.*\.rb$}
          :model
        when %r{^app/views/.*\.(erb|haml|slim)$}
          :view
        when %r{^app/helpers/.*_helper\.rb$}
          :helper
        when %r{^app/.*/services/.*\.rb$}, %r{^app/services/.*\.rb$}
          :service
        when %r{^app/.*/interactors/.*\.rb$}, %r{^app/interactors/.*\.rb$}
          :interactor
        when %r{^app/.*/serializers/.*\.rb$}, %r{^app/serializers/.*\.rb$}
          :serializer
        when %r{^app/.*/forms/.*\.rb$}, %r{^app/forms/.*\.rb$}
          :form
        when %r{^app/.*/decorators/.*\.rb$}, %r{^app/decorators/.*\.rb$}
          :decorator
        when %r{^app/.*/presenters/.*\.rb$}, %r{^app/presenters/.*\.rb$}
          :presenter
        when %r{^app/.*/policies/.*\.rb$}, %r{^app/policies/.*\.rb$}
          :policy
        when %r{^app/.*/jobs/.*\.rb$}, %r{^app/jobs/.*\.rb$}
          :job
        when %r{^app/.*/workers/.*\.rb$}, %r{^app/workers/.*\.rb$}
          :worker
        when %r{^app/.*/mailers/.*\.rb$}, %r{^app/mailers/.*\.rb$}
          :mailer
        when %r{^app/.*/channels/.*\.rb$}, %r{^app/channels/.*\.rb$}
          :channel
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

      def detect_detailed_file_type(file_path, project_root)
        relative_path = file_path.relative_path_from(project_root).to_s
        file_type = detect_file_type(file_path, project_root)
        
        context = {
          organization: detect_organization_pattern(relative_path),
          domain: extract_domain(relative_path),
          area: extract_area(relative_path),
          api_version: extract_api_version(relative_path)
        }.compact

        { type: file_type, context: context }
      end

      private

      def detect_organization_pattern(relative_path)
        case relative_path
        when %r{^app/topics/}
          :topic_based
        when %r{^app/domains/}
          :domain_based
        when %r{^app/modules/}
          :module_based
        else
          :traditional
        end
      end

      def extract_domain(relative_path)
        case relative_path
        when %r{^app/topics/([^/]+)/}
          $1
        when %r{^app/domains/([^/]+)/}
          $1
        when %r{^app/modules/([^/]+)/}
          $1
        else
          nil
        end
      end

      def extract_area(relative_path)
        areas = %w[admin backoffice api]
        areas.each do |area|
          return area if relative_path.include?("/#{area}/")
        end
        nil
      end

      def extract_api_version(relative_path)
        match = relative_path.match(%r{/v(\d+)/})
        match ? "v#{match[1]}" : nil
      end

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
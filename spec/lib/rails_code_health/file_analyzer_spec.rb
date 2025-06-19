require 'spec_helper'
require 'tmpdir'

RSpec.describe RailsCodeHealth::FileAnalyzer do
  let(:project_path) { Dir.mktmpdir }
  let(:analyzer) { described_class.new(project_path) }

  after { FileUtils.remove_entry(project_path) }

  def create_file(path, content = "# test file")
    full_path = File.join(project_path, path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  describe '#find_view_files' do
    context 'with traditional view structure' do
      it 'finds ERB views' do
        create_file('app/views/users/index.html.erb')
        create_file('app/views/users/show.html.erb')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/views/users/index.html.erb'))
        expect(paths).to include(end_with('app/views/users/show.html.erb'))
      end

      it 'finds HAML views' do
        create_file('app/views/users/index.html.haml')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/views/users/index.html.haml'))
      end

      it 'finds Slim views' do
        create_file('app/views/users/index.html.slim')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/views/users/index.html.slim'))
      end
    end

    context 'with nested view structures' do
      it 'finds views in domain-based organization' do
        create_file('app/domains/billing/views/payments/index.html.erb')
        create_file('app/domains/billing/views/invoices/show.html.erb')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/domains/billing/views/payments/index.html.erb'))
        expect(paths).to include(end_with('app/domains/billing/views/invoices/show.html.erb'))
      end

      it 'finds views in topic-based organization' do
        create_file('app/topics/backoffice/views/reports/dashboard.html.erb')
        create_file('app/topics/backoffice/views/users/list.html.haml')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/topics/backoffice/views/reports/dashboard.html.erb'))
        expect(paths).to include(end_with('app/topics/backoffice/views/users/list.html.haml'))
      end

      it 'finds views in module-based organization' do
        create_file('app/modules/auth/views/sessions/new.html.slim')
        create_file('app/modules/auth/views/passwords/reset.html.erb')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/modules/auth/views/sessions/new.html.slim'))
        expect(paths).to include(end_with('app/modules/auth/views/passwords/reset.html.erb'))
      end

      it 'finds views in deeply nested structures' do
        create_file('app/topics/backoffice/admin/views/reports/v2/dashboard.html.erb')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/topics/backoffice/admin/views/reports/v2/dashboard.html.erb'))
      end
    end

    context 'with mixed structures' do
      it 'finds views in both traditional and nested structures' do
        # Traditional
        create_file('app/views/users/index.html.erb')
        create_file('app/views/posts/show.html.haml')
        
        # Nested
        create_file('app/domains/billing/views/payments/index.html.erb')
        create_file('app/topics/admin/views/dashboard/index.html.slim')

        view_files = analyzer.send(:find_view_files)
        paths = view_files.map(&:to_s)

        expect(paths).to include(end_with('app/views/users/index.html.erb'))
        expect(paths).to include(end_with('app/views/posts/show.html.haml'))
        expect(paths).to include(end_with('app/domains/billing/views/payments/index.html.erb'))
        expect(paths).to include(end_with('app/topics/admin/views/dashboard/index.html.slim'))
      end
    end
  end

  describe '#find_ruby_files' do
    it 'finds Ruby files in app directory including new file types' do
      # Traditional
      create_file('app/controllers/users_controller.rb')
      create_file('app/models/user.rb')
      
      # New file types
      create_file('app/services/user_service.rb')
      create_file('app/interactors/create_user.rb')
      create_file('app/serializers/user_serializer.rb')
      create_file('app/forms/user_form.rb')
      create_file('app/decorators/user_decorator.rb')
      create_file('app/presenters/user_presenter.rb')
      create_file('app/policies/user_policy.rb')
      create_file('app/jobs/email_job.rb')
      create_file('app/workers/background_worker.rb')

      ruby_files = analyzer.send(:find_ruby_files)
      paths = ruby_files.map(&:to_s)

      expect(paths).to include(end_with('app/controllers/users_controller.rb'))
      expect(paths).to include(end_with('app/models/user.rb'))
      expect(paths).to include(end_with('app/services/user_service.rb'))
      expect(paths).to include(end_with('app/interactors/create_user.rb'))
      expect(paths).to include(end_with('app/serializers/user_serializer.rb'))
      expect(paths).to include(end_with('app/forms/user_form.rb'))
      expect(paths).to include(end_with('app/decorators/user_decorator.rb'))
      expect(paths).to include(end_with('app/presenters/user_presenter.rb'))
      expect(paths).to include(end_with('app/policies/user_policy.rb'))
      expect(paths).to include(end_with('app/jobs/email_job.rb'))
      expect(paths).to include(end_with('app/workers/background_worker.rb'))
    end

    it 'finds Ruby files in nested structures' do
      create_file('app/topics/billing/controllers/payments_controller.rb')
      create_file('app/domains/auth/services/authentication_service.rb')
      create_file('app/modules/reporting/interactors/generate_report.rb')

      ruby_files = analyzer.send(:find_ruby_files)
      paths = ruby_files.map(&:to_s)

      expect(paths).to include(end_with('app/topics/billing/controllers/payments_controller.rb'))
      expect(paths).to include(end_with('app/domains/auth/services/authentication_service.rb'))
      expect(paths).to include(end_with('app/modules/reporting/interactors/generate_report.rb'))
    end
  end

  describe '#should_skip_file?' do
    it 'skips test files' do
      expect(analyzer.send(:should_skip_file?, 'spec/models/user_spec.rb')).to be true
      expect(analyzer.send(:should_skip_file?, 'test/models/user_test.rb')).to be true
    end

    it 'skips vendor files' do
      expect(analyzer.send(:should_skip_file?, 'vendor/bundle/gems/rails.rb')).to be true
    end

    it 'skips generated files' do
      expect(analyzer.send(:should_skip_file?, 'db/schema.rb')).to be true
      expect(analyzer.send(:should_skip_file?, 'config/routes.rb')).to be true
    end

    it 'does not skip valid application files' do
      expect(analyzer.send(:should_skip_file?, 'app/controllers/users_controller.rb')).to be false
      expect(analyzer.send(:should_skip_file?, 'app/services/user_service.rb')).to be false
      expect(analyzer.send(:should_skip_file?, 'lib/custom_library.rb')).to be false
    end
  end

  describe '#analyze_file' do
    before do
      # Mock the detector and analyzers
      allow(RailsCodeHealth::ProjectDetector).to receive(:detect_file_type).and_return(:service)
      allow(RailsCodeHealth::RubyAnalyzer).to receive(:new).and_return(
        double(analyze: { method_count: 5, complexity: 8 })
      )
      allow(RailsCodeHealth::RailsAnalyzer).to receive(:new).and_return(
        double(analyze: { rails_type: :service, has_call_method: true })
      )
    end

    it 'analyzes a valid file' do
      create_file('app/services/user_service.rb', <<~RUBY)
        class UserService
          def call
            # service logic
          end
        end
      RUBY

      file_path = File.join(project_path, 'app/services/user_service.rb')
      result = analyzer.analyze_file(file_path)

      expect(result).to include(:file_path, :relative_path, :file_type, :file_size, :last_modified)
      expect(result[:file_type]).to eq(:service)
      expect(result[:ruby_analysis]).to eq({ method_count: 5, complexity: 8 })
      expect(result[:rails_analysis]).to eq({ rails_type: :service, has_call_method: true })
    end

    it 'handles non-existent files gracefully' do
      file_path = File.join(project_path, 'non_existent.rb')
      result = analyzer.analyze_file(file_path)

      expect(result).to be_nil
    end

    it 'handles analysis errors gracefully' do
      create_file('app/services/broken_service.rb', 'invalid ruby syntax {{{')
      
      # Mock an analysis error
      allow(RailsCodeHealth::RubyAnalyzer).to receive(:new).and_raise(StandardError, "Parse error")

      file_path = File.join(project_path, 'app/services/broken_service.rb')
      result = analyzer.analyze_file(file_path)

      expect(result).to include(:error)
      expect(result[:error]).to include("Analysis failed")
    end
  end

  describe '#analyze_all' do
    it 'analyzes all Ruby and view files' do
      # Create test files
      create_file('app/controllers/users_controller.rb')
      create_file('app/services/user_service.rb')
      create_file('app/views/users/index.html.erb')
      create_file('app/topics/billing/views/payments/show.html.haml')
      
      # Mock dependencies
      allow(RailsCodeHealth::ProjectDetector).to receive(:detect_file_type).and_return(:controller, :service, :view, :view)
      allow(RailsCodeHealth::RubyAnalyzer).to receive(:new).and_return(
        double(analyze: { method_count: 3 })
      )
      allow(RailsCodeHealth::RailsAnalyzer).to receive(:new).and_return(
        double(analyze: { rails_type: :controller })
      )

      results = analyzer.analyze_all

      expect(results.length).to eq(4)
      expect(results).to all(include(:file_type, :file_path))
    end
  end
end
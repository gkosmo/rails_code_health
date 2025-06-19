require 'spec_helper'

RSpec.describe RailsCodeHealth::ProjectDetector do
  let(:project_root) { Pathname.new('/test/project') }

  describe '.detect_file_type' do
    context 'with traditional Rails structure' do
      it 'detects controllers' do
        file_path = Pathname.new('/test/project/app/controllers/users_controller.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:controller)
      end

      it 'detects models' do
        file_path = Pathname.new('/test/project/app/models/user.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:model)
      end

      it 'detects views' do
        file_path = Pathname.new('/test/project/app/views/users/index.html.erb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:view)
      end

      it 'detects helpers' do
        file_path = Pathname.new('/test/project/app/helpers/application_helper.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:helper)
      end
    end

    context 'with nested directory structures' do
      it 'detects controllers in nested paths' do
        file_path = Pathname.new('/test/project/app/topics/backoffice/controllers/third_party_cases_controller.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:controller)
      end

      it 'detects services in nested paths' do
        file_path = Pathname.new('/test/project/app/domains/billing/services/payment_processor.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:service)
      end

      it 'detects interactors in nested paths' do
        file_path = Pathname.new('/test/project/app/modules/auth/interactors/authenticate_user.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:interactor)
      end
    end

    context 'with new file types' do
      it 'detects services' do
        file_path = Pathname.new('/test/project/app/services/user_service.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:service)
      end

      it 'detects interactors' do
        file_path = Pathname.new('/test/project/app/interactors/create_user.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:interactor)
      end

      it 'detects serializers' do
        file_path = Pathname.new('/test/project/app/serializers/user_serializer.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:serializer)
      end

      it 'detects forms' do
        file_path = Pathname.new('/test/project/app/forms/user_form.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:form)
      end

      it 'detects decorators' do
        file_path = Pathname.new('/test/project/app/decorators/user_decorator.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:decorator)
      end

      it 'detects presenters' do
        file_path = Pathname.new('/test/project/app/presenters/user_presenter.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:presenter)
      end

      it 'detects policies' do
        file_path = Pathname.new('/test/project/app/policies/user_policy.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:policy)
      end

      it 'detects jobs' do
        file_path = Pathname.new('/test/project/app/jobs/email_job.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:job)
      end

      it 'detects workers' do
        file_path = Pathname.new('/test/project/app/workers/background_worker.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:worker)
      end

      it 'detects mailers' do
        file_path = Pathname.new('/test/project/app/mailers/user_mailer.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:mailer)
      end

      it 'detects channels' do
        file_path = Pathname.new('/test/project/app/channels/chat_channel.rb')
        expect(described_class.detect_file_type(file_path, project_root)).to eq(:channel)
      end
    end
  end

  describe '.detect_detailed_file_type' do
    it 'returns file type and empty context for traditional structure' do
      file_path = Pathname.new('/test/project/app/controllers/users_controller.rb')
      result = described_class.detect_detailed_file_type(file_path, project_root)
      
      expect(result[:type]).to eq(:controller)
      expect(result[:context][:organization]).to eq(:traditional)
    end

    context 'with topic-based organization' do
      it 'detects topic-based organization and domain' do
        file_path = Pathname.new('/test/project/app/topics/backoffice/controllers/cases_controller.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:type]).to eq(:controller)
        expect(result[:context][:organization]).to eq(:topic_based)
        expect(result[:context][:domain]).to eq('backoffice')
      end

      it 'detects area information' do
        file_path = Pathname.new('/test/project/app/topics/backoffice/controllers/admin/users_controller.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:context][:area]).to eq('admin')
      end
    end

    context 'with domain-based organization' do
      it 'detects domain-based organization' do
        file_path = Pathname.new('/test/project/app/domains/billing/services/payment_service.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:type]).to eq(:service)
        expect(result[:context][:organization]).to eq(:domain_based)
        expect(result[:context][:domain]).to eq('billing')
      end
    end

    context 'with module-based organization' do
      it 'detects module-based organization' do
        file_path = Pathname.new('/test/project/app/modules/auth/interactors/login.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:type]).to eq(:interactor)
        expect(result[:context][:organization]).to eq(:module_based)
        expect(result[:context][:domain]).to eq('auth')
      end
    end

    context 'with API versioning' do
      it 'detects API version v1' do
        file_path = Pathname.new('/test/project/app/controllers/api/v1/users_controller.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:context][:api_version]).to eq('v1')
        expect(result[:context][:area]).to eq('api')
      end

      it 'detects API version v2' do
        file_path = Pathname.new('/test/project/app/topics/billing/controllers/api/v2/payments_controller.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:context][:api_version]).to eq('v2')
        expect(result[:context][:area]).to eq('api')
      end
    end

    context 'with admin areas' do
      it 'detects admin area' do
        file_path = Pathname.new('/test/project/app/controllers/admin/users_controller.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:context][:area]).to eq('admin')
      end

      it 'detects backoffice area' do
        file_path = Pathname.new('/test/project/app/services/backoffice/report_generator.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:context][:area]).to eq('backoffice')
      end
    end

    context 'with complex nested structures' do
      it 'detects all context information' do
        file_path = Pathname.new('/test/project/app/topics/backoffice/controllers/admin/v2/users_controller.rb')
        result = described_class.detect_detailed_file_type(file_path, project_root)
        
        expect(result[:type]).to eq(:controller)
        expect(result[:context][:organization]).to eq(:topic_based)
        expect(result[:context][:domain]).to eq('backoffice')
        expect(result[:context][:area]).to eq('admin')
        expect(result[:context][:api_version]).to eq('v2')
      end
    end
  end
end
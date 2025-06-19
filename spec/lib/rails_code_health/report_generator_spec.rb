require 'spec_helper'

RSpec.describe RailsCodeHealth::ReportGenerator do
  let(:sample_results) do
    [
      {
        file_path: '/test/app/controllers/users_controller.rb',
        relative_path: 'app/controllers/users_controller.rb',
        file_type: :controller,
        file_size: 1024,
        health_score: 8.5,
        health_category: :healthy,
        last_modified: Time.parse('2024-01-01'),
        rails_analysis: {
          rails_type: :controller,
          action_count: 5,
          has_business_logic: false,
          rails_smells: []
        },
        recommendations: []
      },
      {
        file_path: '/test/app/services/user_service.rb',
        relative_path: 'app/services/user_service.rb',
        file_type: :service,
        file_size: 2048,
        health_score: 7.2,
        health_category: :warning,
        last_modified: Time.parse('2024-01-01'),
        context: {
          organization: :domain_based,
          domain: 'auth',
          area: 'api'
        },
        rails_analysis: {
          rails_type: :service,
          has_call_method: true,
          dependencies: [:active_record, :external_api],
          complexity_score: 12,
          rails_smells: []
        },
        recommendations: ['Consider reducing complexity']
      },
      {
        file_path: '/test/app/domains/billing/interactors/process_payment.rb',
        relative_path: 'app/domains/billing/interactors/process_payment.rb',
        file_type: :interactor,
        file_size: 1536,
        health_score: 9.1,
        health_category: :healthy,
        last_modified: Time.parse('2024-01-01'),
        context: {
          organization: :domain_based,
          domain: 'billing',
          area: nil,
          api_version: 'v2'
        },
        rails_analysis: {
          rails_type: :interactor,
          has_call_method: true,
          is_organizer: false,
          complexity_score: 8,
          rails_smells: []
        },
        recommendations: []
      },
      {
        file_path: '/test/app/serializers/user_serializer.rb',
        relative_path: 'app/serializers/user_serializer.rb',
        file_type: :serializer,
        file_size: 512,
        health_score: 6.8,
        health_category: :warning,
        last_modified: Time.parse('2024-01-01'),
        rails_analysis: {
          rails_type: :serializer,
          attribute_count: 8,
          association_count: 3,
          custom_method_count: 2,
          rails_smells: []
        },
        recommendations: ['Consider splitting serializer']
      },
      {
        file_path: '/test/app/forms/user_form.rb',
        relative_path: 'app/forms/user_form.rb',
        file_type: :form,
        file_size: 768,
        health_score: 3.2,
        health_category: :alert,
        last_modified: Time.parse('2024-01-01'),
        rails_analysis: {
          rails_type: :form,
          rails_smells: [
            { type: :complex_form, severity: :high }
          ]
        },
        recommendations: ['Simplify form logic', 'Extract validations']
      }
    ]
  end

  let(:generator) { described_class.new(sample_results) }

  describe '#generate_file_type_breakdown' do
    it 'shows all file types with proper ordering' do
      breakdown = generator.send(:generate_file_type_breakdown)

      # Check that new file types are included
      expect(breakdown).to include('🎮 Controller: 1 files')
      expect(breakdown).to include('⚙️ Service: 1 files')
      expect(breakdown).to include('🔄 Interactor: 1 files')
      expect(breakdown).to include('📦 Serializer: 1 files')
      expect(breakdown).to include('📝 Form: 1 files')
    end

    it 'displays health metrics for each file type' do
      breakdown = generator.send(:generate_file_type_breakdown)

      expect(breakdown).to include('avg score: 8.5, 1 healthy')
      expect(breakdown).to include('avg score: 7.2, 0 healthy')
      expect(breakdown).to include('avg score: 9.1, 1 healthy')
    end

    it 'shows context breakdown for new file types' do
      breakdown = generator.send(:generate_file_type_breakdown)

      # Should show domain breakdown for service
      expect(breakdown).to match(/Service:.*\n.*🏢 Domains: auth: 1/)
      expect(breakdown).to match(/Service:.*\n.*🏠 Areas: api: 1/)
      
      # Should show domain and API version for interactor
      expect(breakdown).to match(/Interactor:.*\n.*🏢 Domains: billing: 1/)
      expect(breakdown).to match(/Interactor:.*\n.*🔢 API Versions: v2: 1/)
    end
  end

  describe '#get_file_type_emoji' do
    it 'returns correct emojis for all file types' do
      emoji_tests = {
        controller: "🎮",
        model: "📊",
        view: "🖼️",
        service: "⚙️",
        interactor: "🔄",
        serializer: "📦",
        form: "📝",
        decorator: "🎨",
        presenter: "🎪",
        policy: "🛡️",
        job: "⚡",
        worker: "👷",
        mailer: "📧",
        channel: "📡",
        unknown_type: "📄"
      }

      emoji_tests.each do |type, expected_emoji|
        expect(generator.send(:get_file_type_emoji, type)).to eq(expected_emoji)
      end
    end
  end

  describe '#generate_context_breakdown' do
    let(:files_with_context) do
      [
        {
          context: {
            organization: :domain_based,
            domain: 'billing',
            area: 'admin'
          }
        },
        {
          context: {
            organization: :topic_based,
            domain: 'auth',
            area: 'api',
            api_version: 'v1'
          }
        },
        {
          context: {
            organization: :domain_based,
            domain: 'billing',
            api_version: 'v2'
          }
        }
      ]
    end

    it 'generates organization breakdown' do
      breakdown = generator.send(:generate_context_breakdown, files_with_context)
      
      expect(breakdown).to include('📁 Organization: Domain based: 2, Topic based: 1')
    end

    it 'generates domain breakdown' do
      breakdown = generator.send(:generate_context_breakdown, files_with_context)
      
      expect(breakdown).to include('🏢 Domains: billing: 2, auth: 1')
    end

    it 'generates area breakdown' do
      breakdown = generator.send(:generate_context_breakdown, files_with_context)
      
      expect(breakdown).to include('🏠 Areas: admin: 1, api: 1')
    end

    it 'generates API version breakdown' do
      breakdown = generator.send(:generate_context_breakdown, files_with_context)
      
      expect(breakdown).to include('🔢 API Versions: v1: 1, v2: 1')
    end

    it 'returns empty string for files without context' do
      files_without_context = [{ other_data: 'value' }]
      breakdown = generator.send(:generate_context_breakdown, files_without_context)
      
      expect(breakdown).to eq('')
    end
  end

  describe '#format_file_summary' do
    it 'includes context information in file summary' do
      file_with_context = {
        relative_path: 'app/domains/billing/services/payment_service.rb',
        file_type: :service,
        file_size: 2048,
        health_score: 7.5,
        health_category: :warning,
        context: {
          organization: :domain_based,
          domain: 'billing',
          area: 'api',
          api_version: 'v2'
        },
        rails_analysis: {
          rails_type: :service,
          has_call_method: true,
          dependencies: [:active_record, :external_api],
          complexity_score: 15
        },
        recommendations: ['Reduce complexity']
      }

      summary = generator.send(:format_file_summary, file_with_context, 1)

      expect(summary).to include('Type: service')
      expect(summary).to include('Context: billing, api, v2, domain based')
      expect(summary).to include('call method')
      expect(summary).to include('deps: active_record, external_api')
      expect(summary).to include('complexity: 15')
    end

    it 'shows Rails-specific info for new file types' do
      service_result = {
        relative_path: 'app/services/user_service.rb',
        file_type: :service,
        file_size: 1024,
        health_score: 8.0,
        health_category: :healthy,
        rails_analysis: {
          rails_type: :service,
          has_call_method: true,
          dependencies: [:active_record, :email],
          complexity_score: 12
        }
      }

      summary = generator.send(:format_file_summary, service_result, 1)

      expect(summary).to include('Rails: call method, deps: active_record, email, complexity: 12')
    end

    it 'shows interactor-specific info' do
      interactor_result = {
        relative_path: 'app/interactors/create_user.rb',
        file_type: :interactor,
        file_size: 1024,
        health_score: 8.5,
        health_category: :healthy,
        rails_analysis: {
          rails_type: :interactor,
          has_call_method: true,
          is_organizer: true,
          complexity_score: 8
        }
      }

      summary = generator.send(:format_file_summary, interactor_result, 1)

      expect(summary).to include('Rails: call method, organizer, complexity: 8')
    end

    it 'shows serializer-specific info' do
      serializer_result = {
        relative_path: 'app/serializers/user_serializer.rb',
        file_type: :serializer,
        file_size: 512,
        health_score: 7.0,
        health_category: :warning,
        rails_analysis: {
          rails_type: :serializer,
          attribute_count: 5,
          association_count: 2,
          custom_method_count: 3
        }
      }

      summary = generator.send(:format_file_summary, serializer_result, 1)

      expect(summary).to include('Rails: 5 attributes, 2 associations, 3 custom methods')
    end
  end

  describe '#extract_key_metrics' do
    it 'extracts service metrics' do
      service_result = {
        rails_analysis: {
          rails_type: :service,
          has_call_method: true,
          dependencies: [:active_record, :external_api],
          complexity_score: 15,
          error_handling: { has_error_handling: true }
        }
      }

      metrics = generator.send(:extract_key_metrics, service_result)

      expect(metrics[:has_call_method]).to be true
      expect(metrics[:dependencies]).to eq([:active_record, :external_api])
      expect(metrics[:complexity_score]).to eq(15)
      expect(metrics[:error_handling]).to eq({ has_error_handling: true })
    end

    it 'extracts interactor metrics' do
      interactor_result = {
        rails_analysis: {
          rails_type: :interactor,
          has_call_method: true,
          is_organizer: false,
          context_usage: { context_references: 3, instance_context_references: 1 },
          complexity_score: 10
        }
      }

      metrics = generator.send(:extract_key_metrics, interactor_result)

      expect(metrics[:has_call_method]).to be true
      expect(metrics[:is_organizer]).to be false
      expect(metrics[:context_usage]).to eq({ context_references: 3, instance_context_references: 1 })
      expect(metrics[:complexity_score]).to eq(10)
    end

    it 'extracts serializer metrics' do
      serializer_result = {
        rails_analysis: {
          rails_type: :serializer,
          attribute_count: 8,
          association_count: 3,
          custom_method_count: 5,
          has_conditional_attributes: true
        }
      }

      metrics = generator.send(:extract_key_metrics, serializer_result)

      expect(metrics[:attribute_count]).to eq(8)
      expect(metrics[:association_count]).to eq(3)
      expect(metrics[:custom_method_count]).to eq(5)
      expect(metrics[:has_conditional_attributes]).to be true
    end

    it 'extracts controller business logic metrics' do
      controller_result = {
        rails_analysis: {
          rails_type: :controller,
          action_count: 7,
          uses_strong_parameters: true,
          has_business_logic: true
        }
      }

      metrics = generator.send(:extract_key_metrics, controller_result)

      expect(metrics[:controller_actions]).to eq(7)
      expect(metrics[:uses_strong_parameters]).to be true
      expect(metrics[:has_business_logic]).to be true
    end
  end

  describe '#generate_summary_report' do
    it 'includes file type breakdown with new types' do
      summary = generator.send(:generate_summary_report)

      expect(summary).to include('📂 Breakdown by File Type:')
      expect(summary).to include('🎮 Controller: 1 files')
      expect(summary).to include('⚙️ Service: 1 files')
      expect(summary).to include('🔄 Interactor: 1 files')
      expect(summary).to include('📦 Serializer: 1 files')
    end
  end

  describe '#generate_json_report' do
    it 'includes all new file type metrics' do
      json_report = JSON.parse(generator.generate_json_report)

      expect(json_report).to have_key('summary')
      expect(json_report).to have_key('files')
      expect(json_report['files']).to be_an(Array)
      
      service_file = json_report['files'].find { |f| f['file_type'] == 'service' }
      expect(service_file['metrics']).to include('has_call_method', 'dependencies', 'complexity_score')
      
      interactor_file = json_report['files'].find { |f| f['file_type'] == 'interactor' }
      expect(interactor_file['metrics']).to include('has_call_method', 'is_organizer', 'complexity_score')
      
      serializer_file = json_report['files'].find { |f| f['file_type'] == 'serializer' }
      expect(serializer_file['metrics']).to include('attribute_count', 'association_count', 'custom_method_count')
    end
  end
end
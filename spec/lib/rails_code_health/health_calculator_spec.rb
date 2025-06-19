require 'spec_helper'

RSpec.describe RailsCodeHealth::HealthCalculator do
  let(:calculator) { described_class.new }
  
  before do
    # Stub configuration to use known values
    allow(RailsCodeHealth).to receive(:configuration).and_return(
      double(thresholds: {
        'ruby_thresholds' => {
          'method_length' => { 'green' => 15, 'yellow' => 25, 'red' => 40 },
          'class_length' => { 'green' => 100, 'yellow' => 200, 'red' => 400 },
          'cyclomatic_complexity' => { 'green' => 6, 'yellow' => 10, 'red' => 15 },
          'nesting_depth' => { 'green' => 3, 'yellow' => 5, 'red' => 8 },
          'parameter_count' => { 'green' => 3, 'yellow' => 5, 'red' => 8 }
        },
        'rails_specific' => {
          'controller_actions' => { 'green' => 5, 'yellow' => 10, 'red' => 20 },
          'view_length' => { 'green' => 30, 'yellow' => 50, 'red' => 100 }
        },
        'service_thresholds' => {
          'dependency_count' => { 'green' => 3, 'yellow' => 5, 'red' => 8 },
          'complexity_score' => { 'green' => 10, 'yellow' => 15, 'red' => 25 }
        },
        'file_type_multipliers' => {
          'service' => 1.3,
          'interactor' => 1.2,
          'serializer' => 0.9,
          'controller' => 1.2
        },
        'scoring_weights' => {
          'method_length' => 0.15,
          'class_length' => 0.12,
          'cyclomatic_complexity' => 0.20,
          'nesting_depth' => 0.18,
          'parameter_count' => 0.10,
          'rails_conventions' => 0.15,
          'code_smells' => 0.25
        }
      })
    )
  end

  describe '#calculate_scores' do
    it 'calculates health scores for multiple files' do
      analysis_results = [
        {
          file_type: :controller,
          rails_analysis: {
            rails_type: :controller,
            action_count: 3,
            uses_strong_parameters: true,
            has_direct_model_access: false,
            has_business_logic: false,
            rails_smells: []
          }
        },
        {
          file_type: :service,
          rails_analysis: {
            rails_type: :service,
            has_call_method: true,
            dependencies: [:active_record],
            complexity_score: 8,
            error_handling: { has_error_handling: true },
            rails_smells: []
          }
        }
      ]

      results = calculator.calculate_scores(analysis_results)

      expect(results).to all(have_key(:health_score))
      expect(results).to all(have_key(:health_category))
      expect(results).to all(have_key(:recommendations))
    end
  end

  describe 'controller penalties' do
    it 'penalizes controllers with business logic' do
      file_result = {
        file_type: :controller,
        rails_analysis: {
          rails_type: :controller,
          action_count: 5,
          uses_strong_parameters: true,
          has_direct_model_access: false,
          has_business_logic: true,
          rails_smells: [
            { type: :business_logic_in_controller, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      # Should be penalized for business logic
      expect(score).to be < 10.0
    end

    it 'penalizes controllers with too many actions' do
      file_result = {
        file_type: :controller,
        rails_analysis: {
          rails_type: :controller,
          action_count: 15, # Above yellow threshold
          uses_strong_parameters: true,
          has_direct_model_access: false,
          has_business_logic: false,
          rails_smells: [
            { type: :too_many_actions, count: 15, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 10.0
    end
  end

  describe 'service penalties' do
    it 'heavily penalizes services without call method' do
      file_result = {
        file_type: :service,
        rails_analysis: {
          rails_type: :service,
          has_call_method: false,
          dependencies: [],
          complexity_score: 5,
          error_handling: { has_error_handling: true },
          rails_smells: [
            { type: :missing_call_method, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      # Should be heavily penalized for missing call method
      expect(score).to be < 7.0
    end

    it 'penalizes services with too many dependencies' do
      file_result = {
        file_type: :service,
        rails_analysis: {
          rails_type: :service,
          has_call_method: true,
          dependencies: [:active_record, :external_api, :file_system, :email, :cache, :extra1, :extra2, :extra3, :extra4],
          complexity_score: 5,
          error_handling: { has_error_handling: true },
          rails_smells: [
            { type: :fat_service, complexity: 18, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 9.0
    end

    it 'penalizes services with high complexity' do
      file_result = {
        file_type: :service,
        rails_analysis: {
          rails_type: :service,
          has_call_method: true,
          dependencies: [:active_record],
          complexity_score: 30, # Above red threshold
          error_handling: { has_error_handling: true },
          rails_smells: [
            { type: :fat_service, complexity: 30, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 8.0
    end

    it 'penalizes services without error handling' do
      file_result = {
        file_type: :service,
        rails_analysis: {
          rails_type: :service,
          has_call_method: true,
          dependencies: [:active_record],
          complexity_score: 8,
          error_handling: { has_error_handling: false },
          rails_smells: [
            { type: :missing_error_handling, severity: :medium }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 10.0
    end

    it 'applies service multiplier (1.3x)' do
      # Create two identical file results, one service, one controller
      base_rails_analysis = {
        rails_type: nil, # Will be set per test
        rails_smells: [
          { type: :some_smell, severity: :medium }
        ]
      }

      service_result = {
        file_type: :service,
        rails_analysis: base_rails_analysis.merge(rails_type: :service)
      }

      controller_result = {
        file_type: :controller,
        rails_analysis: base_rails_analysis.merge(rails_type: :controller)
      }

      service_score = calculator.send(:calculate_file_health_score, service_result)
      controller_score = calculator.send(:calculate_file_health_score, controller_result)

      # Service should have lower score due to higher multiplier
      expect(service_score).to be < controller_score
    end
  end

  describe 'interactor penalties' do
    it 'penalizes interactors without call method' do
      file_result = {
        file_type: :interactor,
        rails_analysis: {
          rails_type: :interactor,
          has_call_method: false,
          is_organizer: false,
          context_usage: { context_references: 0, instance_context_references: 0 },
          fail_usage: { context_fail: 0, fail_bang: 0 },
          complexity_score: 5,
          rails_smells: [
            { type: :missing_call_method, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 7.0
    end

    it 'penalizes complex organizers' do
      file_result = {
        file_type: :interactor,
        rails_analysis: {
          rails_type: :interactor,
          has_call_method: true,
          is_organizer: true,
          context_usage: { context_references: 2, instance_context_references: 1 },
          fail_usage: { context_fail: 1, fail_bang: 0 },
          complexity_score: 25, # Too complex for organizer
          rails_smells: [
            { type: :complex_organizer, complexity: 25, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 8.0
    end

    it 'penalizes interactors without failure handling' do
      file_result = {
        file_type: :interactor,
        rails_analysis: {
          rails_type: :interactor,
          has_call_method: true,
          is_organizer: false,
          context_usage: { context_references: 1, instance_context_references: 0 },
          fail_usage: { context_fail: 0, fail_bang: 0 },
          complexity_score: 8,
          rails_smells: [
            { type: :missing_failure_handling, severity: :medium }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 10.0
    end
  end

  describe 'serializer penalties' do
    it 'penalizes fat serializers' do
      file_result = {
        file_type: :serializer,
        rails_analysis: {
          rails_type: :serializer,
          attribute_count: 15,
          association_count: 8, # Total 23 fields
          custom_method_count: 3,
          has_conditional_attributes: false,
          rails_smells: [
            { type: :fat_serializer, field_count: 23, severity: :high }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 9.0
    end

    it 'penalizes complex serializers' do
      file_result = {
        file_type: :serializer,
        rails_analysis: {
          rails_type: :serializer,
          attribute_count: 5,
          association_count: 2,
          custom_method_count: 12, # Too many custom methods
          has_conditional_attributes: true,
          rails_smells: [
            { type: :complex_serializer, method_count: 12, severity: :medium }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 9.5
    end

    it 'penalizes empty serializers' do
      file_result = {
        file_type: :serializer,
        rails_analysis: {
          rails_type: :serializer,
          attribute_count: 0,
          association_count: 0,
          custom_method_count: 0,
          has_conditional_attributes: false,
          rails_smells: [
            { type: :empty_serializer, severity: :low }
          ]
        }
      }

      score = calculator.send(:calculate_file_health_score, file_result)
      
      expect(score).to be < 10.0
    end

    it 'applies serializer multiplier (0.9x - more lenient)' do
      # Create identical smell for serializer vs controller
      base_rails_analysis = {
        rails_smells: [
          { type: :some_smell, severity: :medium }
        ]
      }

      serializer_result = {
        file_type: :serializer,
        rails_analysis: base_rails_analysis.merge(rails_type: :serializer)
      }

      controller_result = {
        file_type: :controller,
        rails_analysis: base_rails_analysis.merge(rails_type: :controller)
      }

      serializer_score = calculator.send(:calculate_file_health_score, serializer_result)
      controller_score = calculator.send(:calculate_file_health_score, controller_result)

      # Serializer should have higher score due to lower multiplier
      expect(serializer_score).to be > controller_score
    end
  end

  describe '#categorize_health' do
    it 'categorizes scores correctly' do
      expect(calculator.send(:categorize_health, 9.5)).to eq(:healthy)
      expect(calculator.send(:categorize_health, 7.0)).to eq(:warning)
      expect(calculator.send(:categorize_health, 3.0)).to eq(:alert)
      expect(calculator.send(:categorize_health, 0.5)).to eq(:critical)
    end
  end

  describe 'recommendations' do
    it 'generates service-specific recommendations' do
      file_result = {
        rails_analysis: {
          rails_smells: [
            { type: :missing_call_method, severity: :high },
            { type: :fat_service, complexity: 20, severity: :high },
            { type: :missing_error_handling, severity: :medium }
          ]
        }
      }

      recommendations = calculator.send(:generate_recommendations, file_result)

      expect(recommendations).to include("Add a call method to follow service/interactor conventions")
      expect(recommendations).to include("Break down service into smaller, focused services (complexity: 20)")
      expect(recommendations).to include("Add proper error handling with rescue blocks")
    end

    it 'generates interactor-specific recommendations' do
      file_result = {
        rails_analysis: {
          rails_smells: [
            { type: :complex_organizer, complexity: 25, severity: :high },
            { type: :missing_failure_handling, severity: :medium }
          ]
        }
      }

      recommendations = calculator.send(:generate_recommendations, file_result)

      expect(recommendations).to include("Simplify organizer - it should only orchestrate other interactors (complexity: 25)")
      expect(recommendations).to include("Add failure handling using context.fail or fail! methods")
    end

    it 'generates serializer-specific recommendations' do
      file_result = {
        rails_analysis: {
          rails_smells: [
            { type: :fat_serializer, field_count: 25, severity: :high },
            { type: :complex_serializer, method_count: 15, severity: :medium },
            { type: :empty_serializer, severity: :low }
          ]
        }
      }

      recommendations = calculator.send(:generate_recommendations, file_result)

      expect(recommendations).to include("Split serializer - it has 25 fields")
      expect(recommendations).to include("Move complex logic out of serializer (15 custom methods)")
      expect(recommendations).to include("Add attributes or associations to provide value")
    end

    it 'generates controller business logic recommendations' do
      file_result = {
        rails_analysis: {
          rails_smells: [
            { type: :business_logic_in_controller, severity: :high }
          ]
        }
      }

      recommendations = calculator.send(:generate_recommendations, file_result)

      expect(recommendations).to include("Extract business logic from controller to service objects")
    end
  end
end
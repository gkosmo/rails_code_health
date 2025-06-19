require 'spec_helper'

RSpec.describe RailsCodeHealth::Configuration do
  let(:config) { described_class.new }

  describe '#thresholds' do
    it 'includes all new file type multipliers' do
      multipliers = config.thresholds['file_type_multipliers']

      expect(multipliers['service']).to eq(1.3)
      expect(multipliers['interactor']).to eq(1.2)
      expect(multipliers['serializer']).to eq(0.9)
      expect(multipliers['form']).to eq(1.1)
      expect(multipliers['decorator']).to eq(0.9)
      expect(multipliers['presenter']).to eq(0.9)
      expect(multipliers['policy']).to eq(1.2)
      expect(multipliers['job']).to eq(1.0)
      expect(multipliers['worker']).to eq(1.0)
    end

    it 'includes service-specific thresholds' do
      service_thresholds = config.thresholds['service_thresholds']

      expect(service_thresholds['dependency_count']).to eq({
        'green' => 3,
        'yellow' => 5,
        'red' => 8
      })

      expect(service_thresholds['complexity_score']).to eq({
        'green' => 10,
        'yellow' => 15,
        'red' => 25
      })
    end

    it 'maintains existing thresholds' do
      ruby_thresholds = config.thresholds['ruby_thresholds']
      rails_specific = config.thresholds['rails_specific']

      expect(ruby_thresholds['method_length']).not_to be_nil
      expect(ruby_thresholds['class_length']).not_to be_nil
      expect(rails_specific['controller_actions']).not_to be_nil
    end

    it 'includes scoring weights' do
      weights = config.thresholds['scoring_weights']

      expect(weights['method_length']).to eq(0.15)
      expect(weights['cyclomatic_complexity']).to eq(0.20)
      expect(weights['rails_conventions']).to eq(0.15)
      expect(weights['code_smells']).to eq(0.25)
    end
  end

  describe '#excluded_paths' do
    it 'includes default excluded paths' do
      excluded = config.excluded_paths

      expect(excluded).to include('vendor/**/*')
      expect(excluded).to include('tmp/**/*')
      expect(excluded).to include('spec/**/*')
      expect(excluded).to include('test/**/*')
    end
  end

  describe '#load_thresholds_from_file' do
    let(:temp_file) { Tempfile.new(['thresholds', '.json']) }

    after { temp_file.close }

    it 'loads thresholds from a JSON file' do
      custom_thresholds = {
        'ruby_thresholds' => {
          'method_length' => { 'green' => 10, 'yellow' => 20, 'red' => 30 }
        },
        'service_thresholds' => {
          'dependency_count' => { 'green' => 2, 'yellow' => 4, 'red' => 6 }
        }
      }

      temp_file.write(custom_thresholds.to_json)
      temp_file.rewind

      config.load_thresholds_from_file(temp_file.path)

      expect(config.thresholds['ruby_thresholds']['method_length']['green']).to eq(10)
      expect(config.thresholds['service_thresholds']['dependency_count']['green']).to eq(2)
    end

    it 'raises error for non-existent file' do
      expect {
        config.load_thresholds_from_file('/non/existent/file.json')
      }.to raise_error(RailsCodeHealth::Error, /Thresholds file not found/)
    end
  end

  describe 'default hardcoded thresholds' do
    it 'provides sensible defaults for all new file types' do
      defaults = config.send(:default_hardcoded_thresholds)

      # Services should have higher standards (1.3x multiplier)
      expect(defaults['file_type_multipliers']['service']).to be > 1.0

      # Decorators and serializers should be more lenient (0.9x multiplier)
      expect(defaults['file_type_multipliers']['decorator']).to be < 1.0
      expect(defaults['file_type_multipliers']['serializer']).to be < 1.0

      # Policies and interactors should have moderate standards
      expect(defaults['file_type_multipliers']['policy']).to eq(1.2)
      expect(defaults['file_type_multipliers']['interactor']).to eq(1.2)
    end

    it 'provides service-specific thresholds that make sense' do
      defaults = config.send(:default_hardcoded_thresholds)
      service_thresholds = defaults['service_thresholds']

      # Dependency thresholds should encourage focused services
      expect(service_thresholds['dependency_count']['green']).to eq(3)
      expect(service_thresholds['dependency_count']['yellow']).to eq(5)
      expect(service_thresholds['dependency_count']['red']).to eq(8)

      # Complexity thresholds should encourage simple services
      expect(service_thresholds['complexity_score']['green']).to eq(10)
      expect(service_thresholds['complexity_score']['yellow']).to eq(15)
      expect(service_thresholds['complexity_score']['red']).to eq(25)
    end
  end
end
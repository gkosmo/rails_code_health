require 'spec_helper'

RSpec.describe RailsCodeHealth::RubyAnalyzer do
  describe 'public method counts' do
    it 'distinguishes public from private methods in classes' do
      fixture = RailsCodeHealthFixtures.path_for('ruby/class_with_private_methods.rb')
      result = described_class.new(fixture).analyze

      example_class = result[:class_metrics].find { |c| c[:name] == :Example }
      expect(example_class[:method_count]).to eq(6) # all defs
      expect(example_class[:public_method_count]).to eq(3) # pub_one, pub_two, pub_three
    end

    it 'handles inline private def' do
      fixture = RailsCodeHealthFixtures.path_for('ruby/class_with_inline_private.rb')
      result = described_class.new(fixture).analyze

      example_class = result[:class_metrics].find { |c| c[:name] == :Example }
      expect(example_class[:method_count]).to eq(3)
      expect(example_class[:public_method_count]).to eq(2)
    end
  end

  describe 'parameter counts' do
    let(:methods) do
      fixture = RailsCodeHealthFixtures.path_for('ruby/method_with_kwargs.rb')
      result = described_class.new(fixture).analyze
      result[:method_metrics].each_with_object({}) { |m, h| h[m[:name]] = m }
    end

    it 'counts positional parameters' do
      expect(methods[:positional_only][:parameter_count]).to eq(3)
    end

    it 'counts required and optional keyword parameters' do
      expect(methods[:with_kwargs][:parameter_count]).to eq(3) # a, b:, c:
    end

    it 'counts splat, double-splat, and block as parameters' do
      expect(methods[:with_splat][:parameter_count]).to eq(3)
    end

    it 'returns 0 for empty argument list' do
      expect(methods[:empty_method][:parameter_count]).to eq(0)
    end
  end
end

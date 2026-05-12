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
end

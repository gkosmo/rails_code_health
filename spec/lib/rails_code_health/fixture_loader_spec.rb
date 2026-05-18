require 'spec_helper'

RSpec.describe RailsCodeHealthFixtures do
  describe '.path_for' do
    it 'returns an absolute path under spec/fixtures/code_samples' do
      path = described_class.path_for('ruby/method_with_kwargs.rb')
      expect(path.to_s).to end_with('spec/fixtures/code_samples/ruby/method_with_kwargs.rb')
      expect(path).to be_an_instance_of(Pathname)
    end

    it 'raises a clear error when fixture is missing' do
      expect { described_class.path_for('does_not_exist.rb') }
        .to raise_error(ArgumentError, /fixture not found/)
    end
  end
end

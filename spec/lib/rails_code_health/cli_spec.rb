require 'spec_helper'

RSpec.describe RailsCodeHealth::CLI do
  describe '#gate_exit_code' do
    let(:healthy_result)  { { health_score: 9.0, health_category: :healthy } }
    let(:warning_result)  { { health_score: 6.5, health_category: :warning } }
    let(:alert_result)    { { health_score: 4.5, health_category: :alert } }
    let(:critical_result) { { health_score: 2.0, health_category: :critical } }

    def cli_with_options(opts)
      cli = described_class.new([])
      cli.instance_variable_set(:@options, cli.instance_variable_get(:@options).merge(opts))
      cli
    end

    it 'returns 0 when no thresholds are configured' do
      cli = cli_with_options(fail_under: nil, max_critical: nil)
      expect(cli.send(:gate_exit_code, [critical_result, critical_result])).to eq(0)
    end

    it 'returns 0 when results are empty (cannot gate on nothing)' do
      cli = cli_with_options(fail_under: 9.0, max_critical: 0)
      expect(cli.send(:gate_exit_code, [])).to eq(0)
    end

    context 'with --fail-under' do
      it 'returns 0 when average score meets the threshold' do
        cli = cli_with_options(fail_under: 7.0)
        expect(cli.send(:gate_exit_code, [healthy_result, healthy_result])).to eq(0)
      end

      it 'returns 2 when average score is below the threshold' do
        cli = cli_with_options(fail_under: 7.0)
        expect(cli.send(:gate_exit_code, [warning_result, alert_result])).to eq(2)
      end

      it 'treats equal-to-threshold as passing' do
        cli = cli_with_options(fail_under: 6.5)
        expect(cli.send(:gate_exit_code, [warning_result])).to eq(0)
      end
    end

    context 'with --max-critical' do
      it 'returns 0 when critical count is at or below the limit' do
        cli = cli_with_options(max_critical: 1)
        expect(cli.send(:gate_exit_code, [healthy_result, critical_result])).to eq(0)
      end

      it 'returns 2 when critical count exceeds the limit' do
        cli = cli_with_options(max_critical: 0)
        expect(cli.send(:gate_exit_code, [healthy_result, critical_result])).to eq(2)
      end
    end

    context 'with both flags' do
      it 'fails if either condition is violated' do
        cli = cli_with_options(fail_under: 9.5, max_critical: 5)
        expect(cli.send(:gate_exit_code, [healthy_result, warning_result])).to eq(2)
      end

      it 'passes only when both conditions hold' do
        cli = cli_with_options(fail_under: 7.0, max_critical: 0)
        expect(cli.send(:gate_exit_code, [healthy_result, healthy_result])).to eq(0)
      end
    end
  end
end

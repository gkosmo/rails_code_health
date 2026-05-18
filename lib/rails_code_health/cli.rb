require 'optparse'

module RailsCodeHealth
  class CLI
    def self.start(args)
      new(args).run
    end

    def initialize(args)
      @args = args
      @options = {
        path: '.',
        format: :console,
        output: nil,
        config: nil,
        verbose: false,
        fail_under: nil,
        max_critical: nil
      }
    end

    def run
      parse_options

      begin
        # Load custom config if provided
        if @options[:config]
          RailsCodeHealth.configuration.load_thresholds_from_file(@options[:config])
        end

        # Set output format
        RailsCodeHealth.configuration.output_format = @options[:format]

        puts "🔍 Analyzing Rails project at: #{@options[:path]}" if @options[:verbose]
        puts "📊 Using format: #{@options[:format]}" if @options[:verbose]

        # Run the analysis
        results = analyze_project

        # Output the report
        output_report(results)

        puts "\n✅ Analysis complete!" if @options[:verbose]

        # Apply CI gating thresholds (after report is emitted so the user still sees output)
        exit_code = gate_exit_code(results)
        exit exit_code unless exit_code.zero?

      rescue RailsCodeHealth::Error => e
        puts "❌ Error: #{e.message}"
        exit 1
      rescue => e
        puts "💥 Unexpected error: #{e.message}"
        puts e.backtrace.join("\n") if @options[:verbose]
        exit 1
      end
    end

    private

    def parse_options
      OptionParser.new do |opts|
        opts.banner = "Usage: rails-health [options] [path]"
        opts.separator ""
        opts.separator "Analyze the code health of a Ruby on Rails application"
        opts.separator ""
        opts.separator "Options:"

        opts.on("-f", "--format FORMAT", [:console, :json], 
                "Output format (console, json)") do |format|
          @options[:format] = format
        end

        opts.on("-o", "--output FILE", 
                "Output file (default: stdout)") do |file|
          @options[:output] = file
        end

        opts.on("-c", "--config FILE", 
                "Custom configuration file") do |file|
          @options[:config] = file
        end

        opts.on("-v", "--verbose",
                "Verbose output") do
          @options[:verbose] = true
        end

        opts.on("--fail-under SCORE", Float,
                "Exit non-zero if average health score is below SCORE (e.g. 7.0)") do |score|
          @options[:fail_under] = score
        end

        opts.on("--max-critical N", Integer,
                "Exit non-zero if more than N files fall into the Critical category") do |n|
          @options[:max_critical] = n
        end

        opts.on_tail("-h", "--help", "Show this message") do
          puts opts
          exit
        end

        opts.on_tail("--version", "Show version") do
          puts "Rails Code Health v#{RailsCodeHealth::VERSION}"
          exit
        end
      end.parse!(@args)

      # Use remaining argument as path if provided
      @options[:path] = @args.first if @args.any?
    end

    def analyze_project
      project_path = Pathname.new(@options[:path]).expand_path
      
      unless ProjectDetector.rails_project?(project_path)
        raise Error, "Not a Rails project directory: #{project_path}"
      end

      puts "📁 Found Rails project!" if @options[:verbose]

      analyzer = FileAnalyzer.new(project_path)
      results = analyzer.analyze_all

      puts "📝 Analyzed #{results.count} files" if @options[:verbose]

      health_calculator = HealthCalculator.new
      scored_results = health_calculator.calculate_scores(results)

      puts "🧮 Calculated health scores" if @options[:verbose]

      scored_results
    end

    def output_report(results)
      case @options[:format]
      when :console
        output_console_report(results)
      when :json
        output_json_report(results)
      end
    end

    def output_console_report(results)
      report_generator = ReportGenerator.new(results)
      
      if @options[:output]
        File.write(@options[:output], capture_console_output(report_generator))
        puts "📄 Report saved to: #{@options[:output]}"
      else
        report_generator.generate
      end
    end

    def output_json_report(results)
      report_generator = ReportGenerator.new(results)
      json_report = report_generator.generate_json_report
      
      if @options[:output]
        File.write(@options[:output], json_report)
        puts "📄 JSON report saved to: #{@options[:output]}"
      else
        puts json_report
      end
    end

    def gate_exit_code(results)
      return 0 if results.nil? || results.empty?
      return 0 if @options[:fail_under].nil? && @options[:max_critical].nil?

      failures = []

      if (threshold = @options[:fail_under])
        average = results.sum { |r| r[:health_score] || 0 } / results.size.to_f
        if average < threshold
          failures << "average health score #{average.round(2)} is below --fail-under #{threshold}"
        end
      end

      if (max = @options[:max_critical])
        critical_count = results.count { |r| r[:health_category] == :critical }
        if critical_count > max
          failures << "#{critical_count} critical file(s) exceeds --max-critical #{max}"
        end
      end

      return 0 if failures.empty?

      warn ""
      warn "❌ Health gate failed:"
      failures.each { |msg| warn "   - #{msg}" }
      2
    end

    def capture_console_output(report_generator)
      original_stdout = $stdout
      $stdout = StringIO.new
      
      report_generator.generate
      
      output = $stdout.string
      $stdout = original_stdout
      
      output
    end
  end
end
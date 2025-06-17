require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

desc "Run the code health analyzer on a sample Rails project"
task :demo do
  puts "Running demo analysis..."
  system("bundle exec bin/rails-health --verbose .")
end

desc "Generate documentation"
task :docs do
  system("yard doc")
end
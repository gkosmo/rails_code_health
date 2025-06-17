source 'https://rubygems.org'

gemspec

# Core parsing gems
gem 'parser', '~> 3.0'
gem 'ast', '~> 2.4'
gem 'rubocop-ast', '~> 1.0'

# Minimal Rails dependencies - avoid full Rails stack
gem 'activesupport', '~> 7.0', require: false

# For complexity analysis
gem 'flog', '~> 4.6'
gem 'flay', '~> 2.13'

# Fix for psych compilation issues on ARM Macs
gem 'psych', '~> 4.0' if RUBY_VERSION < '3.1'

group :development do
  gem 'rake', '~> 13.0'
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.50'
  gem 'pry'
end

group :test do
  gem 'rspec-core', '~> 3.12'
  gem 'simplecov', '~> 0.22'
end
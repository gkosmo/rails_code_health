Gem::Specification.new do |spec|
  spec.name          = 'rails_code_health'
  spec.version       = '0.1.0'
  spec.authors       = ['George Kosmopoulos']
  spec.email         = ['gkosmo1@hotmail.com']

  spec.summary       = 'Code health analyzer for Ruby on Rails applications'
  spec.description   = 'A gem that evaluates the code health of Ruby on Rails applications using metrics inspired by CodeScene\'s research on technical debt and maintainability.'
  spec.homepage      = 'https://github.com/gkosmo/rails_code_health'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir['lib/**/*', 'config/**/*', 'README.md', 'LICENSE.txt', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  # Core dependencies
  spec.add_dependency 'parser', '~> 3.0'
  spec.add_dependency 'ast', '~> 2.4'
  spec.add_dependency 'rubocop-ast', '~> 1.0'
  spec.add_dependency 'activesupport', '~> 7.0'
  spec.add_dependency 'flog', '~> 4.6'
  spec.add_dependency 'flay', '~> 2.13'

  # Development dependencies
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.50'

  spec.executables   = ['rails-health']
  spec.bindir        = 'bin'
end
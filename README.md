# Rails Code Health

A Ruby gem that evaluates the code health of Ruby on Rails applications, inspired by CodeScene's research on technical debt and maintainability.

## Overview

Rails Code Health analyzes your Rails codebase and provides:
- **Health scores** (1-10 scale) for each file based on complexity, maintainability, and Rails conventions
- **Categorization** of files into Healthy (🟢), Warning (🟡), Alert (🔴), and Critical (⚫) categories
- **Actionable recommendations** for improving code quality
- **Rails-specific analysis** for controllers, models, views, helpers, and migrations

## Installation

Add this gem to your Rails application's Gemfile:

```ruby
gem 'rails_code_health', group: :development
```

Or install it globally:

```bash
gem install rails_code_health
```

## Usage

### Command Line Interface

Run analysis on your current Rails project:

```bash
rails-health
```

Analyze a specific Rails project:

```bash
rails-health /path/to/rails/project
```

Generate JSON output:

```bash
rails-health --format json --output report.json
```

Use custom configuration:

```bash
rails-health --config custom_thresholds.json
```

### Programmatic Usage

```ruby
require 'rails_code_health'

# Analyze current directory
report = RailsCodeHealth.analyze('.')

# Analyze specific path
report = RailsCodeHealth.analyze('/path/to/rails/project')

# Configure custom thresholds
RailsCodeHealth.configure do |config|
  config.load_thresholds_from_file('custom_config.json')
end
```

## What It Analyzes

### Ruby Code Metrics
- **Method length** - Long methods are harder to understand and maintain
- **Class length** - Large classes often violate single responsibility principle
- **Cyclomatic complexity** - High complexity increases defect risk
- **Nesting depth** - Deep nesting reduces readability
- **Parameter count** - Too many parameters suggest poor design
- **ABC complexity** - Assignments, branches, and conditions complexity

### Rails-Specific Analysis

#### Controllers
- Action count per controller
- Strong parameters usage
- Direct model access detection
- Response format analysis

#### Models
- Association count
- Validation presence
- Callback complexity
- Fat model detection

#### Views
- Logic in views detection
- Inline styles/JavaScript
- Template length analysis

#### Helpers & Migrations
- Helper method count
- Migration complexity
- Data changes in migrations

### Code Smells Detection
- **God Class/Method** - Classes or methods doing too much
- **Long Parameter List** - Methods with too many parameters
- **Nested Conditionals** - Deep if/else nesting
- **Missing Validations** - Models without proper validation
- **Logic in Views** - Business logic in presentation layer

## Health Score Calculation

Health scores range from 1.0 (critical) to 10.0 (excellent) based on:

- **File type multipliers** - Different standards for different file types
- **Weighted penalties** - More important issues have higher impact
- **Rails conventions** - Adherence to Rails best practices
- **Code complexity** - Multiple complexity metrics combined

### Score Categories

- **🟢 Healthy (8.0-10.0)**: Well-structured, maintainable code
- **🟡 Warning (4.0-7.9)**: Some issues, but generally acceptable
- **🔴 Alert (1.0-3.9)**: Significant problems requiring attention
- **⚫ Critical (<1.0)**: Severe issues, immediate action needed

## Configuration

Create a custom `thresholds.json` file:

```json
{
  "ruby_thresholds": {
    "method_length": {
      "green": 15,
      "yellow": 25,
      "red": 40
    },
    "cyclomatic_complexity": {
      "green": 6,
      "yellow": 10,
      "red": 15
    }
  },
  "rails_specific": {
    "controller_actions": {
      "green": 5,
      "yellow": 10,
      "red": 20
    }
  },
  "scoring_weights": {
    "method_length": 0.15,
    "cyclomatic_complexity": 0.20,
    "rails_conventions": 0.15
  }
}
```

## Sample Output

```
Rails Code Health Report
==================================================

📊 Overall Health Summary:
  Total files analyzed: 45
  🟢 Healthy files (8.0-10.0): 32 (71.1%)
  🟡 Warning files (4.0-7.9): 10 (22.2%)
  🔴 Alert files (1.0-3.9): 3 (6.7%)

📈 Average Health Score: 7.8/10.0

📂 Breakdown by File Type:
  Controller: 8 files, avg score: 7.2, 5 healthy
  Model: 12 files, avg score: 8.4, 10 healthy
  View: 15 files, avg score: 8.1, 12 healthy

🚨 Files Needing Most Attention:
1. 🔴 app/controllers/admin/reports_controller.rb
   Score: 3.2/10.0 | Type: controller | Size: 15.2 KB
   Top issues:
     • Break down the generate_report method (156 lines) into smaller methods
     • Consider splitting this controller - it has 18 actions

💡 Key Recommendations:
1. Reduce method and class lengths
2. Lower cyclomatic complexity  
3. Follow Rails conventions
4. Extract business logic from controllers
```

## Research Foundation

This gem is inspired by the peer-reviewed research paper ["Code Red: The Business Impact of Code Quality"](https://arxiv.org/pdf/2203.04374) by Adam Tornhill and Markus Borg, which found that:

- Low quality code contains **15x more defects** than high quality code
- Resolving issues in low quality code takes **124% more time**
- Issue resolutions involve **9x longer maximum cycle times**

## Development

After checking out the repo, run:

```bash
bundle install
```

Run tests:

```bash
bundle exec rspec
```

Run the gem locally:

```bash
bundle exec bin/rails-health /path/to/rails/project
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Credits

Inspired by [CodeScene](https://codescene.com/) and the research on technical debt's business impact. This gem implements similar concepts specifically for Ruby on Rails applications.
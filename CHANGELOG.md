# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2025-06-19

### Added
- Comprehensive test suite with RSpec covering all major components
- Test coverage for Configuration, FileAnalyzer, HealthCalculator, ProjectDetector, RailsAnalyzer, and ReportGenerator

### Changed
- Enhanced Configuration class with improved validation and error handling
- Improved FileAnalyzer with better file processing capabilities
- Updated HealthCalculator with more robust scoring algorithms
- Enhanced ProjectDetector with better Rails project detection
- Improved RailsAnalyzer with more comprehensive Rails pattern analysis
- Enhanced ReportGenerator with better formatting and output options

### Fixed
- Various bug fixes and improvements based on user feedback

## [0.1.0] - 2025-06-17

### Added
- Initial release of Rails Code Health analyzer
- Ruby code complexity analysis (cyclomatic complexity, method length, class length)
- Rails-specific pattern detection for controllers, models, views, helpers, and migrations
- Health scoring system (1-10 scale) based on CodeScene research
- Command-line interface with console and JSON output options
- Configurable thresholds and scoring weights
- Actionable recommendations for code improvements
- Support for Ruby 3.0+ and Rails 7.0+

### Features
- **Ruby Analysis**: Method/class length, cyclomatic complexity, nesting depth, parameter count
- **Rails Analysis**: Controller actions, model validations, view logic detection, migration complexity
- **Code Smells**: God classes/methods, long parameter lists, nested conditionals, missing validations
- **Reporting**: Detailed console output with health categories and JSON export
- **CLI**: `rails-health` command with options for format, output file, and custom configuration

[Unreleased]: https://github.com/gkosmo/rails_code_health/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/gkosmo/rails_code_health/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gkosmo/rails_code_health/releases/tag/v0.1.0
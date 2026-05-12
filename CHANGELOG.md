# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-05-12

### Added
- `RailsCodeHealth::ASTHelpers` module: shared AST traversal with scoped variants and visibility-aware def collection.
- Fixture-based RSpec test suite under `spec/fixtures/code_samples/`.
- New configuration group `smell_thresholds` for previously hard-coded values.

### Fixed
- `RubyAnalyzer#count_public_methods_in_class` now actually distinguishes public from private methods (including inline `private def foo`).
- `RubyAnalyzer#count_parameters` now counts only true parameter nodes.
- `RubyAnalyzer` nesting depth calculation no longer counts `:begin` and `:block` as nesting levels.
- `RailsAnalyzer#count_controller_actions` no longer inverts public/private; the seven canonical RESTful actions are correctly counted, and private helpers are excluded.
- `RailsAnalyzer#has_direct_model_access?` only fires when model calls appear inside public controller actions.
- `RailsAnalyzer#has_business_logic?` uses stricter signals (business-verb calls on model receivers, transactions, loops with conditionals) instead of matching any compound `if` or any `.each do`.
- Model `count_associations`, `count_validations`, `count_callbacks`, `count_scopes` count only top-level class body macros — no comments, strings, or nested-class matches.
- `has_fat_model_smell?` uses class-scoped code-line count and class-scoped method count.
- View `count_view_logic_lines` parses ERB fragments and no longer flags plain HTML that happens to contain `if`, `unless`, etc., in text.
- Migration `has_data_changes?` recognizes `find_each`, `update`, `update_columns`, `update_column`, `update!`, `update_all`, `delete_all`, `save`, `save!`, raw `connection.execute`, and `execute`.
- Service `detect_service_dependencies` uses word boundaries — `Profile.` no longer matches the `File.` check.
- God class, high complexity, parameter, and nesting smell thresholds are now read from configuration instead of inlined.

### Changed (may affect scores)
- Score changes are expected on any project where the above false positives or false negatives applied. Re-baseline before comparing to v0.2.0 reports.

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

[Unreleased]: https://github.com/gkosmo/rails_code_health/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/gkosmo/rails_code_health/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gkosmo/rails_code_health/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gkosmo/rails_code_health/releases/tag/v0.1.0
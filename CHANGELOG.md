# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-05-18

### Fixed
- `ReportGenerator` no longer includes migration files in the "Top Performing Files" showcase. Migrations are almost always trivially simple by construction, so they routinely crowded out genuinely well-written healthy files in the top-5 list. Migrations are still analyzed and still appear in the "Files Needing Most Attention" list when problematic.

### Added
- `docs/index.html` static landing page for GitHub Pages, explaining the why and how of the gem.

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
- Service `detect_service_smells` now flags `:fat_service` at complexity ≥ 13 (was > 15, which left some genuinely-fat services unflagged).
- Interactor `detect_fail_usage` no longer double-counts `context.fail!` as both `context_fail` and `fail_bang`.
- Serializer `count_serializer_attributes` / `count_serializer_associations` now count each symbol (`attributes :a, :b, :c` = 3) instead of just one per declaration line.
- `FileAnalyzer#find_view_files` dedupes overlapping glob matches so files under `app/views/` are no longer counted twice when matched by both `app/views/**/*.erb` and `app/**/views/**/*.erb`.
- `HealthCalculator` service/interactor/serializer penalties now use flat (un-weighted) multipliers for the most severe issues (missing call method, fat service, complex organizer, fat serializer) — the global `rails_conventions` weight (0.15) was too small to make these matter.

### Changed (may affect scores)
- Score changes are expected on any project where the above false positives or false negatives applied. Re-baseline before comparing to v0.2.0 reports.
- Services missing a `call` method now score noticeably lower (penalty went from ~0.45 to 3.0); same for interactors. Fat serializers and complex organizers are also penalized more strongly.

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

[Unreleased]: https://github.com/gkosmo/rails_code_health/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/gkosmo/rails_code_health/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/gkosmo/rails_code_health/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/gkosmo/rails_code_health/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/gkosmo/rails_code_health/releases/tag/v0.1.0
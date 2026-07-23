# Changelog

All notable changes to Trace are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Structured logging via `os.Logger` subsystems for sessions, database, summary, restore, and tracking
- Typed errors: `DatabaseError`, `RestoreError`, and `SummaryError`
- Service protocols: `ActivityTracking` and `SessionPersisting`
- Unit tests for `SnapshotDatabase` round-trip, incremental load, and prune
- Unit tests for `BundleRegistry` browser, chat, and terminal detection
- Doc comments on core domain types in `Models.swift` and `ContextContinuity`

### Changed
- `AppState` initializes the activity tracker without force-unwrapped optionals
- `SnapshotDatabase` uses `save` / `load` / `prune` naming aligned with `SessionPersisting`
- `SessionBuilder.projectFromPath` and `projectFromFileURL` are private; callers use `projectFromURL` or `buildSessions`
- Summary and restore failures are logged instead of failing silently

### Fixed
- Database initialization failures are logged to Console.app
- Timeline refresh and prune errors are logged instead of swallowed

## [0.1.0] - 2026-07-22

### Added
- Menu-bar timeline panel with session cards and stats view
- Polling-based activity tracking with Accessibility API context capture
- SQLite snapshot storage with retention pruning and VACUUM
- On-device session summaries via Apple Foundation Models with heuristic fallback
- Context continuity (focus score) metric in expanded session cards
- Session restore for apps, files, and browser tabs

[Unreleased]: https://github.com/amitshinde/Trace/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/amitshinde/Trace/releases/tag/v0.1.0

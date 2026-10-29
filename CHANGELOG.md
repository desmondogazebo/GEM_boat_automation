# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-29

### Added

- Tag-triggered GitHub Actions workflow that compiles `1batch.ahk` and `2batch.ahk` with Ahk2Exe and publishes `1batch.exe`, `2batch.exe` and `GameOCR.ps1` to a GitHub Release, using the matching section of this changelog as the release notes.

## [0.0.1] - 2026-10-29

### Added

- `1batch.ahk` and `2batch.ahk` AutoHotkey v2 scripts for assigning ships to trade routes.
- `GameOCR.ps1` Windows OCR helper used by both scripts.
- Sanitized Task Scheduler templates for the first- and second-batch launches.
- Precompiled `1batch.exe` and `2batch.exe` launchers.

[Unreleased]: https://github.com/desmondogazebo/GEM_boat_automation/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/desmondogazebo/GEM_boat_automation/compare/v0.0.1...v0.1.0
[0.0.1]: https://github.com/desmondogazebo/GEM_boat_automation/releases/tag/v0.0.1

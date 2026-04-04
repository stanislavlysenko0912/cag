# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added internal `AgentRegistry`, shared participant parser, and generic JSONL storage foundation for runner and persistence deduplication.

### Changed

- Refactored compare, consensus, and council runners and storage wrappers to share internal agent lookup and JSONL persistence infrastructure without changing CLI behavior.

### Fixed

- Fixed duplicated participant parsing paths to enforce the same validation and normalization rules across compare, consensus, and council models.

## [0.3.0] - 2026-04-04

### Added

- Added structured `AgentFailure` error model with exit reason, snippets, timeout metadata, and partial-output details.
- Added MCP prompts support — `cag_discuss` prompt for iterative dialogue with AI agents.
- Added `cag compare` for parallel multi-agent runs with persisted compare IDs and per-agent session IDs.
- Added `cag compare --list` and `cag compare --inspect` for browsing saved compare runs.
- Added persisted `cag council` runs with `council_id`, `--list`, and `--inspect`.
- Added `cag_compare` MCP tool.
- Added `make mcp-inspect` target for launching MCP Inspector against the cag server.

### Changed

- Changed agent execution to use unified error handling across direct runs, compare, consensus, council, and MCP responses.
- Changed CLI runner to enforce separate hard and idle timeouts instead of a single timeout value.
- Changed config schema and config loading to support `hard_timeout_seconds` and `idle_timeout_seconds`, with legacy timeout migration.
- Updated `cag prime` to document compare mode and compare follow-up flows.
- Changed MCP tool output defaults to compact CLI-like `result` strings with optional `verbose` expanded payloads.
- Reduced default MCP payload size for `cag_agent` and `cag_models`.
- Changed Claude model resolution to use explicit canonical model IDs with short aliases (`sonnet`, `opus`, `haiku`).
- Upgraded `mcp_dart` from 1.1.2 to 2.1.0 (MCP protocol `2025-11-25` support, fixes Inspector compatibility).

### Fixed

- Fixed parser and agent execution failures to return clearer, structured diagnostics instead of inconsistent ad-hoc errors.
- Fixed compare and council persistence to keep partial failures and failure context instead of collapsing on the first execution error.
- Fixed Gemini agent using `-s` (sandbox flag) instead of system prompt — Gemini CLI has no system prompt flag, now embeds instructions via XML tags in user prompt.
- Fixed Gemini agent missing `-p` flag for headless mode — without it, CLI could enter interactive mode instead of returning output.
- Fixed outdated `CLIRunner` test that still referenced removed shell wrapper API, restoring `fvm dart analyze` and `fvm dart test`.

## [0.2.1] - 2026-02-11

### Changed

- Updated GPT-5.3-Codex model to Codex.
- Added Composer 1.5 model to Cursor Agent.

## [0.2.0] - 2025-12-31

### Added

- Added Cursor Agent CLI integration.
- Added `cag detect` command to enable/disable agents based on installed CLIs.

### Changed

- Improved Windows support by resolving `.exe/.cmd/.bat` in PATH.

### Fixed

- Added a friendly Windows error hint for missing agent executables.
- Fixed custom `env` config replacing entire environment instead of merging with parent.

### Documentation

- Documented Windows `.cmd` example and optional WSL setup.

## [0.1.0] - 2025-12-30

### Added

- Initial version.

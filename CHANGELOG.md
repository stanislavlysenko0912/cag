# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.1] - 2026-05-29

### Changed

- Updated Claude Opus canonical model from `claude-opus-4-7` to `claude-opus-4-8` (alias `opus` unchanged).
- Updated curated Cursor front-tier Opus from `claude-opus-4-7-thinking-max` to `claude-opus-4-8-thinking-max`.
- Updated Cursor Composer models to `composer-2.5-fast` (default) and `composer-2.5`.
- Expanded curated Cursor model list and documented `cursor-agent models` for slug discovery.
- Temporarily disabled `antigravity` agent until AGY CLI reliably supports session resume.
- Documented Gemini CLI as deprecated and Antigravity as work in progress in README.

### Added

- Added `AntigravityAgent` and `AntigravityParser` to support the new Antigravity CLI (`agy`).
- Added `antigravity` command to the main CLI with support for `--print`, session resume, and system prompts; model selection uses AGY CLI's configured `/model` setting.
- Added internal `AgentRegistry`, shared participant parser, and generic JSONL storage foundation for runner and persistence deduplication.
- Added `cag consensus --inspect`, optional consensus titles, and JSON summary output for `cag consensus --list`.

### Changed

- Refactored compare, consensus, and council runners and storage wrappers to share internal agent lookup and JSONL persistence infrastructure without changing CLI behavior.
- Standardized persisted run/session browsing across compare, consensus, and council, including shared list formatting and stored consensus titles.
- Updated Codex default and mid-tier models to `gpt-5.5` and `gpt-5.5-mini`; shortened description for `gpt-5.3-codex`.

### Fixed

- Fixed duplicated participant parsing paths to enforce the same validation and normalization rules across compare, consensus, and council models.
- Fixed JSONL storage loading to skip malformed records with warnings instead of crashing on partial file corruption.
- Fixed config loading to warn and fall back on invalid content without overwriting broken config files, while only rewriting migrated configs after successful validation.
- Fixed `cag prime` to explain that single-agent runs use `cag <agent> -m <model>`, while `agent:model` syntax is only valid inside multi-agent flags such as `compare`, `consensus`, and `council`.
- Fixed `cag prime` to warn that stronger models may answer slowly and should not be retried just because they take longer.
- Fixed shared-workspace guidance in `cag prime` and `cag_discuss` so agents are told more explicitly that they run in the same `cwd` and should inspect files directly instead of retelling repository structure.
- Fixed dialogue guidance in `cag prime` and `cag_discuss` to push agents toward real multi-turn collaboration by default instead of stopping after a single answer.
- Fixed dialogue guidance to require follow-up rounds after the first useful answer and to tell caller agents not to pause on intermediate responses.

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

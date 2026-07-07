# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added the initial `--tui` entrypoint with a Nocterm-backed terminal UI shell.
- Added a global `Ctrl+C` shortcut to quit the `--tui` from any screen, including while editing custom model form fields; the hint is shown only on the main menu.
- Added TUI menu actions for status diagnostics and agent CLI detection.
- Added TUI model management for enabled agents, default model selection, and custom model creation.
- Added `cag doctor` for read-only setup diagnostics across config, enabled agents, executables, versions, hints, and optional MCP HTTP reachability.
- Added `antigravity` to `cag detect` and refreshed AGY model aliases.
- Added stdin/pipe prompt input for prompt-based CLI commands, allowing usage such as `git diff | cag codex "review this"`.
- Added MCP Task-backed `cag_agent` execution and the `cag_task` fallback tool for `mode: background`, with compact task resources, opt-in logs, non-graceful cancellation, and one-hour in-memory task retention.
- Added a `d` shortcut in the `--tui` agent detail view to set the highlighted model (standard or custom) as that agent's default; the `★` moves to it and it does not change the model's enabled state.
- Added structured model scores for cost, intelligence, speed, and taste across built-in CAG models.
- Added an `edited` tag on `--tui` built-in model rows whose definition (provider id, hint, scores, or aliases) is overridden by config, so config-level customization is visible at a glance.
- Added editable per-model routing scores (cost, intelligence, speed, taste, each 1-10) to the `--tui` custom model form as four optional, all-or-nothing fields.

### Changed

- Redesigned the `--tui` interface around a single, selection-driven interaction model: arrows or the mouse move a highlight, Enter opens the row, Space toggles it, and Esc goes back or quits. Every navigational action (Back, Add custom model) is now a highlighted row, and framed panels with titles replace the previous key-hint clutter.
- Replaced the `[x]`/`[ ]` toggle markers with a colored status dot so enabled and disabled agents and models read at a glance.
- Made the `--tui` Detect screen a preview: it now shows a diff of what applying detection would change and requires an explicit "Apply changes" action instead of writing config on open.
- Separated custom models from included models in the `--tui` model list, and made custom models editable and deletable from a dedicated form.
- Clarified the `--tui` custom model form with per-field guidance (name, optional hint, optional provider model); provider model and hint are now optional while name is required.
- Changed model guidance in `prime`, MCP, and the TUI from prose-first descriptions to comparable score columns with optional short hints and model-selection guidance.
- Reworked the `--tui` custom model form fields into single-line rows: labels sit in an aligned column, required fields are marked with a colored `*`, and per-field guidance now appears as in-field placeholder hints instead of a separate line.
- Refined `--tui` layout polish: aligned header with panel titles, added a title/subtitle separator, and gave panels consistent top spacing.
- Dropped the default model column from the `--tui` Status screen for a cleaner diagnostic list.
- Changed the `--tui` model list to hide the hint and scores on unselected rows and expand them into a fully labeled detail block (`cost N · intelligence N · speed N · taste N`) beneath the highlighted row, replacing the cryptic per-row abbreviation.
- Changed `--tui` error handling to show errors as an inline banner above the current screen instead of replacing the whole screen, so the view stays navigable (and mutation failures no longer discard the model list or form).
- Centralized platform-aware shell command construction in `CLIRunner`, keeping agent execution code focused on agent arguments.
- Improved MCP and `prime` guidance for `cag_agent` and `cag_models` so hosts know when to use them, when to prefer native tools, how IDs differ, and when to inspect model aliases.
- Removed Antigravity's `configured` model alias so CAG always passes an explicit AGY model.
- Renamed the built-in agent ID namespace to `AgentId` and reused it across implementation code.
- Moved the open `TODO.useful.md` backlog into the Linear CAG project.
- Synced refreshed `TODO.useful.md` research notes into the Linear CAG project.

### Fixed

- Fixed Antigravity CLI integration to pass model overrides, preserve explicit conversation resume IDs, and capture new conversation IDs from per-run AGY logs.
- Fixed CLI runner capturing agent stdout/stderr by streaming process output during execution, avoiding truncated JSON from Claude CLI and other agents on large responses (~192 KB+) without using temporary files for ordinary runs.
- Fixed Windows CLI runner argument handling so direct process execution no longer breaks quoted arguments such as `python -c` scripts or nested `cmd /c` commands.
- Restored Linux release artifact publishing and Homebrew formula checksum updates for the Linux installer flow.

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

import 'base_agent.dart';
import 'claude_agent.dart';
import 'codex_agent.dart';
import 'cursor_agent.dart';
import 'gemini_agent.dart';
import '../models/agent_config.dart';

/// Lazy registry for known CLI agents.
class AgentRegistry {
  /// Creates a registry with optional prebuilt agents.
  AgentRegistry({
    GeminiAgent? geminiAgent,
    CodexAgent? codexAgent,
    CursorAgent? cursorAgent,
    ClaudeAgent? claudeAgent,
    Map<String, AgentConfig> agentConfigs = const {},
  }) : _geminiAgent = geminiAgent,
       _codexAgent = codexAgent,
       _cursorAgent = cursorAgent,
       _claudeAgent = claudeAgent,
       _agentConfigs = agentConfigs;

  GeminiAgent? _geminiAgent;
  CodexAgent? _codexAgent;
  CursorAgent? _cursorAgent;
  ClaudeAgent? _claudeAgent;
  final Map<String, AgentConfig> _agentConfigs;

  /// Returns the agent instance for the given name.
  BaseAgent get(String agentName) {
    return switch (agentName) {
      'gemini' => _geminiAgent ??= GeminiAgent(config: _agentConfigs['gemini']),
      'codex' => _codexAgent ??= CodexAgent(config: _agentConfigs['codex']),
      'cursor' => _cursorAgent ??= CursorAgent(config: _agentConfigs['cursor']),
      'claude' => _claudeAgent ??= ClaudeAgent(config: _agentConfigs['claude']),
      _ => throw ArgumentError('Unknown agent: $agentName'),
    };
  }
}

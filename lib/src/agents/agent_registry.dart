import 'base_agent.dart';
import 'claude_agent.dart';
import 'codex_agent.dart';
import 'cursor_agent.dart';
import 'gemini_agent.dart';

/// Lazy registry for known CLI agents.
class AgentRegistry {
  /// Creates a registry with optional prebuilt agents.
  AgentRegistry({
    GeminiAgent? geminiAgent,
    CodexAgent? codexAgent,
    CursorAgent? cursorAgent,
    ClaudeAgent? claudeAgent,
  }) : _geminiAgent = geminiAgent,
       _codexAgent = codexAgent,
       _cursorAgent = cursorAgent,
       _claudeAgent = claudeAgent;

  GeminiAgent? _geminiAgent;
  CodexAgent? _codexAgent;
  CursorAgent? _cursorAgent;
  ClaudeAgent? _claudeAgent;

  /// Returns the agent instance for the given name.
  BaseAgent get(String agentName) {
    return switch (agentName) {
      'gemini' => _geminiAgent ??= GeminiAgent(),
      'codex' => _codexAgent ??= CodexAgent(),
      'cursor' => _cursorAgent ??= CursorAgent(),
      'claude' => _claudeAgent ??= ClaudeAgent(),
      _ => throw ArgumentError('Unknown agent: $agentName'),
    };
  }
}

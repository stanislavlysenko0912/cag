import 'agent_catalog.dart';
import 'base_agent.dart';
import 'antigravity_agent.dart';
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
    AntigravityAgent? antigravityAgent,
    Map<String, AgentConfig> agentConfigs = const {},
  }) : _agents = {
         if (geminiAgent != null) geminiAgent.name: geminiAgent,
         if (codexAgent != null) codexAgent.name: codexAgent,
         if (cursorAgent != null) cursorAgent.name: cursorAgent,
         if (claudeAgent != null) claudeAgent.name: claudeAgent,
         if (antigravityAgent != null) antigravityAgent.name: antigravityAgent,
       },
       _agentConfigs = agentConfigs;

  final Map<String, BaseAgent> _agents;
  final Map<String, AgentConfig> _agentConfigs;

  /// Returns the agent instance for the given name.
  BaseAgent get(String agentName) {
    final existing = _agents[agentName];
    if (existing != null) return existing;

    final definition = AgentCatalog.find(agentName);
    if (definition == null) {
      throw ArgumentError('Unknown agent: $agentName');
    }

    final agent = definition.createAgent(_agentConfigs[agentName]);
    _agents[agentName] = agent;
    return agent;
  }
}

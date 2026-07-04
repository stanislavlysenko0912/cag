import '../config/app_config.dart';
import '../config/config_service.dart';
import '../models/agent_config.dart';
import 'antigravity_agent.dart';
import 'base_agent.dart';
import 'claude_agent.dart';
import 'codex_agent.dart';
import 'cursor_agent.dart';
import 'gemini_agent.dart';
import 'known_agents.dart';

typedef AgentFactory = BaseAgent Function(AgentConfig? config);

class AgentDefinition {
  const AgentDefinition({
    required this.name,
    required this.displayName,
    required this.defaultConfig,
    required this.descriptionText,
    required this.systemHelp,
    required this.resumeHelp,
    required this.createAgent,
  });

  final String name;
  final String displayName;
  final AgentConfig defaultConfig;
  final String descriptionText;
  final String systemHelp;
  final String resumeHelp;
  final AgentFactory createAgent;

  String defaultModel(AgentConfig config) {
    return config.defaultModel ?? defaultConfig.defaultModel ?? 'configured';
  }
}

class AgentCatalog {
  AgentCatalog._();

  static final definitions = [
    AgentDefinition(
      name: KnownAgents.claude,
      displayName: 'Claude Code',
      defaultConfig: ClaudeAgent.defaultConfig,
      descriptionText: 'Run Claude CLI agent',
      systemHelp: 'System prompt (appended)',
      resumeHelp: 'Resume session (session_id)',
      createAgent: (config) => ClaudeAgent(config: config),
    ),
    AgentDefinition(
      name: KnownAgents.gemini,
      displayName: 'Gemini CLI',
      defaultConfig: GeminiAgent.defaultConfig,
      descriptionText: 'Run Gemini CLI agent',
      systemHelp: 'System prompt',
      resumeHelp: 'Resume session (session_id or "latest")',
      createAgent: (config) => GeminiAgent(config: config),
    ),
    AgentDefinition(
      name: KnownAgents.codex,
      displayName: 'Codex CLI',
      defaultConfig: CodexAgent.defaultConfig,
      descriptionText: 'Run Codex CLI agent',
      systemHelp: 'System prompt',
      resumeHelp: 'Resume session (thread_id)',
      createAgent: (config) => CodexAgent(config: config),
    ),
    AgentDefinition(
      name: KnownAgents.cursor,
      displayName: 'Cursor Agent CLI',
      defaultConfig: CursorAgent.defaultConfig,
      descriptionText: 'Run Cursor Agent CLI',
      systemHelp: 'System prompt (prepended to prompt)',
      resumeHelp: 'Resume session (session_id)',
      createAgent: (config) => CursorAgent(config: config),
    ),
    AgentDefinition(
      name: KnownAgents.antigravity,
      displayName: 'Antigravity CLI',
      defaultConfig: AntigravityAgent.defaultConfig,
      descriptionText: 'Run Antigravity CLI agent',
      systemHelp: 'System prompt',
      resumeHelp: 'Resume session (conversation_id)',
      createAgent: (config) => AntigravityAgent(config: config),
    ),
  ];

  static final names = definitions
      .map((definition) => definition.name)
      .toList(growable: false);

  static final defaultConfigs = {
    for (final definition in definitions)
      definition.name: definition.defaultConfig,
  };

  static AgentDefinition? find(String name) {
    for (final definition in definitions) {
      if (definition.name == name) return definition;
    }
    return null;
  }

  static Map<String, AgentConfig> resolveConfigs(
    ConfigService configService,
    AppConfig appConfig,
  ) {
    return {
      for (final definition in definitions)
        definition.name: configService.applyOverrides(
          definition.defaultConfig,
          configService.overridesFor(appConfig, definition.name),
        ),
    };
  }

  static List<String> enabledNames(Map<String, AgentConfig> configs) {
    return [
      for (final definition in definitions)
        if (configs[definition.name]?.enabled == true) definition.name,
    ];
  }

  static Map<String, BaseAgent> createEnabledAgents(
    Map<String, AgentConfig> configs,
  ) {
    return {
      for (final definition in definitions)
        if (configs[definition.name]?.enabled == true)
          definition.name: definition.createAgent(configs[definition.name]!),
    };
  }

  static String displayName(String name) {
    return find(name)?.displayName ?? name;
  }
}

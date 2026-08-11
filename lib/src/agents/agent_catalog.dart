import '../config/agent_config_override.dart';
import '../config/app_config.dart';
import '../config/config_service.dart';
import '../models/agent_config.dart';
import '../models/agent_model_discovery.dart';
import 'acp_agent.dart';
import 'agent_id.dart';
import 'antigravity_agent.dart';
import 'base_agent.dart';
import 'claude_agent.dart';
import 'codex_agent.dart';
import 'cursor_agent.dart';
import 'gemini_agent.dart';
import 'opencode_agent.dart';
import 'pi_agent.dart';

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
    this.adapter,
    this.isDetectionManaged = true,
    this.isModelDiscoveryEnabled = true,
  });

  final String name;
  final String displayName;
  final AgentConfig defaultConfig;
  final String descriptionText;
  final String systemHelp;
  final String resumeHelp;
  final AgentFactory createAgent;
  final String? adapter;

  /// Whether `cag detect` may update this agent's enabled state.
  final bool isDetectionManaged;

  /// Whether ACP model discovery may replace this agent's configured catalog.
  final bool isModelDiscoveryEnabled;

  String get adapterName => adapter ?? name;

  String? defaultModel(AgentConfig config) {
    return config.defaultModel ?? config.availableModels.firstOrNull?.name;
  }
}

class AgentCatalog {
  AgentCatalog._();

  static final _builtInDefinitions = [
    AgentDefinition(
      name: AgentId.claude,
      displayName: 'Claude Code',
      defaultConfig: ClaudeAgent.defaultConfig,
      descriptionText: 'Run Claude CLI agent',
      systemHelp: 'System prompt (appended)',
      resumeHelp: 'Resume session (session_id)',
      createAgent: (config) => ClaudeAgent(config: config),
    ),
    AgentDefinition(
      name: AgentId.gemini,
      displayName: 'Gemini CLI',
      defaultConfig: GeminiAgent.defaultConfig,
      descriptionText: 'Run Gemini CLI agent',
      systemHelp: 'System prompt',
      resumeHelp: 'Resume session (session_id or "latest")',
      createAgent: (config) => GeminiAgent(config: config),
    ),
    AgentDefinition(
      name: AgentId.codex,
      displayName: 'Codex CLI',
      defaultConfig: CodexAgent.defaultConfig,
      descriptionText: 'Run Codex CLI agent',
      systemHelp: 'System prompt',
      resumeHelp: 'Resume session (thread_id)',
      createAgent: (config) => CodexAgent(config: config),
    ),
    AgentDefinition(
      name: AgentId.cursor,
      adapter: AgentId.acp,
      displayName: 'Cursor Agent CLI',
      defaultConfig: CursorAgent.defaultConfig,
      descriptionText: 'Run Cursor Agent through ACP',
      systemHelp: 'System prompt (prepended to the first prompt)',
      resumeHelp: 'Resume Cursor ACP session (session_id)',
      createAgent: (config) => CursorAgent(config: config),
      isModelDiscoveryEnabled: false,
    ),
    AgentDefinition(
      name: AgentId.antigravity,
      displayName: 'Antigravity CLI',
      defaultConfig: AntigravityAgent.defaultConfig,
      descriptionText: 'Run Antigravity CLI agent',
      systemHelp: 'System prompt',
      resumeHelp: 'Resume session (conversation_id)',
      createAgent: (config) => AntigravityAgent(config: config),
    ),
    AgentDefinition(
      name: AgentId.opencode,
      adapter: AgentId.acp,
      displayName: 'OpenCode',
      defaultConfig: OpenCodeAgent.defaultConfig,
      descriptionText: 'Run OpenCode through ACP',
      systemHelp: 'System prompt (prepended to the first prompt)',
      resumeHelp: 'Resume OpenCode ACP session (session_id)',
      createAgent: (config) => OpenCodeAgent(config: config),
    ),
    AgentDefinition(
      name: AgentId.pi,
      displayName: 'Pi',
      defaultConfig: PiAgent.defaultConfig,
      descriptionText: 'Run Pi coding agent',
      systemHelp: 'System prompt (appended)',
      resumeHelp: 'Resume Pi session (session_id)',
      createAgent: (config) => PiAgent(config: config),
      isDetectionManaged: false,
    ),
  ];

  static final _adapterOnlyDefinitions = [
    AgentDefinition(
      name: AgentId.acp,
      displayName: 'ACP',
      defaultConfig: AcpAgent.defaultConfig,
      descriptionText: 'Run an ACP v1 agent',
      systemHelp: 'System prompt (prepended to the first prompt)',
      resumeHelp: 'Resume ACP session (session_id)',
      createAgent: (config) => AcpAgent(config: config),
    ),
  ];

  static List<AgentDefinition> _configuredDefinitions = const [];

  static List<AgentDefinition> get definitions => [
    ..._builtInDefinitions,
    ..._configuredDefinitions,
  ];

  static List<String> get names =>
      definitions.map((definition) => definition.name).toList(growable: false);

  static Map<String, AgentConfig> get defaultConfigs => {
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
    configure(appConfig);
    return {
      for (final definition in definitions)
        definition.name: configService.applyOverrides(
          definition.defaultConfig,
          configService.overridesFor(appConfig, definition.name),
        ),
    };
  }

  /// Discovers models from enabled ACP agents, preserving static fallback data.
  static Future<Map<String, AgentModelDiscovery>> discoverModels(
    Map<String, AgentConfig> configs, {
    StringSink? warningSink,
  }) async {
    final discoveries = <String, AgentModelDiscovery>{};
    await Future.wait([
      for (final definition in definitions)
        if (definition.adapterName == AgentId.acp &&
            definition.isModelDiscoveryEnabled &&
            configs[definition.name]?.enabled == true)
          () async {
            try {
              final agent = definition.createAgent(configs[definition.name]);
              if (agent is AcpAgent) {
                discoveries[definition.name] = await agent.discoverModels();
              }
            } on Object catch (error) {
              warningSink?.writeln(
                'Model discovery failed for ${definition.name}: $error',
              );
            }
          }(),
    ]);
    return discoveries;
  }

  /// Applies model discoveries to resolved runtime configurations.
  static Map<String, AgentConfig> applyModelDiscoveries(
    ConfigService configService,
    AppConfig appConfig,
    Map<String, AgentConfig> configs,
    Map<String, AgentModelDiscovery> discoveries,
  ) {
    final resolved = <String, AgentConfig>{};
    for (final entry in configs.entries) {
      final discovery = discoveries[entry.key];
      resolved[entry.key] = discovery == null
          ? entry.value
          : configService.applyModelDiscovery(
              entry.value,
              appConfig.agents[entry.key],
              discovery,
            );
    }
    return resolved;
  }

  static void configure(AppConfig config) {
    for (final entry in config.agents.entries) {
      if (findBuiltIn(entry.key) == null && entry.value.adapter == null) {
        throw StateError('Custom agent "${entry.key}" must define an adapter.');
      }
    }
    _configuredDefinitions = [
      for (final entry in config.agents.entries)
        if (findBuiltIn(entry.key) == null && entry.value.adapter != null)
          _customDefinition(entry.key, entry.value),
    ];
  }

  static AgentDefinition? findBuiltIn(String name) {
    for (final definition in _builtInDefinitions) {
      if (definition.name == name) return definition;
    }
    return null;
  }

  static AgentDefinition? findAdapter(String name) {
    return findBuiltIn(name) ??
        _adapterOnlyDefinitions
            .where((definition) => definition.name == name)
            .firstOrNull;
  }

  static AgentDefinition _customDefinition(
    String name,
    AgentConfigOverride override,
  ) {
    final adapter = findAdapter(override.adapter!);
    if (adapter == null) {
      throw StateError(
        'Unknown adapter "${override.adapter}" for agent "$name".',
      );
    }
    final base = adapter.defaultConfig;
    final defaultConfig = AgentConfig(
      name: name,
      executable: base.executable,
      parser: base.parser,
      defaultModel: override.defaultModel ?? base.defaultModel,
      additionalArgs: base.additionalArgs,
      env: base.env,
      hardTimeoutSeconds: base.hardTimeoutSeconds,
      idleTimeoutSeconds: base.idleTimeoutSeconds,
      shellExecutable: base.shellExecutable,
      shellArgs: base.shellArgs,
      shellCommandPrefix: base.shellCommandPrefix,
      settings: base.settings,
    );
    return AgentDefinition(
      name: name,
      adapter: adapter.name,
      displayName: override.displayName ?? name,
      defaultConfig: defaultConfig,
      descriptionText:
          override.description ??
          'Run $name through the ${adapter.name} adapter',
      systemHelp: adapter.systemHelp,
      resumeHelp: adapter.resumeHelp,
      createAgent: (config) => adapter.createAgent(config),
      isDetectionManaged: adapter.isDetectionManaged,
      isModelDiscoveryEnabled: adapter.isModelDiscoveryEnabled,
    );
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

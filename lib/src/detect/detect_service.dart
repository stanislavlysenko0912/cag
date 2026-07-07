import '../agents/agent_catalog.dart';
import '../config/agent_config_override.dart';
import '../config/app_config.dart';
import '../config/config_service.dart';
import '../utils/agent_executable_resolver.dart';
import '../utils/app_paths.dart';
import '../utils/executable_checker.dart';
import 'detect_result.dart';

/// Detects installed agent CLIs and updates config enablement.
class DetectService {
  /// Creates a detect service.
  DetectService({String? configPath, ConfigService? configService})
    : _configPath = configPath,
      _configService = configService ?? ConfigService(configPath: configPath);

  final String? _configPath;
  final ConfigService _configService;

  /// Detects agent executables, writes enablement to config, and returns rows.
  Future<DetectResult> detectAndSave() async {
    final config = await _configService.loadOrCreate();
    final detection = detect(config);
    await _configService.save(_applyDetection(config, detection));

    return DetectResult(
      agents: detection,
      configPath: _configPath ?? AppPaths.configPath(),
    );
  }

  /// Previews detection against the current config without writing anything.
  Future<DetectPreview> preview() async {
    final config = await _configService.loadOrCreate();
    final resolved = AgentCatalog.resolveConfigs(_configService, config);
    final detection = detect(config);

    return DetectPreview(
      rows: [
        for (final definition in AgentCatalog.definitions)
          DetectRow(
            name: definition.name,
            displayName: definition.displayName,
            available: detection[definition.name] ?? false,
            enabled: resolved[definition.name]?.enabled ?? false,
          ),
      ],
      configPath: _configPath ?? AppPaths.configPath(),
    );
  }

  /// Detects agent executable availability without writing config.
  Map<String, bool> detect(AppConfig config) {
    return {
      for (final definition in AgentCatalog.definitions)
        definition.name: isExecutableAvailable(
          resolveAgentExecutable(
            definition.defaultConfig,
            config.agents[definition.name],
          ),
        ),
    };
  }

  AppConfig _applyDetection(AppConfig config, Map<String, bool> detection) {
    final agents = Map<String, AgentConfigOverride>.from(config.agents);
    for (final entry in detection.entries) {
      agents[entry.key] = _mergeOverride(
        current: agents[entry.key],
        enabled: entry.value,
      );
    }
    return AppConfig(agents: agents);
  }

  AgentConfigOverride _mergeOverride({
    required AgentConfigOverride? current,
    required bool enabled,
  }) {
    return AgentConfigOverride(
      executable: current?.executable,
      enabled: enabled,
      defaultModel: current?.defaultModel,
      additionalArgs: current?.additionalArgs,
      env: current?.env,
      hardTimeoutSeconds: current?.hardTimeoutSeconds,
      idleTimeoutSeconds: current?.idleTimeoutSeconds,
      shellExecutable: current?.shellExecutable,
      shellArgs: current?.shellArgs,
      shellCommandPrefix: current?.shellCommandPrefix,
    );
  }
}

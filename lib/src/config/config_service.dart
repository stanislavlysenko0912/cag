import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';

import '../../gen/config_schema.dart';
import '../models/models.dart';
import '../utils/app_paths.dart';
import 'agent_config_override.dart';
import 'app_config.dart';

class ConfigService {
  ConfigService({String? configPath, StringSink? warningSink})
    : _configPath = configPath ?? AppPaths.configPath(),
      _warningSink = warningSink ?? stderr;

  final String _configPath;
  final StringSink _warningSink;

  Future<AppConfig> loadOrCreate() async {
    final file = File(_configPath);
    if (!await file.exists()) {
      final defaults = AppConfig.defaults();
      await _writeConfig(file, defaults);
      return defaults;
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      final defaults = AppConfig.defaults();
      await _writeConfig(file, defaults);
      return defaults;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      _warningSink.writeln('Config parse error: ${file.path}');
      return AppConfig.defaults();
    } on TypeError {
      _warningSink.writeln('Config parse error: ${file.path}');
      return AppConfig.defaults();
    }

    final migrated = _migrateLegacyConfig(json);
    final isValid = await _validateConfig(json);
    if (!isValid) {
      return AppConfig.defaults();
    }

    if (migrated) {
      await file.parent.create(recursive: true);
      final normalized = const JsonEncoder.withIndent('  ').convert(json);
      await file.writeAsString('$normalized\n');
    }

    return AppConfig.fromJson(json);
  }

  Future<void> save(AppConfig config) async {
    final file = File(_configPath);
    await _writeConfig(file, config);
  }

  AgentConfig applyOverrides(AgentConfig base, AgentConfigOverride? overrides) {
    if (overrides == null) {
      return AgentConfig(
        name: base.name,
        executable: base.executable,
        parser: base.parser,
        enabled: base.enabled,
        defaultModel: base.defaultModel,
        additionalArgs: base.additionalArgs,
        env: base.env,
        hardTimeoutSeconds: base.hardTimeoutSeconds,
        idleTimeoutSeconds: base.idleTimeoutSeconds,
        shellExecutable: base.shellExecutable,
        shellArgs: base.shellArgs,
        shellCommandPrefix: base.shellCommandPrefix,
        availableModels: AgentModelRegistry.modelsFor(base.name),
      );
    }

    final models = _mergeModels(
      AgentModelRegistry.modelsFor(base.name),
      overrides.models,
    );

    return AgentConfig(
      name: base.name,
      executable: overrides.executable ?? base.executable,
      parser: base.parser,
      enabled: overrides.enabled ?? base.enabled,
      defaultModel: overrides.defaultModel ?? base.defaultModel,
      additionalArgs: overrides.additionalArgs ?? base.additionalArgs,
      env: overrides.env ?? base.env,
      hardTimeoutSeconds:
          overrides.hardTimeoutSeconds ?? base.hardTimeoutSeconds,
      idleTimeoutSeconds:
          overrides.idleTimeoutSeconds ?? base.idleTimeoutSeconds,
      shellExecutable: overrides.shellExecutable ?? base.shellExecutable,
      shellArgs: overrides.shellArgs ?? base.shellArgs,
      shellCommandPrefix:
          overrides.shellCommandPrefix ?? base.shellCommandPrefix,
      availableModels: models,
    );
  }

  List<ModelConfig> _mergeModels(
    List<ModelConfig> base,
    List<ModelConfig>? overrides,
  ) {
    if (overrides == null || overrides.isEmpty) return base;

    final map = {for (final m in base) m.name: m};
    for (final override in overrides) {
      map[override.name] = override;
    }
    return map.values.toList();
  }

  AgentConfigOverride? overridesFor(AppConfig config, String agentName) {
    return config.agents[agentName];
  }

  Future<bool> _validateConfig(Map<String, dynamic> json) async {
    final schema = await _loadSchema();
    final result = schema.validate(json);
    if (!result.isValid) {
      _warningSink.writeln('Config validation failed at $_configPath:');
      for (final error in result.errors) {
        final path = error.instancePath.isNotEmpty ? error.instancePath : '\$';
        _warningSink.writeln('  - $path: ${error.message}');
      }
    }
    return result.isValid;
  }

  Future<JsonSchema> _loadSchema() async {
    final decoded = jsonDecode(configSchemaJson) as Map<String, dynamic>;
    return JsonSchema.create(decoded);
  }

  Future<void> _writeConfig(File file, AppConfig config) async {
    await file.parent.create(recursive: true);
    final json = const JsonEncoder.withIndent('  ').convert(config.toJson());
    await file.writeAsString('$json\n');
  }

  bool _migrateLegacyConfig(Map<String, dynamic> json) {
    final rawAgents = json['agents'];
    if (rawAgents is! Map<String, dynamic>) {
      return false;
    }

    var changed = false;
    for (final entry in rawAgents.entries) {
      final value = entry.value;
      if (value is! Map<String, dynamic>) {
        continue;
      }

      final legacyTimeout = value.remove('timeout_seconds');
      if (legacyTimeout is! int) {
        continue;
      }

      value.putIfAbsent('hard_timeout_seconds', () => legacyTimeout);
      value.putIfAbsent('idle_timeout_seconds', () => legacyTimeout);
      changed = true;
    }

    return changed;
  }
}

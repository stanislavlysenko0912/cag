import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';

import '../models/models.dart';
import '../utils/app_paths.dart';
import 'agent_config_override.dart';
import 'app_config.dart';
import 'package:cag/gen/config_schema.dart';

class ConfigService {
  Future<AppConfig> loadOrCreate() async {
    final file = File(AppPaths.configPath());
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
      stderr.writeln('Config parse error: ${file.path}');
      return AppConfig.defaults();
    }

    final isValid = await _validateConfig(json);
    if (!isValid) {
      return AppConfig.defaults();
    }

    return AppConfig.fromJson(json);
  }

  AgentConfig applyOverrides(AgentConfig base, AgentConfigOverride? overrides) {
    if (overrides == null) return base;

    return AgentConfig(
      name: base.name,
      executable: overrides.executable ?? base.executable,
      parser: base.parser,
      enabled: overrides.enabled ?? base.enabled,
      defaultModel: overrides.defaultModel ?? base.defaultModel,
      additionalArgs: overrides.additionalArgs ?? base.additionalArgs,
      env: overrides.env ?? base.env,
      timeoutSeconds: overrides.timeoutSeconds ?? base.timeoutSeconds,
      shellExecutable: overrides.shellExecutable ?? base.shellExecutable,
      shellArgs: overrides.shellArgs ?? base.shellArgs,
      shellCommandPrefix: overrides.shellCommandPrefix ?? base.shellCommandPrefix,
    );
  }

  AgentConfigOverride? overridesFor(AppConfig config, String agentName) {
    return config.agents[agentName];
  }

  Future<bool> _validateConfig(Map<String, dynamic> json) async {
    final schema = await _loadSchema();
    final result = schema.validate(json);
    if (!result.isValid) {
      stderr.writeln('Config validation failed at ${AppPaths.configPath()}:');
      for (final error in result.errors) {
        final path = error.instancePath.isNotEmpty ? error.instancePath : '\$';
        stderr.writeln('  - $path: ${error.message}');
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
}

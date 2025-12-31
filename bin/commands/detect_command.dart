import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';
import 'package:cag/src/config/agent_config_override.dart';
import 'package:cag/src/config/app_config.dart';
import 'package:cag/src/utils/app_paths.dart';
import 'package:cag/src/utils/executable_checker.dart';

class DetectCommand extends Command<void> {
  @override
  String get name => 'detect';

  @override
  String get description =>
      'Detect installed agent CLIs and update config enablement';

  @override
  Future<void> run() async {
    final configService = ConfigService();
    final config = await configService.loadOrCreate();

    final agents = <String, AgentConfig>{
      'claude': ClaudeAgent.defaultConfig,
      'gemini': GeminiAgent.defaultConfig,
      'codex': CodexAgent.defaultConfig,
      'cursor': CursorAgent.defaultConfig,
    };

    final detection = <String, bool>{};
    for (final entry in agents.entries) {
      final override = config.agents[entry.key];
      final executable = _resolveExecutable(entry.value, override);
      detection[entry.key] = isExecutableAvailable(executable);
    }

    final updated = _applyDetection(config, detection);
    await configService.save(updated);

    _printSummary(detection);
    stdout.writeln('Updated config: ${AppPaths.configPath()}');
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
      timeoutSeconds: current?.timeoutSeconds,
      shellExecutable: current?.shellExecutable,
      shellArgs: current?.shellArgs,
      shellCommandPrefix: current?.shellCommandPrefix,
    );
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

  String _resolveExecutable(AgentConfig base, AgentConfigOverride? override) {
    final shellPrefix = override?.shellCommandPrefix ?? base.shellCommandPrefix;
    if (shellPrefix != null && shellPrefix.trim().isNotEmpty) {
      return override?.shellExecutable ??
          base.shellExecutable ??
          _defaultShellExecutable();
    }
    return override?.executable ?? base.executable;
  }

  String _defaultShellExecutable() {
    return Platform.isWindows ? 'cmd' : '/bin/sh';
  }

  void _printSummary(Map<String, bool> detection) {
    stdout.writeln('Detected agents:');
    for (final entry in detection.entries) {
      final status = entry.value ? 'found' : 'missing';
      stdout.writeln('  - ${entry.key}: $status');
    }
  }
}

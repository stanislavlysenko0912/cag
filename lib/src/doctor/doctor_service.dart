import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';

import '../../gen/config_schema.dart';
import '../agents/agent_catalog.dart';
import '../config/app_config.dart';
import '../config/config_service.dart';
import '../models/agent_config.dart';
import '../runners/cli_runner.dart';
import '../utils/agent_executable_resolver.dart';
import '../utils/app_paths.dart';
import '../utils/executable_checker.dart';
import 'doctor_report.dart';

class DoctorService {
  Future<DoctorReport> inspect({String? mcpUrl}) async {
    final config = await _readConfig();
    final agents = await _inspectAgents(config.appConfig);
    final mcp = await _checkMcp(mcpUrl);
    final summary = _buildSummary(config, agents, mcp);

    return DoctorReport(
      config: config,
      agents: agents,
      mcp: mcp,
      summary: summary,
    );
  }

  Future<ConfigDiagnostic> _readConfig() async {
    final path = AppPaths.configPath();
    final file = File(path);
    if (!await file.exists()) {
      return ConfigDiagnostic(
        path: path,
        exists: false,
        valid: true,
        status: 'missing',
        appConfig: AppConfig.defaults(),
      );
    }

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) {
      return ConfigDiagnostic.invalid(
        path: path,
        error: 'Config file is empty.',
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException catch (error) {
      return ConfigDiagnostic.invalid(path: path, error: error.message);
    } on TypeError {
      return ConfigDiagnostic.invalid(
        path: path,
        error: 'Config root must be a JSON object.',
      );
    }

    final validationError = _validateConfig(json);
    if (validationError != null) {
      return ConfigDiagnostic.invalid(path: path, error: validationError);
    }

    return ConfigDiagnostic(
      path: path,
      exists: true,
      valid: true,
      status: 'ok',
      appConfig: AppConfig.fromJson(json),
    );
  }

  String? _validateConfig(Map<String, dynamic> json) {
    final decoded = jsonDecode(configSchemaJson) as Map<String, dynamic>;
    final schema = JsonSchema.create(decoded);
    final result = schema.validate(json);
    if (result.isValid) return null;

    return result.errors
        .map((error) {
          final path = error.instancePath.isNotEmpty
              ? error.instancePath
              : r'$';
          return '$path: ${error.message}';
        })
        .join('; ');
  }

  Future<List<AgentDiagnostic>> _inspectAgents(AppConfig appConfig) async {
    final configService = ConfigService();
    final diagnostics = <AgentDiagnostic>[];

    for (final definition in AgentCatalog.definitions) {
      final override = appConfig.agents[definition.name];
      final config = configService.applyOverrides(
        definition.defaultConfig,
        override,
      );
      final executable = resolveAgentExecutable(
        definition.defaultConfig,
        override,
      );
      final available = isExecutableAvailable(executable);
      final version = config.enabled && available
          ? await _detectVersion(config: config, executable: executable)
          : null;

      diagnostics.add(
        AgentDiagnostic(
          name: definition.name,
          enabled: config.enabled,
          executable: executable,
          available: available,
          version: version,
          status: _agentStatus(enabled: config.enabled, available: available),
          hint: _agentHint(
            name: definition.name,
            enabled: config.enabled,
            available: available,
            version: version,
          ),
        ),
      );
    }

    return diagnostics;
  }

  Future<String?> _detectVersion({
    required AgentConfig config,
    required String executable,
  }) async {
    final shellPrefix = config.shellCommandPrefix;
    final args = shellPrefix == null || shellPrefix.trim().isEmpty
        ? const ['--version']
        : _shellVersionArgs(config, shellPrefix);

    final result = await CLIRunner().run(
      executable: executable,
      args: args,
      env: config.env.isNotEmpty ? config.env : null,
      hardTimeout: const Duration(seconds: 2),
      idleTimeout: const Duration(seconds: 2),
    );

    return _firstOutputLine(result.stdout) ?? _firstOutputLine(result.stderr);
  }

  List<String> _shellVersionArgs(AgentConfig config, String shellPrefix) {
    if (config.shellArgs.isNotEmpty) {
      return [...config.shellArgs, '$shellPrefix --version'];
    }
    return Platform.isWindows
        ? ['/c', '$shellPrefix --version']
        : ['-c', '$shellPrefix --version'];
  }

  String? _firstOutputLine(String output) {
    for (final line in const LineSplitter().convert(output)) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String _agentStatus({required bool enabled, required bool available}) {
    if (!enabled) return 'disabled';
    return available ? 'found' : 'missing';
  }

  String? _agentHint({
    required String name,
    required bool enabled,
    required bool available,
    required String? version,
  }) {
    if (!enabled) return null;
    if (!available) {
      return 'Install ${AgentCatalog.displayName(name)} or set agents.$name.executable in config.';
    }
    if (_looksLikeAuthProblem(version)) {
      return 'Run the ${AgentCatalog.displayName(name)} CLI login/setup command and retry.';
    }
    return null;
  }

  bool _looksLikeAuthProblem(String? value) {
    if (value == null) return false;
    final normalized = value.toLowerCase();
    return normalized.contains('auth') ||
        normalized.contains('login') ||
        normalized.contains('sign in') ||
        normalized.contains('unauthorized');
  }

  Future<McpDiagnostic> _checkMcp(String? url) async {
    if (url == null || url.trim().isEmpty) {
      return const McpDiagnostic(checked: false);
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return McpDiagnostic(
        checked: true,
        url: url,
        reachable: false,
        error: 'Invalid URL.',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      await response.drain<void>();
      return McpDiagnostic(
        checked: true,
        url: url,
        reachable: response.statusCode < 500,
        statusCode: response.statusCode,
      );
    } on Object catch (error) {
      return McpDiagnostic(
        checked: true,
        url: url,
        reachable: false,
        error: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  DoctorSummary _buildSummary(
    ConfigDiagnostic config,
    List<AgentDiagnostic> agents,
    McpDiagnostic mcp,
  ) {
    var ok = config.valid ? 1 : 0;
    var warn = 0;
    var fail = config.valid ? 0 : 1;

    for (final agent in agents) {
      if (agent.enabled && !agent.available) {
        fail++;
      } else if (agent.hint != null) {
        warn++;
      } else {
        ok++;
      }
    }

    if (mcp.checked) {
      if (mcp.reachable == true) {
        ok++;
      } else {
        warn++;
      }
    }

    return DoctorSummary(ok: ok, warn: warn, fail: fail);
  }
}

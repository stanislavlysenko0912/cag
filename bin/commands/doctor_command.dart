import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/src/doctor/doctor.dart';

class DoctorCommand extends Command<void> {
  DoctorCommand() {
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print machine-readable diagnostics.',
      )
      ..addOption(
        'mcp-url',
        help: 'Optional MCP HTTP URL to probe with a cheap GET request.',
      );
  }

  @override
  String get name => 'doctor';

  @override
  String get description => 'Run read-only diagnostics for cag setup';

  @override
  Future<void> run() async {
    final report = await DoctorService().inspect(
      mcpUrl: argResults?['mcp-url'] as String?,
    );

    if (argResults?['json'] == true) {
      stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
    } else {
      _printReport(report);
    }

    if (report.summary.fail > 0) {
      exitCode = 1;
    }
  }

  void _printReport(DoctorReport report) {
    _printConfig(report.config);
    _printAgents(report.agents);
    _printHints(report.agents);
    _printMcp(report.mcp);
    stdout.writeln(
      'Summary: ${report.summary.ok} ok, ${report.summary.warn} warn, ${report.summary.fail} fail',
    );
  }

  void _printConfig(ConfigDiagnostic config) {
    stdout.writeln('Config: ${config.status} (${config.path})');
    if (config.error != null) {
      stdout.writeln('  ${config.error}');
    }
  }

  void _printAgents(List<AgentDiagnostic> agents) {
    stdout.writeln('Agents:');
    for (final agent in agents) {
      final enabled = agent.enabled ? 'enabled' : 'disabled';
      final version = agent.version ?? 'unknown';
      stdout.writeln(
        '  - ${agent.name}: $enabled, ${agent.status}, ${agent.executable}, version: $version',
      );
    }
  }

  void _printHints(List<AgentDiagnostic> agents) {
    final hints = agents
        .where((agent) => agent.hint != null)
        .map((agent) => '${agent.name}: ${agent.hint}')
        .toList();
    if (hints.isEmpty) return;

    stdout.writeln('Hints:');
    for (final hint in hints) {
      stdout.writeln('  - $hint');
    }
  }

  void _printMcp(McpDiagnostic mcp) {
    if (!mcp.checked) {
      stdout.writeln('MCP: skipped');
      return;
    }

    if (mcp.reachable == true) {
      stdout.writeln('MCP: reachable (${mcp.url}, HTTP ${mcp.statusCode})');
      return;
    }

    stdout.writeln('MCP: unreachable (${mcp.url})');
    if (mcp.error != null) {
      stdout.writeln('  ${mcp.error}');
    }
  }
}

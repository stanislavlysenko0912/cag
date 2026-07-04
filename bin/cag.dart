import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'commands/agent_command.dart';
import 'commands/compare_command.dart';
import 'commands/consensus_command.dart';
import 'commands/council_command.dart';
import 'commands/detect_command.dart';
import 'commands/doctor_command.dart';
import 'commands/mcp_command.dart';
import 'commands/prime_command.dart';

void main(List<String> args) async {
  if (_isDoctorCommand(args)) {
    await _runDoctor(args);
    return;
  }

  final configService = ConfigService();
  final config = await configService.loadOrCreate();
  final agentConfigs = AgentCatalog.resolveConfigs(configService, config);

  final runner = CommandRunner<void>('cag', 'CLI wrapper for AI agents')
    ..addCommand(ConsensusCommand(agentConfigs: agentConfigs))
    ..addCommand(CompareCommand(agentConfigs: agentConfigs))
    ..addCommand(CouncilCommand(agentConfigs: agentConfigs))
    ..addCommand(DetectCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(McpCommand())
    ..addCommand(PrimeCommand(agentConfigs: agentConfigs))
    ..argParser.addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Print version',
    );

  _addAgentCommands(runner, agentConfigs);

  try {
    final results = runner.argParser.parse(args);
    if (results['version'] as bool) {
      print('cag ${AppInfo.version}');
      return;
    }
    await runner.run(args);
  } on UsageException catch (e) {
    print(e);
    exit(64);
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}

void _addAgentCommands(
  CommandRunner<void> runner,
  Map<String, AgentConfig> agentConfigs,
) {
  for (final definition in AgentCatalog.definitions) {
    final config = agentConfigs[definition.name];
    if (config == null || !config.enabled) continue;

    runner.addCommand(
      AgentCommand(
        agentName: definition.name,
        descriptionText: definition.descriptionText,
        defaultModel: definition.defaultModel(config),
        agent: definition.createAgent(config),
        metaPrinter: _metaPrinterFor(definition.name),
        systemHelp: definition.systemHelp,
        resumeHelp: definition.resumeHelp,
      ),
    );
  }
}

MetaPrinter _metaPrinterFor(String agentName) {
  return switch (agentName) {
    KnownAgents.claude => printClaudeMeta,
    KnownAgents.gemini => printGeminiMeta,
    KnownAgents.codex => printCodexMeta,
    KnownAgents.cursor => printCursorMeta,
    KnownAgents.antigravity => printAntigravityMeta,
    _ => throw ArgumentError('Unknown agent: $agentName'),
  };
}

Future<void> _runDoctor(List<String> args) async {
  final runner = CommandRunner<void>('cag', 'CLI wrapper for AI agents')
    ..addCommand(DoctorCommand())
    ..argParser.addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Print version',
    );

  try {
    final results = runner.argParser.parse(args);
    if (results['version'] as bool) {
      print('cag ${AppInfo.version}');
      return;
    }
    await runner.run(args);
  } on UsageException catch (e) {
    print(e);
    exit(64);
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}

bool _isDoctorCommand(List<String> args) {
  for (final arg in args) {
    if (arg == '--') return false;
    if (arg.startsWith('-')) continue;
    return arg == 'doctor';
  }
  return false;
}

class AppInfo {
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'unknown',
  );
}

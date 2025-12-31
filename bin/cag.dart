import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'commands/agent_command.dart';
import 'commands/consensus_command.dart';
import 'commands/council_command.dart';
import 'commands/detect_command.dart';
import 'commands/mcp_command.dart';
import 'commands/prime_command.dart';

void main(List<String> args) async {
  final configService = ConfigService();
  final config = await configService.loadOrCreate();

  final claudeConfig = configService.applyOverrides(
    ClaudeAgent.defaultConfig,
    configService.overridesFor(config, 'claude'),
  );
  final geminiConfig = configService.applyOverrides(
    GeminiAgent.defaultConfig,
    configService.overridesFor(config, 'gemini'),
  );
  final codexConfig = configService.applyOverrides(
    CodexAgent.defaultConfig,
    configService.overridesFor(config, 'codex'),
  );
  final cursorConfig = configService.applyOverrides(
    CursorAgent.defaultConfig,
    configService.overridesFor(config, 'cursor'),
  );

  final agentConfigs = {
    'claude': claudeConfig,
    'gemini': geminiConfig,
    'codex': codexConfig,
    'cursor': cursorConfig,
  };
  final enabledAgents = agentConfigs.entries
      .where((entry) => entry.value.enabled)
      .map((entry) => entry.key)
      .toSet();

  final runner = CommandRunner<void>('cag', 'CLI wrapper for AI agents')
    ..addCommand(ConsensusCommand(enabledAgents: enabledAgents))
    ..addCommand(CouncilCommand(enabledAgents: enabledAgents))
    ..addCommand(DetectCommand())
    ..addCommand(McpCommand())
    ..addCommand(PrimeCommand(enabledAgents: enabledAgents))
    ..argParser.addFlag(
      'version',
      abbr: 'v',
      negatable: false,
      help: 'Print version',
    );

  if (claudeConfig.enabled) {
    runner.addCommand(
      AgentCommand(
        agentName: 'claude',
        descriptionText: 'Run Claude CLI agent',
        defaultModel:
            claudeConfig.defaultModel ??
            (AgentModelRegistry.defaultModelName('claude') ?? 'sonnet'),
        agent: ClaudeAgent(config: claudeConfig),
        metaPrinter: printClaudeMeta,
        systemHelp: 'System prompt (appended)',
        resumeHelp: 'Resume session (session_id)',
      ),
    );
  }
  if (geminiConfig.enabled) {
    runner.addCommand(
      AgentCommand(
        agentName: 'gemini',
        descriptionText: 'Run Gemini CLI agent',
        defaultModel:
            geminiConfig.defaultModel ??
            (AgentModelRegistry.defaultModelName('gemini') ??
                'gemini-3-flash-preview'),
        agent: GeminiAgent(config: geminiConfig),
        metaPrinter: printGeminiMeta,
        systemHelp: 'System prompt',
        resumeHelp: 'Resume session (session_id or "latest")',
      ),
    );
  }
  if (codexConfig.enabled) {
    runner.addCommand(
      AgentCommand(
        agentName: 'codex',
        descriptionText: 'Run Codex CLI agent',
        defaultModel:
            codexConfig.defaultModel ??
            (AgentModelRegistry.defaultModelName('codex') ?? 'gpt-5.2'),
        agent: CodexAgent(config: codexConfig),
        metaPrinter: printCodexMeta,
        systemHelp: 'System prompt',
        resumeHelp: 'Resume session (thread_id)',
      ),
    );
  }
  if (cursorConfig.enabled) {
    runner.addCommand(
      AgentCommand(
        agentName: 'cursor',
        descriptionText: 'Run Cursor Agent CLI',
        defaultModel:
            cursorConfig.defaultModel ??
            (AgentModelRegistry.defaultModelName('cursor') ?? 'composer-1'),
        agent: CursorAgent(config: cursorConfig),
        metaPrinter: printCursorMeta,
        systemHelp: 'System prompt (prepended to prompt)',
        resumeHelp: 'Resume session (session_id)',
      ),
    );
  }

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

class AppInfo {
  static const version = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'unknown',
  );
}

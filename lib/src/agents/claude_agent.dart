import 'dart:convert';

import '../models/models.dart';
import '../parsers/claude_parser.dart';
import '../runners/runners.dart';
import 'agent_id.dart';
import 'base_agent.dart';

/// Claude CLI agent.
class ClaudeAgent extends BaseAgent {
  ClaudeAgent({AgentConfig? config, ClaudeParser? parser})
    : super(config: config ?? _defaultConfig, parser: parser ?? ClaudeParser());

  static final defaultConfig = AgentConfig(
    name: AgentId.claude,
    executable: 'claude',
    parser: 'claude_json',
    defaultModel:
        AgentModelRegistry.defaultModelName(AgentId.claude) ?? 'sonnet',
    additionalArgs: ['--permission-mode', 'acceptEdits'],
    hardTimeoutSeconds: 1800,
    idleTimeoutSeconds: 900,
  );

  static final _defaultConfig = defaultConfig;

  @override
  List<String> buildArgs({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
    AgentRunContext? runContext,
  }) {
    final configuredArgs = _withoutTransportArgs(config.additionalArgs);
    final args = <String>['-p', '--output-format', 'json', ...configuredArgs];

    if (model != null) {
      args.addAll(['--model', model]);
    }

    if (systemPrompt != null) {
      args.addAll(['--system-prompt', systemPrompt]);
    }

    if (config.settings case final settings?) {
      args.addAll(['--settings', jsonEncode(settings)]);
    }

    if (resume != null) {
      args.addAll(['--resume', resume]);
    }

    if (extraArgs != null) {
      for (final entry in extraArgs.entries) {
        args.addAll([entry.key, entry.value]);
      }
    }

    args.add(prompt);

    return args;
  }

  List<String> _withoutTransportArgs(List<String> configuredArgs) {
    final result = <String>[];
    for (var index = 0; index < configuredArgs.length; index++) {
      final argument = configuredArgs[index];
      if (argument == '-p') continue;
      if (argument == '--output-format' && index + 1 < configuredArgs.length) {
        index++;
        continue;
      }
      result.add(argument);
    }
    return result;
  }

  @override
  ParsedResponse? recoverFromError(
    CLIResult result,
    AgentRunContext? runContext,
  ) {
    try {
      return parser!.parse(stdout: result.stdout, stderr: result.stderr);
    } catch (_) {
      return null;
    }
  }
}

import '../models/models.dart';
import '../parsers/pi_parser.dart';
import 'agent_id.dart';
import 'base_agent.dart';

/// Runs Pi in its non-interactive JSON event stream mode.
class PiAgent extends BaseAgent {
  PiAgent({AgentConfig? config, PiParser? parser})
    : super(config: config ?? defaultConfig, parser: parser ?? PiParser());

  static final defaultConfig = AgentConfig(
    name: AgentId.pi,
    executable: 'pi',
    parser: 'pi_jsonl',
    enabled: false,
  );

  @override
  bool get requiresModel => true;

  @override
  bool get allowsUnconfiguredModels => true;

  @override
  List<String> buildArgs({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
    AgentRunContext? runContext,
  }) {
    return [
      '--mode',
      'json',
      ..._withoutTransportArgs(config.additionalArgs),
      if (model != null) ...['--model', model],
      if (systemPrompt != null) ...['--append-system-prompt', systemPrompt],
      if (resume != null) ...['--session', resume],
      if (extraArgs != null)
        for (final entry in extraArgs.entries) ...[entry.key, entry.value],
      prompt,
    ];
  }

  List<String> _withoutTransportArgs(List<String> configuredArgs) {
    final result = <String>[];
    for (var index = 0; index < configuredArgs.length; index++) {
      final argument = configuredArgs[index];
      if (argument == '-p' || argument == '--print') continue;
      if (argument == '--mode' && index + 1 < configuredArgs.length) {
        index++;
        continue;
      }
      result.add(argument);
    }
    return result;
  }
}

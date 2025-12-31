import '../models/models.dart';
import '../parsers/cursor_parser.dart';
import 'base_agent.dart';

/// Cursor CLI agent.
class CursorAgent extends BaseAgent {
  CursorAgent({AgentConfig? config, CursorParser? parser})
    : super(config: config ?? _defaultConfig, parser: parser ?? CursorParser());

  static final defaultConfig = AgentConfig(
    name: 'cursor',
    executable: 'cursor-agent',
    parser: 'cursor_json',
    defaultModel: AgentModelRegistry.defaultModelName('cursor') ?? 'composer-1',
    additionalArgs: ['--print', '--output-format', 'json', '--force'],
    timeoutSeconds: 1800,
  );

  static final _defaultConfig = defaultConfig;

  @override
  List<String> buildArgs({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) {
    final args = <String>[...config.additionalArgs];

    if (model != null) {
      args.addAll(['--model', model]);
    }

    if (resume != null) {
      args.addAll(['--resume', resume]);
    }

    if (extraArgs != null) {
      for (final entry in extraArgs.entries) {
        args.addAll([entry.key, entry.value]);
      }
    }

    final combinedPrompt = _applySystemPrompt(
      prompt: prompt,
      systemPrompt: systemPrompt,
      hasResume: resume != null,
    );
    args.add(combinedPrompt);

    return args;
  }

  String _applySystemPrompt({
    required String prompt,
    required String? systemPrompt,
    required bool hasResume,
  }) {
    if (systemPrompt == null || systemPrompt.trim().isEmpty || hasResume) {
      return prompt;
    }

    return '<system>\n$systemPrompt\n</system>\n\n'
        '<user_main_prompt>\n$prompt\n</user_main_prompt>';
  }
}

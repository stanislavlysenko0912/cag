import '../models/models.dart';
import '../parsers/claude_parser.dart';
import '../runners/runners.dart';
import 'base_agent.dart';

/// Claude CLI agent.
class ClaudeAgent extends BaseAgent {
  ClaudeAgent({AgentConfig? config, ClaudeParser? parser})
    : super(config: config ?? _defaultConfig, parser: parser ?? ClaudeParser());

  static final defaultConfig = AgentConfig(
    name: 'claude',
    executable: 'claude',
    parser: 'claude_json',
    defaultModel: AgentModelRegistry.defaultModelName('claude') ?? 'sonnet',
    additionalArgs: [
      '-p',
      '--output-format',
      'json',
      '--permission-mode',
      'acceptEdits',
    ],
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
    final args = <String>[
      '-p',
      '--output-format',
      'json',
      '--permission-mode',
      'acceptEdits',
    ];

    if (model != null) {
      args.addAll(['--model', model]);
    }

    if (systemPrompt != null) {
      args.addAll(['--system-prompt', systemPrompt]);
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

  @override
  ParsedResponse? recoverFromError(CLIResult result) {
    try {
      return parser.parse(stdout: result.stdout, stderr: result.stderr);
    } catch (_) {
      return null;
    }
  }
}

import '../models/models.dart';
import '../parsers/codex_parser.dart';
import '../runners/runners.dart';
import 'base_agent.dart';

/// Codex CLI agent.
class CodexAgent extends BaseAgent {
  CodexAgent({AgentConfig? config, CodexParser? parser})
    : super(config: config ?? _defaultConfig, parser: parser ?? CodexParser());

  static final defaultConfig = AgentConfig(
    name: 'codex',
    executable: 'codex',
    parser: 'codex_jsonl',
    defaultModel: AgentModelRegistry.defaultModelName('codex') ?? 'gpt-5.2',
    additionalArgs: [
      '--dangerously-bypass-approvals-and-sandbox',
      '--search',
      'exec',
      '--json',
      '--skip-git-repo-check',
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
    final args = <String>[...config.additionalArgs];

    if (model != null) {
      args.addAll(['-m', model]);
    }

    if (systemPrompt != null) {
      // codex uses -c developer_instructions for custom instructions
      args.addAll(['-c', 'developer_instructions=$systemPrompt']);
    }

    if (extraArgs != null) {
      for (final entry in extraArgs.entries) {
        args.addAll([entry.key, entry.value]);
      }
    }

    if (resume != null) {
      // codex exec resume <session_id> <prompt>
      args.addAll(['resume', resume, prompt]);
    } else {
      args.add(prompt);
    }

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

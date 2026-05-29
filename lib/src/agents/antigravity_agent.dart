import '../models/models.dart';
import '../parsers/parsers.dart';
import '../runners/runners.dart';
import 'base_agent.dart';

// TODO(stanislav): Re-enable antigravity when AGY CLI reliably supports session resume.
/// Antigravity CLI agent (successor to Gemini CLI).
class AntigravityAgent extends BaseAgent {
  AntigravityAgent({AgentConfig? config, AntigravityParser? parser})
    : super(
        config: config ?? _defaultConfig,
        parser: parser ?? AntigravityParser(),
      );

  static final defaultConfig = AgentConfig(
    name: 'antigravity',
    enabled: false,
    executable: 'agy',
    parser: 'antigravity',
    defaultModel:
        AgentModelRegistry.defaultModelName('antigravity') ?? 'configured',
    additionalArgs: ['--print', '--dangerously-skip-permissions'],
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
  }) {
    final args = <String>[...config.additionalArgs];

    // AGY model selection is controlled by /model or persisted settings.
    // The current CLI rejects --model in print mode.
    if (resume != null) {
      args.addAll(['--conversation', resume]);
    }

    if (extraArgs != null) {
      for (final entry in extraArgs.entries) {
        args.addAll([entry.key, entry.value]);
      }
    }

    final finalPrompt = _applySystemPrompt(prompt, systemPrompt);
    args.add(finalPrompt);

    return args;
  }

  String _applySystemPrompt(String prompt, String? systemPrompt) {
    if (systemPrompt == null || systemPrompt.trim().isEmpty) {
      return prompt;
    }
    return '<system_instructions>\n$systemPrompt\n</system_instructions>\n\n$prompt';
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

import '../models/models.dart';
import '../parsers/parsers.dart';
import '../runners/runners.dart';

/// Base class for CLI agents.
abstract class BaseAgent {
  BaseAgent({required this.config, required this.parser, CLIRunner? runner})
    : runner = runner ?? CLIRunner();

  final AgentConfig config;
  final BaseParser parser;
  final CLIRunner runner;

  /// Agent name.
  String get name => config.name;

  /// Build CLI arguments for the prompt.
  List<String> buildArgs({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  });

  /// Try to recover a response from CLI error output.
  /// Override in subclasses to handle specific error formats.
  ParsedResponse? recoverFromError(CLIResult result) => null;

  /// Execute the agent with the given prompt.
  Future<ParsedResponse> execute({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) async {
    final args = buildArgs(
      prompt: prompt,
      model: model ?? config.defaultModel,
      systemPrompt: systemPrompt,
      resume: resume,
      extraArgs: extraArgs,
    );

    final result = await _runCommand(args);

    if (!result.success) {
      final recovered = recoverFromError(result);
      if (recovered != null) return recovered;

      throw CLIRunnerException(
        '${config.name} CLI failed',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }

    return parser.parse(stdout: result.stdout, stderr: result.stderr);
  }

  Future<CLIResult> _runCommand(List<String> args) {
    final timeout = Duration(seconds: config.timeoutSeconds);
    ShellConfig? shellConfig;
    if (config.shellCommandPrefix != null) {
      shellConfig = ShellConfig(
        commandPrefix: config.shellCommandPrefix!,
        shellExecutable: config.shellExecutable,
        shellArgs: config.shellArgs,
      );
    }

    return runner.run(
      executable: config.executable,
      args: args,
      env: config.env.isNotEmpty ? config.env : null,
      timeout: timeout,
      shellConfig: shellConfig,
    );
  }
}

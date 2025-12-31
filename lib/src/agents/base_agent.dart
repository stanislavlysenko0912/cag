import 'dart:io';

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
    if (config.shellCommandPrefix == null) {
      return runner.run(
        executable: config.executable,
        args: args,
        env: config.env.isNotEmpty ? config.env : null,
        timeout: timeout,
      );
    }

    final shellExecutable = config.shellExecutable ?? _defaultShellExecutable();
    final shellArgs = config.shellArgs.isNotEmpty
        ? config.shellArgs
        : _defaultShellArgs(shellExecutable);
    final command = _buildShellCommand(
      config.shellCommandPrefix!,
      args,
      shellExecutable,
    );

    return runner.run(
      executable: shellExecutable,
      args: [...shellArgs, command],
      env: config.env.isNotEmpty ? config.env : null,
      timeout: timeout,
    );
  }

  String _buildShellCommand(
    String prefix,
    List<String> args,
    String shellExecutable,
  ) {
    final escapedArgs = args
        .map((arg) => _shellEscape(arg, shellExecutable))
        .join(' ');
    final trimmedPrefix = prefix.trim();
    if (escapedArgs.isEmpty) return trimmedPrefix;
    return '$trimmedPrefix $escapedArgs';
  }

  String _shellEscape(String value, String shellExecutable) {
    final lower = shellExecutable.toLowerCase();
    if (lower.contains('cmd')) {
      final escaped = value.replaceAll('"', '\\"');
      return '"$escaped"';
    }
    final escaped = value.replaceAll("'", "'\\''");
    return "'$escaped'";
  }

  String _defaultShellExecutable() {
    if (Platform.isWindows) return 'cmd';
    return '/bin/sh';
  }

  List<String> _defaultShellArgs(String shellExecutable) {
    final lower = shellExecutable.toLowerCase();
    if (lower.contains('cmd')) return ['/c'];
    return ['-c'];
  }
}

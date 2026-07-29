import '../models/models.dart';
import '../parsers/parsers.dart';
import '../runners/runners.dart';

/// Per-execution state prepared by an agent before it builds CLI arguments.
class AgentRunContext {
  const AgentRunContext();
}

/// Parsed agent response with raw execution details.
class AgentDetailedExecution {
  const AgentDetailedExecution({required this.response, required this.result});

  /// Parsed response.
  final ParsedResponse response;

  /// Raw CLI execution result.
  final CLIResult result;
}

/// Base class for CLI agents.
abstract class BaseAgent {
  BaseAgent({required this.config, this.parser, CLIRunner? runner})
    : runner = runner ?? CLIRunner();

  final AgentConfig config;
  final BaseParser? parser;
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
    AgentRunContext? runContext,
  });

  /// Prepare per-run resources before CLI arguments are built.
  Future<AgentRunContext?> prepareRun({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) async {
    return null;
  }

  /// Parse CLI output into a normalized response.
  ParsedResponse parseResponse(CLIResult result, AgentRunContext? runContext) {
    final responseParser = parser;
    if (responseParser == null) {
      throw ParserException('${config.name} does not define an output parser.');
    }
    return responseParser.parse(stdout: result.stdout, stderr: result.stderr);
  }

  /// Clean up per-run resources.
  Future<void> cleanupRun(AgentRunContext? runContext) async {}

  /// Try to recover a response from CLI error output.
  /// Override in subclasses to handle specific error formats.
  ParsedResponse? recoverFromError(
    CLIResult result,
    AgentRunContext? runContext,
  ) => null;

  /// Execute the agent with the given prompt.
  Future<ParsedResponse> execute({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) async {
    final execution = await executeDetailed(
      prompt: prompt,
      model: model,
      systemPrompt: systemPrompt,
      resume: resume,
      extraArgs: extraArgs,
    );
    return execution.response;
  }

  /// Execute the agent and retain raw execution details.
  Future<AgentDetailedExecution> executeDetailed({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) async {
    final resolvedModel = model ?? config.defaultModel;
    final runContext = await prepareRun(
      prompt: prompt,
      model: resolvedModel,
      systemPrompt: systemPrompt,
      resume: resume,
      extraArgs: extraArgs,
    );

    try {
      final args = buildArgs(
        prompt: prompt,
        model: resolvedModel,
        systemPrompt: systemPrompt,
        resume: resume,
        extraArgs: extraArgs,
        runContext: runContext,
      );

      final result = await _runCommand(
        args,
        environment: config.environmentFor(resolvedModel),
        workingDirectory: workingDirectory,
        onProcessStarted: onProcessStarted,
        keepCapture: keepCapture,
      );

      if (!result.success) {
        final recovered = recoverFromError(result, runContext);
        if (recovered != null) {
          return AgentDetailedExecution(
            response: _attachExecutionMetadata(recovered, result),
            result: result,
          );
        }
        throw AgentExecutionException(result.failure!, result: result);
      }

      try {
        final response = parseResponse(result, runContext);
        if (response.content.trim().isEmpty) {
          final failure = AgentFailure(
            reason: AgentExitReason.emptyResponse,
            message: '${config.name} returned an empty response.',
            exitCode: result.exitCode,
            stdoutSnippet: _snippet(result.stdout),
            stderrSnippet: _snippet(result.stderr),
            durationMs: result.durationMs,
            hadPartialOutput:
                result.stdout.trim().isNotEmpty ||
                result.stderr.trim().isNotEmpty,
          );
          throw AgentExecutionException(failure, result: result);
        }
        return AgentDetailedExecution(
          response: _attachExecutionMetadata(response, result),
          result: result,
        );
      } on ParserException catch (error) {
        final failure = AgentFailure(
          reason: error.reason,
          message: error.message,
          exitCode: result.exitCode,
          stdoutSnippet: _snippet(result.stdout),
          stderrSnippet: _snippet(result.stderr),
          durationMs: result.durationMs,
          hadPartialOutput:
              result.stdout.trim().isNotEmpty ||
              result.stderr.trim().isNotEmpty,
        );
        throw AgentExecutionException(failure, result: result);
      }
    } finally {
      await cleanupRun(runContext);
    }
  }

  Future<CLIResult> _runCommand(
    List<String> args, {
    required Map<String, String> environment,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) {
    final hardTimeout = Duration(seconds: config.hardTimeoutSeconds);
    final idleTimeout = Duration(seconds: config.idleTimeoutSeconds);
    final command = ProcessCommand.forAgent(config, args);

    return runner.run(
      executable: command.executable,
      args: command.args,
      env: environment.isNotEmpty ? environment : null,
      hardTimeout: hardTimeout,
      idleTimeout: idleTimeout,
      workingDirectory: workingDirectory,
      onProcessStarted: onProcessStarted,
      keepCapture: keepCapture,
    );
  }

  ParsedResponse _attachExecutionMetadata(
    ParsedResponse response,
    CLIResult result,
  ) {
    return ParsedResponse(
      content: response.content,
      metadata: {...response.metadata, 'duration_ms': result.durationMs},
    );
  }

  String? _snippet(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= 400) {
      return trimmed;
    }
    return '${trimmed.substring(0, 400)}...';
  }
}

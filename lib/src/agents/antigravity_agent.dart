import 'dart:io';

import '../models/models.dart';
import '../parsers/parsers.dart';
import '../runners/runners.dart';
import 'base_agent.dart';

/// Antigravity CLI agent (successor to Gemini CLI).
class AntigravityAgent extends BaseAgent {
  AntigravityAgent({
    AgentConfig? config,
    AntigravityParser? parser,
    super.runner,
  }) : super(
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
    AgentRunContext? runContext,
  }) {
    final args = <String>[
      for (final arg in config.additionalArgs)
        if (!_isPrintFlag(arg)) arg,
    ];

    args.addAll(['--print-timeout', '${config.hardTimeoutSeconds}s']);

    if (_shouldPassModel(model)) {
      args.addAll(['--model', model!]);
    }

    if (resume != null) {
      args.addAll(['--conversation', resume]);
    } else if (runContext is _AntigravityRunContext) {
      final logFile = runContext.logFile;
      if (logFile != null) {
        args.addAll(['--log-file', logFile.path]);
      }
    }

    if (extraArgs != null) {
      for (final entry in extraArgs.entries) {
        args.addAll([entry.key, entry.value]);
      }
    }

    final finalPrompt = _applySystemPrompt(prompt, systemPrompt);
    args.addAll(['--print', finalPrompt]);

    return args;
  }

  @override
  Future<AgentRunContext?> prepareRun({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
  }) async {
    if (resume != null) {
      return _AntigravityRunContext(resume: resume);
    }

    final directory = await Directory.systemTemp.createTemp('cag_agy_');
    return _AntigravityRunContext(
      logDirectory: directory,
      logFile: File('${directory.path}/agy.log'),
    );
  }

  @override
  ParsedResponse parseResponse(CLIResult result, AgentRunContext? runContext) {
    final response = parser.parse(stdout: result.stdout, stderr: result.stderr);
    if (runContext is! _AntigravityRunContext) {
      return response;
    }

    final sessionId =
        runContext.resume ??
        (runContext.logFile == null
            ? null
            : _extractConversationId(runContext.logFile!));
    if (sessionId == null) {
      return response;
    }

    return ParsedResponse(
      content: response.content,
      metadata: {...response.metadata, 'session_id': sessionId},
    );
  }

  @override
  Future<void> cleanupRun(AgentRunContext? runContext) async {
    if (runContext is! _AntigravityRunContext) {
      return;
    }
    final directory = runContext.logDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  String _applySystemPrompt(String prompt, String? systemPrompt) {
    if (systemPrompt == null || systemPrompt.trim().isEmpty) {
      return prompt;
    }
    return '<system_instructions>\n$systemPrompt\n</system_instructions>\n\n$prompt';
  }

  @override
  ParsedResponse? recoverFromError(
    CLIResult result,
    AgentRunContext? runContext,
  ) {
    try {
      return parseResponse(result, runContext);
    } catch (_) {
      return null;
    }
  }

  bool _shouldPassModel(String? model) {
    if (model == null) return false;
    return !const {'configured', 'current', 'default'}.contains(model);
  }

  bool _isPrintFlag(String arg) {
    return const {'--print', '-p', '--prompt'}.contains(arg);
  }

  String? _extractConversationId(File logFile) {
    if (!logFile.existsSync()) {
      return null;
    }

    final content = logFile.readAsStringSync();
    final patterns = [
      RegExp(r'Created conversation ([a-fA-F0-9-]{36})'),
      RegExp(r'Print mode: conversation=([a-fA-F0-9-]{36})'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(content).toList();
      if (matches.isNotEmpty) {
        return matches.last.group(1);
      }
    }
    return null;
  }
}

class _AntigravityRunContext extends AgentRunContext {
  _AntigravityRunContext({this.resume, this.logDirectory, this.logFile});

  final String? resume;
  final Directory? logDirectory;
  final File? logFile;
}

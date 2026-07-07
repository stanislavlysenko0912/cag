import 'dart:convert';

import '../models/models.dart';
import '../parsers/parsers.dart';
import '../runners/runners.dart';
import 'agent_id.dart';
import 'base_agent.dart';

/// Gemini CLI agent.
class GeminiAgent extends BaseAgent {
  GeminiAgent({AgentConfig? config, GeminiParser? parser})
    : super(config: config ?? _defaultConfig, parser: parser ?? GeminiParser());

  static final defaultConfig = AgentConfig(
    name: AgentId.gemini,
    executable: 'gemini',
    parser: 'gemini_json',
    defaultModel:
        AgentModelRegistry.defaultModelName(AgentId.gemini) ??
        'gemini-3-flash-preview',
    additionalArgs: ['-o', 'json', '--yolo'],
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
    final args = <String>[...config.additionalArgs];

    if (model != null) {
      args.addAll(['-m', model]);
    }

    if (resume != null) {
      args.addAll(['-r', resume]);
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
    args.addAll(['-p', combinedPrompt]);

    return args;
  }

  /// Embeds system prompt into the user prompt via XML tags.
  ///
  /// Gemini CLI has no dedicated system prompt flag, so instructions
  /// are inlined as structured context within the user prompt.
  String _applySystemPrompt({
    required String prompt,
    required String? systemPrompt,
    required bool hasResume,
  }) {
    if (systemPrompt == null || systemPrompt.trim().isEmpty || hasResume) {
      return prompt;
    }

    return '<system_instructions>\n$systemPrompt\n</system_instructions>\n\n'
        '$prompt';
  }

  @override
  ParsedResponse? recoverFromError(
    CLIResult result,
    AgentRunContext? runContext,
  ) {
    final combined = [
      result.stderr,
      result.stdout,
    ].where((s) => s.isNotEmpty).join('\n');
    if (combined.isEmpty) return null;

    final braceIndex = combined.indexOf('{');
    if (braceIndex == -1) return null;

    final jsonCandidate = combined.substring(braceIndex);
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(jsonCandidate) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }

    final errorBlock = payload['error'];
    if (errorBlock is! Map<String, dynamic>) return null;

    final code = errorBlock['code'];
    final errType = errorBlock['type'];
    final detailMessage = errorBlock['message'] as String?;

    final prologue = combined.substring(0, braceIndex).trim();
    final lines = <String>[];
    if (prologue.isNotEmpty &&
        (detailMessage == null || !detailMessage.contains(prologue))) {
      lines.add(prologue);
    }
    if (detailMessage != null) {
      lines.add(detailMessage);
    }

    var header = 'Gemini CLI reported a tool failure';
    if (code != null) {
      header = '$header ($code)';
    } else if (errType != null) {
      header = '$header ($errType)';
    }

    final contentLines = [
      '${header.replaceAll(RegExp(r'\.$'), '')}.',
      ...lines,
    ];
    final message = contentLines.join('\n').trim();

    return ParsedResponse(
      content: message.isNotEmpty ? message : header,
      metadata: {
        'cli_error_recovered': true,
        'cli_error_code': code,
        'cli_error_type': errType,
        'cli_error_payload': payload,
      },
    );
  }
}

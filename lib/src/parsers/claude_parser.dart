import 'dart:convert';

import '../models/models.dart';
import 'base_parser.dart';

/// Parser for Claude CLI JSON output (`--output-format json`).
class ClaudeParser extends BaseParser {
  @override
  String get name => 'claude_json';

  @override
  ParsedResponse parse({required String stdout, required String stderr}) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) {
      throw ParserException('Claude CLI returned empty stdout');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      throw ParserException('Failed to decode Claude CLI JSON: $e');
    }

    final List<Map<String, dynamic>> events;
    if (decoded is List) {
      events = decoded.whereType<Map<String, dynamic>>().toList();
    } else if (decoded is Map<String, dynamic>) {
      events = [decoded];
    } else {
      throw ParserException('Unexpected Claude CLI JSON payload');
    }

    if (events.isEmpty) {
      throw ParserException('Claude CLI JSON array is empty');
    }

    final resultEvent = events.firstWhere(
      (e) => e['type'] == 'result',
      orElse: () => <String, dynamic>{},
    );

    final assistantEvent = events.lastWhere(
      (e) => e['type'] == 'assistant',
      orElse: () => <String, dynamic>{},
    );

    final sessionId = _extractSessionId(events);
    final content = _extractContent(resultEvent, assistantEvent);
    final metadata = _buildMetadata(
      resultEvent: resultEvent,
      assistantEvent: assistantEvent,
      sessionId: sessionId,
      stderr: stderr,
    );

    if (content.isEmpty) {
      final stderrText = stderr.trim();
      if (stderrText.isNotEmpty) {
        return ParsedResponse(
          content: 'Claude CLI returned no result. Check stderr.',
          metadata: {...metadata, 'stderr': stderrText},
        );
      }
      throw ParserException('Claude CLI response has no textual result');
    }

    return ParsedResponse(content: content, metadata: metadata);
  }

  String? _extractSessionId(List<Map<String, dynamic>> events) {
    for (final event in events) {
      final sid = event['session_id'];
      if (sid is String && sid.isNotEmpty) return sid;
    }
    return null;
  }

  String _extractContent(
    Map<String, dynamic> resultEvent,
    Map<String, dynamic> assistantEvent,
  ) {
    final result = resultEvent['result'];
    if (result is String && result.trim().isNotEmpty) {
      return result.trim();
    }
    if (result is List) {
      final joined = result
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join('\n');
      if (joined.isNotEmpty) return joined;
    }

    final message = assistantEvent['message'];
    if (message is Map<String, dynamic>) {
      final content = message['content'];
      if (content is List) {
        final texts = content
            .whereType<Map<String, dynamic>>()
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'])
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join('\n');
        if (texts.isNotEmpty) return texts;
      }
    }

    return '';
  }

  Map<String, dynamic> _buildMetadata({
    required Map<String, dynamic> resultEvent,
    required Map<String, dynamic> assistantEvent,
    required String? sessionId,
    required String stderr,
  }) {
    final metadata = <String, dynamic>{};

    if (sessionId != null) {
      metadata['session_id'] = sessionId;
    }

    final isError = resultEvent['is_error'];
    if (isError == true) {
      metadata['is_error'] = true;
    }

    final durationMs = resultEvent['duration_ms'];
    if (durationMs is num) {
      metadata['duration_ms'] = durationMs;
    }

    final durationApiMs = resultEvent['duration_api_ms'];
    if (durationApiMs is num) {
      metadata['duration_api_ms'] = durationApiMs;
    }

    final usage = resultEvent['usage'];
    if (usage is Map<String, dynamic>) {
      metadata['usage'] = usage;
    }

    final modelUsage = resultEvent['modelUsage'];
    if (modelUsage is Map<String, dynamic> && modelUsage.isNotEmpty) {
      metadata['model_usage'] = modelUsage;
      metadata['model_used'] = modelUsage.keys.first;
    }

    final totalCost = resultEvent['total_cost_usd'];
    if (totalCost is num) {
      metadata['total_cost_usd'] = totalCost;
    }

    final stderrText = stderr.trim();
    if (stderrText.isNotEmpty) {
      metadata['stderr'] = stderrText;
    }

    return metadata;
  }
}

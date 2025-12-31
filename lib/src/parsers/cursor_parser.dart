import 'dart:convert';

import '../models/models.dart';
import 'base_parser.dart';

/// Parser for Cursor Agent CLI JSON output (`--print --output-format json`).
class CursorParser extends BaseParser {
  @override
  String get name => 'cursor_json';

  @override
  ParsedResponse parse({required String stdout, required String stderr}) {
    final trimmed = stdout.trim();
    if (trimmed.isEmpty) {
      throw ParserException('Cursor Agent CLI returned empty stdout');
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(trimmed) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw ParserException('Failed to decode Cursor Agent JSON: $e');
    }

    final result = payload['result'] as String?;
    final content = result?.trim() ?? '';
    if (content.isEmpty) {
      throw ParserException('Cursor Agent JSON missing non-empty result');
    }

    final metadata = <String, dynamic>{'raw': payload};

    final sessionId = payload['session_id'];
    if (sessionId is String && sessionId.isNotEmpty) {
      metadata['session_id'] = sessionId;
    }

    final durationMs = payload['duration_ms'];
    if (durationMs is num) {
      metadata['duration_ms'] = durationMs;
    }

    final durationApiMs = payload['duration_api_ms'];
    if (durationApiMs is num) {
      metadata['duration_api_ms'] = durationApiMs;
    }

    final requestId = payload['request_id'];
    if (requestId is String && requestId.isNotEmpty) {
      metadata['request_id'] = requestId;
    }

    final isError = payload['is_error'];
    if (isError is bool && isError) {
      metadata['is_error'] = true;
    }

    final stderrText = stderr.trim();
    if (stderrText.isNotEmpty) {
      metadata['stderr'] = stderrText;
    }

    return ParsedResponse(content: content, metadata: metadata);
  }
}

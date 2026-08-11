import 'dart:convert';

import '../models/models.dart';
import 'base_parser.dart';

/// Parser for Pi JSON event stream output (`pi --mode json`).
class PiParser extends BaseParser {
  @override
  String get name => 'pi_jsonl';

  @override
  ParsedResponse parse({required String stdout, required String stderr}) {
    String? sessionId;
    Map<String, dynamic>? finalMessage;

    for (final line in stdout.split('\n')) {
      if (line.trim().isEmpty) continue;

      final Map<String, dynamic> event;
      try {
        event = jsonDecode(line) as Map<String, dynamic>;
      } on FormatException {
        throw ParserException('Pi emitted an invalid JSON event.');
      } on TypeError {
        throw ParserException('Pi emitted a non-object JSON event.');
      }

      if (event['type'] == 'session') {
        sessionId = event['id'] as String?;
      }
      if (event['type'] == 'message_end') {
        final message = event['message'];
        if (message is Map<String, dynamic> && message['role'] == 'assistant') {
          finalMessage = message;
        }
      }
      if (event['type'] == 'agent_end') {
        final messages = event['messages'];
        if (messages is List) {
          for (final message in messages.whereType<Map<String, dynamic>>()) {
            if (message['role'] == 'assistant') finalMessage = message;
          }
        }
      }
    }

    if (finalMessage == null) {
      throw ParserException(
        'Pi JSON output did not include a final assistant message.',
        reason: AgentExitReason.emptyResponse,
      );
    }

    final stopReason = finalMessage['stopReason'] as String?;
    if (stopReason == 'error' || stopReason == 'aborted') {
      throw ParserException(
        finalMessage['errorMessage'] as String? ??
            'Pi stopped with reason "$stopReason".',
        reason: AgentExitReason.cliError,
      );
    }

    final content = _textContent(finalMessage['content']);
    if (content.isEmpty) {
      throw ParserException(
        'Pi final assistant message did not include text content.',
        reason: AgentExitReason.emptyResponse,
      );
    }

    final provider = finalMessage['provider'] as String?;
    final model =
        finalMessage['responseModel'] as String? ??
        finalMessage['model'] as String?;
    return ParsedResponse(
      content: content,
      metadata: {
        if (sessionId != null) 'session_id': sessionId,
        if (provider != null && model != null)
          'model_used': '$provider/$model'
        else if (model != null)
          'model_used': model,
        if (finalMessage['usage'] case final Map<String, dynamic> usage)
          'usage': usage,
        if (stopReason != null) 'stop_reason': stopReason,
        if (stderr.trim().isNotEmpty) 'stderr': stderr.trim(),
      },
    );
  }

  String _textContent(Object? rawContent) {
    if (rawContent is! List) return '';
    return rawContent
        .whereType<Map<String, dynamic>>()
        .where((item) => item['type'] == 'text')
        .map((item) => item['text'])
        .whereType<String>()
        .where((text) => text.trim().isNotEmpty)
        .join('\n')
        .trim();
  }
}

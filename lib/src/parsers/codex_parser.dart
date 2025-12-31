import 'dart:convert';

import '../models/models.dart';
import 'base_parser.dart';

/// Parser for Codex CLI JSONL output (`codex exec --json`).
class CodexParser extends BaseParser {
  @override
  String get name => 'codex_jsonl';

  @override
  ParsedResponse parse({required String stdout, required String stderr}) {
    final lines = stdout.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final events = <Map<String, dynamic>>[];
    final agentMessages = <String>[];
    final errors = <String>[];
    Map<String, dynamic>? usage;
    String? threadId;

    for (final line in lines) {
      if (!line.trim().startsWith('{')) continue;

      final Map<String, dynamic> event;
      try {
        event = jsonDecode(line.trim()) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }

      events.add(event);
      final eventType = event['type'] as String?;

      switch (eventType) {
        case 'thread.started':
          threadId = event['thread_id'] as String?;
        case 'item.completed':
          final item = event['item'] as Map<String, dynamic>?;
          if (item != null && item['type'] == 'agent_message') {
            final text = item['text'] as String?;
            if (text != null && text.trim().isNotEmpty) {
              agentMessages.add(text.trim());
            }
          }
        case 'error':
          final message = event['message'] as String?;
          if (message != null && message.trim().isNotEmpty) {
            errors.add(message.trim());
          }
        case 'turn.completed':
          final turnUsage = event['usage'] as Map<String, dynamic>?;
          if (turnUsage != null) {
            usage = turnUsage;
          }
      }
    }

    if (agentMessages.isEmpty && errors.isNotEmpty) {
      agentMessages.addAll(errors);
    }

    if (agentMessages.isEmpty) {
      throw ParserException(
        'Codex CLI JSONL output did not include an agent_message item',
      );
    }

    final content = agentMessages.join('\n\n').trim();
    final metadata = <String, dynamic>{
      'events': events,
      if (threadId != null) 'session_id': threadId,
      if (errors.isNotEmpty) 'errors': errors,
      if (usage != null) 'usage': usage,
      if (stderr.trim().isNotEmpty) 'stderr': stderr.trim(),
    };

    return ParsedResponse(content: content, metadata: metadata);
  }
}

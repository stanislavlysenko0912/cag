import '../models/models.dart';
import 'base_parser.dart';

/// Parser for Antigravity CLI output (`agy --print`).
class AntigravityParser extends BaseParser {
  @override
  String get name => 'antigravity';

  @override
  ParsedResponse parse({required String stdout, required String stderr}) {
    final responseText = stdout.trim();

    if (responseText.isEmpty && stderr.trim().isEmpty) {
      throw ParserException(
        'Antigravity CLI returned empty output',
        reason: AgentExitReason.emptyResponse,
      );
    }

    final metadata = <String, dynamic>{};
    if (stderr.trim().isNotEmpty) {
      metadata['stderr'] = stderr.trim();
    }

    final combinedOutput = '$stdout\n$stderr';
    final sessionMatch = RegExp(
      r'(?:conversation_id:\s*|--conversation\s+)([a-zA-Z0-9-]+)',
    ).firstMatch(combinedOutput);
    if (sessionMatch != null) {
      metadata['session_id'] = sessionMatch.group(1);
    }

    return ParsedResponse(
      content: responseText.isNotEmpty
          ? responseText
          : 'Antigravity CLI completed with no textual output.',
      metadata: metadata,
    );
  }
}

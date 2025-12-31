import 'dart:convert';

import '../models/models.dart';
import 'base_parser.dart';

/// Parser for Gemini CLI JSON output (`gemini -o json`).
class GeminiParser extends BaseParser {
  @override
  String get name => 'gemini_json';

  @override
  ParsedResponse parse({required String stdout, required String stderr}) {
    if (stdout.trim().isEmpty) {
      throw ParserException(
        'Gemini CLI returned empty stdout while JSON output was expected',
      );
    }

    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(stdout) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw ParserException('Failed to decode Gemini CLI JSON output: $e');
    }

    final response = payload['response'];
    final responseText = response is String ? response.trim() : '';

    final metadata = <String, dynamic>{'raw': payload};

    final sessionId = payload['session_id'];
    if (sessionId is String) {
      metadata['session_id'] = sessionId;
    }

    _extractStats(payload, metadata);

    if (responseText.isNotEmpty) {
      if (stderr.trim().isNotEmpty) {
        metadata['stderr'] = stderr.trim();
      }
      return ParsedResponse(content: responseText, metadata: metadata);
    }

    final fallback = _buildFallbackMessage(payload, stderr);
    if (fallback != null) {
      metadata.addAll(fallback.extraMetadata);
      if (stderr.trim().isNotEmpty) {
        metadata['stderr'] = stderr.trim();
      }
      return ParsedResponse(content: fallback.message, metadata: metadata);
    }

    throw ParserException(
      "Gemini CLI response is missing a textual 'response' field",
    );
  }

  void _extractStats(
    Map<String, dynamic> payload,
    Map<String, dynamic> metadata,
  ) {
    final stats = payload['stats'];
    if (stats is! Map<String, dynamic>) return;

    metadata['stats'] = stats;

    final models = stats['models'];
    if (models is! Map<String, dynamic> || models.isEmpty) return;

    final modelName = models.keys.first;
    metadata['model_used'] = modelName;

    final modelStats = models[modelName];
    if (modelStats is! Map<String, dynamic>) return;

    final tokens = modelStats['tokens'];
    if (tokens is Map<String, dynamic>) {
      metadata['token_usage'] = tokens;
    }

    final apiStats = modelStats['api'];
    if (apiStats is Map<String, dynamic>) {
      metadata['latency_ms'] = apiStats['totalLatencyMs'];
    }
  }

  _FallbackResult? _buildFallbackMessage(
    Map<String, dynamic> payload,
    String stderr,
  ) {
    final stderrText = stderr.trim();
    final stderrLower = stderrText.toLowerCase();
    final extraMetadata = <String, dynamic>{'empty_response': true};

    if (stderrLower.contains('429') || stderrLower.contains('rate limit')) {
      extraMetadata['rate_limit_status'] = 429;
      return _FallbackResult(
        message:
            'Gemini request returned no content because the API reported a 429 rate limit. '
            'Retry after reducing the request size or waiting for quota to replenish.',
        extraMetadata: extraMetadata,
      );
    }

    final stats = payload['stats'];
    if (stats is Map<String, dynamic>) {
      final models = stats['models'];
      if (models is Map<String, dynamic> && models.isNotEmpty) {
        final firstModel = models.values.first;
        if (firstModel is Map<String, dynamic>) {
          final apiStats = firstModel['api'];
          if (apiStats is Map<String, dynamic>) {
            final totalErrors = apiStats['totalErrors'];
            final totalRequests = apiStats['totalRequests'];
            if (totalErrors is int && totalErrors > 0) {
              extraMetadata['api_total_errors'] = totalErrors;
              if (totalRequests is int) {
                extraMetadata['api_total_requests'] = totalRequests;
              }
              return _FallbackResult(
                message:
                    'Gemini CLI returned no textual output. The API reported '
                    '$totalErrors error(s); see stderr for details.',
                extraMetadata: extraMetadata,
              );
            }
          }
        }
      }
    }

    if (stderrText.isNotEmpty) {
      return _FallbackResult(
        message:
            'Gemini CLI returned no textual output. Raw stderr was preserved for troubleshooting.',
        extraMetadata: extraMetadata,
      );
    }

    return null;
  }
}

class _FallbackResult {
  _FallbackResult({required this.message, required this.extraMetadata});
  final String message;
  final Map<String, dynamic> extraMetadata;
}

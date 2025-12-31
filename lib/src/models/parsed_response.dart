/// Result of parsing CLI stdout/stderr.
class ParsedResponse {
  ParsedResponse({required this.content, this.metadata = const {}});

  /// Main text content from the agent.
  final String content;

  /// Additional metadata (tokens, latency, model used, etc.).
  final Map<String, dynamic> metadata;

  /// Session ID for conversation continuity.
  String? get sessionId => metadata['session_id'] as String?;

  @override
  String toString() => content;

  Map<String, dynamic> toJson() => {'content': content, 'metadata': metadata};
}

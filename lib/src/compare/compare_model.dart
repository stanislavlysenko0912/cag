import '../models/models.dart';

/// A model participating in compare.
class CompareParticipant {
  /// Creates a compare participant definition.
  CompareParticipant({
    required this.agent,
    required this.model,
    this.sessionId,
    String? resolvedModel,
  }) : _resolvedModel = resolvedModel;

  /// Agent name (gemini, codex, claude, cursor).
  final String agent;

  /// Model name as provided (may be alias like "flash").
  final String model;

  /// Session ID from the agent for follow-up.
  final String? sessionId;

  String? _resolvedModel;

  /// Get resolved model name, falls back to original model if not resolved.
  String get resolvedModel => _resolvedModel ?? model;

  /// Create a modified copy of this participant.
  CompareParticipant copyWith({String? sessionId, String? resolvedModel}) {
    return CompareParticipant(
      agent: agent,
      model: model,
      sessionId: sessionId ?? this.sessionId,
      resolvedModel: resolvedModel ?? _resolvedModel,
    );
  }

  /// Parse from CLI format: "agent:model".
  factory CompareParticipant.parse(
    String input, {
    Iterable<String> allowedAgents = const [
      'gemini',
      'codex',
      'claude',
      'cursor',
    ],
  }) {
    final parts = input.split(':');
    if (parts.length != 2) {
      throw ArgumentError(
        'Invalid format: "$input". Expected: agent:model (e.g., agent:model)',
      );
    }

    final agent = parts[0].trim().toLowerCase();
    final model = parts[1].trim();

    if (agent.isEmpty) {
      throw ArgumentError('Agent cannot be empty in: "$input"');
    }
    if (model.isEmpty) {
      throw ArgumentError('Model cannot be empty in: "$input"');
    }

    final validAgents = allowedAgents
        .map((value) => value.toLowerCase())
        .toSet();
    if (validAgents.isEmpty) {
      throw ArgumentError('No agents are enabled.');
    }
    if (!validAgents.contains(agent)) {
      final allowed = validAgents.toList()..sort();
      throw ArgumentError('Invalid agent: $agent. Use: ${allowed.join(', ')}');
    }

    return CompareParticipant(agent: agent, model: model);
  }

  /// Convert participant to JSON.
  Map<String, dynamic> toJson() => {
    'agent': agent,
    'model': resolvedModel,
    if (sessionId != null) 'session_id': sessionId,
  };

  /// Build participant from JSON.
  factory CompareParticipant.fromJson(Map<String, dynamic> json) {
    final model = json['model'] as String;
    return CompareParticipant(
      agent: json['agent'] as String,
      model: model,
      sessionId: json['session_id'] as String?,
      resolvedModel: model,
    );
  }

  @override
  String toString() => '$agent:$model';
}

/// Result from a single compare participant.
class CompareParticipantResult {
  /// Creates a compare participant result.
  CompareParticipantResult({
    required this.participant,
    this.response,
    this.failure,
  });

  /// Participant details.
  final CompareParticipant participant;

  /// Parsed response when successful.
  final ParsedResponse? response;

  /// Structured failure when execution failed.
  final AgentFailure? failure;

  /// Whether execution succeeded.
  bool get success => failure == null && response != null;

  /// Convert result to JSON.
  Map<String, dynamic> toJson() => {
    'participant': participant.toJson(),
    'success': success,
    if (response != null) 'response': response!.toJson(),
    if (participant.sessionId != null) 'session_id': participant.sessionId,
    if (failure != null) 'failure': failure!.toJson(),
  };

  /// Build result from JSON.
  factory CompareParticipantResult.fromJson(Map<String, dynamic> json) {
    final participant = CompareParticipant.fromJson(
      json['participant'] as Map<String, dynamic>,
    );
    return CompareParticipantResult(
      participant: participant,
      response: _parseResponse(json['response']),
      failure: _parseFailure(json['failure']),
    );
  }
}

/// Persistent compare run.
class CompareRun {
  /// Creates a compare run.
  CompareRun({
    required this.compareId,
    required this.title,
    required this.prompt,
    required this.participants,
    required this.results,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique compare ID.
  final String compareId;

  /// Compare title shown in lists.
  final String title;

  /// Original prompt.
  final String prompt;

  /// Participating models.
  final List<CompareParticipant> participants;

  /// Run results.
  final List<CompareParticipantResult> results;

  /// Creation time.
  final DateTime createdAt;

  /// Last update time.
  DateTime updatedAt;

  /// Run type identifier.
  String get kind => 'compare';

  /// Run status.
  String get status {
    final successCount = results.where((result) => result.success).length;
    if (successCount == results.length) {
      return 'completed';
    }
    if (successCount == 0) {
      return 'failed';
    }
    return 'partial_failure';
  }

  /// Successful result count.
  int get successCount => results.where((result) => result.success).length;

  /// Failed result count.
  int get failureCount => results.length - successCount;

  /// Convert run to JSON.
  Map<String, dynamic> toJson() => {
    'id': compareId,
    'kind': kind,
    'status': status,
    'title': title,
    'prompt': prompt,
    'participants': participants.map((participant) => participant.toJson()).toList(),
    'results': results.map((result) => result.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Build run from JSON.
  factory CompareRun.fromJson(Map<String, dynamic> json) {
    return CompareRun(
      compareId: json['id'] as String,
      title: json['title'] as String,
      prompt: json['prompt'] as String,
      participants: (json['participants'] as List)
          .map(
            (participant) => CompareParticipant.fromJson(
              participant as Map<String, dynamic>,
            ),
          )
          .toList(),
      results: (json['results'] as List)
          .map(
            (result) => CompareParticipantResult.fromJson(
              result as Map<String, dynamic>,
            ),
          )
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Convert run to summary JSON for list output.
  Map<String, dynamic> toSummaryJson() => {
    'id': compareId,
    'kind': kind,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'status': status,
    'title': title,
    'participants': participants.map((participant) => participant.toString()).toList(),
    'success_count': successCount,
    'failure_count': failureCount,
  };
}

ParsedResponse? _parseResponse(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  return ParsedResponse(
    content: value['content'] as String,
    metadata: (value['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

AgentFailure? _parseFailure(Object? value) {
  if (value is! Map<String, dynamic>) {
    return null;
  }
  return AgentFailure.fromJson(value);
}

import '../models/models.dart';

/// A member of the council.
///
/// Used for both participants and the chairman.
class CouncilMember {
  /// Creates a council member definition.
  CouncilMember({
    required this.agent,
    required this.model,
    this.sessionId,
    String? resolvedModel,
  }) : _resolvedModel = resolvedModel;

  /// Agent name (gemini, codex, claude, cursor).
  final String agent;

  /// Model name as provided (may be alias like "flash").
  final String model;

  /// Session ID from the answer stage for later follow-up.
  final String? sessionId;

  String? _resolvedModel;

  /// Gets the resolved model name.
  String get resolvedModel => _resolvedModel ?? model;

  /// Sets the resolved model name.
  set resolvedModel(String value) => _resolvedModel = value;

  /// Creates a modified copy of this member.
  CouncilMember copyWith({String? sessionId, String? resolvedModel}) {
    return CouncilMember(
      agent: agent,
      model: model,
      sessionId: sessionId ?? this.sessionId,
      resolvedModel: resolvedModel ?? _resolvedModel,
    );
  }

  /// Parses a member from CLI format: `agent:model`.
  factory CouncilMember.parse(
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

    return CouncilMember(agent: agent, model: model);
  }

  /// Converts the member to JSON.
  Map<String, dynamic> toJson() => {
    'agent': agent,
    'model': resolvedModel,
    if (sessionId != null) 'session_id': sessionId,
  };

  /// Builds a member from JSON.
  factory CouncilMember.fromJson(Map<String, dynamic> json) {
    final model = json['model'] as String;
    return CouncilMember(
      agent: json['agent'] as String,
      model: model,
      sessionId: json['session_id'] as String?,
      resolvedModel: model,
    );
  }

  @override
  String toString() => '$agent:$model';
}

/// Result from a single participant response.
class CouncilParticipantResult {
  /// Creates a participant result.
  CouncilParticipantResult({
    required this.participant,
    required this.response,
    this.failure,
  });

  /// Participant details.
  final CouncilMember participant;

  /// Parsed response.
  final ParsedResponse? response;

  /// Structured failure when execution failed.
  final AgentFailure? failure;

  /// Whether the participant succeeded.
  bool get success => failure == null && response != null;

  /// Converts the result to JSON.
  Map<String, dynamic> toJson() => {
    'participant': participant.toJson(),
    'success': success,
    if (response != null) 'response': response!.toJson(),
    if (failure != null) 'failure': failure!.toJson(),
  };

  /// Builds a participant result from JSON.
  factory CouncilParticipantResult.fromJson(Map<String, dynamic> json) {
    return CouncilParticipantResult(
      participant: CouncilMember.fromJson(
        json['participant'] as Map<String, dynamic>,
      ),
      response: _parseResponse(json['response']),
      failure: _parseFailure(json['failure']),
    );
  }
}

/// Result from a single participant review.
class CouncilReviewResult {
  /// Creates a review result.
  CouncilReviewResult({
    required this.participant,
    required this.response,
    this.failure,
  });

  /// Participant details.
  final CouncilMember participant;

  /// Parsed response.
  final ParsedResponse? response;

  /// Structured failure when execution failed.
  final AgentFailure? failure;

  /// Whether the review succeeded.
  bool get success => failure == null && response != null;

  /// Converts the result to JSON.
  Map<String, dynamic> toJson() => {
    'participant': participant.toJson(),
    'success': success,
    if (response != null) 'response': response!.toJson(),
    if (failure != null) 'failure': failure!.toJson(),
  };

  /// Builds a review result from JSON.
  factory CouncilReviewResult.fromJson(Map<String, dynamic> json) {
    return CouncilReviewResult(
      participant: CouncilMember.fromJson(
        json['participant'] as Map<String, dynamic>,
      ),
      response: _parseResponse(json['response']),
      failure: _parseFailure(json['failure']),
    );
  }
}

/// Result from the chairman synthesis.
class CouncilChairmanResult {
  /// Creates a chairman result.
  CouncilChairmanResult({
    required this.chairman,
    required this.response,
    this.failure,
  });

  /// Chairman details.
  final CouncilMember chairman;

  /// Parsed response.
  final ParsedResponse? response;

  /// Structured failure when execution failed.
  final AgentFailure? failure;

  /// Whether the chairman synthesis succeeded.
  bool get success => failure == null && response != null;

  /// Converts the result to JSON.
  Map<String, dynamic> toJson() => {
    'chairman': chairman.toJson(),
    'success': success,
    if (response != null) 'response': response!.toJson(),
    if (failure != null) 'failure': failure!.toJson(),
  };

  /// Builds a chairman result from JSON.
  factory CouncilChairmanResult.fromJson(Map<String, dynamic> json) {
    return CouncilChairmanResult(
      chairman: CouncilMember.fromJson(
        json['chairman'] as Map<String, dynamic>,
      ),
      response: _parseResponse(json['response']),
      failure: _parseFailure(json['failure']),
    );
  }
}

/// Persistent council run.
class CouncilRun {
  /// Creates a council run.
  CouncilRun({
    required this.councilId,
    required this.title,
    required this.prompt,
    required this.participants,
    required this.chairman,
    required this.answers,
    required this.reviews,
    required this.chairmanResult,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique council ID.
  final String councilId;

  /// Council title shown in lists.
  final String title;

  /// Original prompt.
  final String prompt;

  /// Participating models.
  final List<CouncilMember> participants;

  /// Chairman for the run.
  final CouncilMember chairman;

  /// Stage 1 answers.
  final List<CouncilParticipantResult> answers;

  /// Stage 2 reviews.
  final List<CouncilReviewResult> reviews;

  /// Stage 3 chairman result.
  final CouncilChairmanResult chairmanResult;

  /// Creation time.
  final DateTime createdAt;

  /// Last update time.
  DateTime updatedAt;

  /// Run type identifier.
  String get kind => 'council';

  /// Run status.
  String get status {
    final totalStages = answers.length + reviews.length + 1;
    final successCount =
        answers.where((result) => result.success).length +
        reviews.where((result) => result.success).length +
        (chairmanResult.success ? 1 : 0);

    if (successCount == totalStages) {
      return 'completed';
    }
    if (successCount == 0) {
      return 'failed';
    }
    return 'partial_failure';
  }

  /// Converts the run to JSON.
  Map<String, dynamic> toJson() => {
    'id': councilId,
    'kind': kind,
    'status': status,
    'title': title,
    'prompt': prompt,
    'participants': participants.map((item) => item.toJson()).toList(),
    'chairman': chairman.toJson(),
    'answers': answers.map((item) => item.toJson()).toList(),
    'reviews': reviews.map((item) => item.toJson()).toList(),
    'chairman_result': chairmanResult.toJson(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  /// Builds a run from JSON.
  factory CouncilRun.fromJson(Map<String, dynamic> json) {
    return CouncilRun(
      councilId: json['id'] as String,
      title: json['title'] as String,
      prompt: json['prompt'] as String,
      participants: (json['participants'] as List)
          .map((item) => CouncilMember.fromJson(item as Map<String, dynamic>))
          .toList(),
      chairman: CouncilMember.fromJson(json['chairman'] as Map<String, dynamic>),
      answers: (json['answers'] as List)
          .map(
            (item) => CouncilParticipantResult.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      reviews: (json['reviews'] as List)
          .map(
            (item) => CouncilReviewResult.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
      chairmanResult: CouncilChairmanResult.fromJson(
        json['chairman_result'] as Map<String, dynamic>,
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Converts the run to summary JSON for list output.
  Map<String, dynamic> toSummaryJson() => {
    'id': councilId,
    'kind': kind,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'status': status,
    'title': title,
    'participants': participants.map((item) => item.toString()).toList(),
    'chairman': chairman.toString(),
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

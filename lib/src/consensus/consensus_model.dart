import '../agents/known_agents.dart';
import '../utils/participant_parser.dart';

/// Stance for a model in consensus.
enum ConsensusStance {
  /// Supportive perspective - find benefits and reasons to proceed.
  forProposal('for'),

  /// Critical perspective - find risks and reasons to reconsider.
  against('against'),

  /// Balanced perspective - objective analysis of both sides.
  neutral('neutral');

  const ConsensusStance(this.value);
  final String value;

  static ConsensusStance fromString(String value) {
    return switch (value.toLowerCase()) {
      'for' => ConsensusStance.forProposal,
      'against' => ConsensusStance.against,
      'neutral' => ConsensusStance.neutral,
      _ => throw ArgumentError(
        'Invalid stance: $value. Use: for, against, neutral',
      ),
    };
  }
}

/// A model participating in consensus.
class ConsensusParticipant {
  ConsensusParticipant({
    required this.agent,
    required this.model,
    required this.stance,
    this.sessionId,
    this.stancePrompt,
    String? resolvedModel,
  }) : _resolvedModel = resolvedModel;

  /// Agent name (gemini, codex, claude, cursor, antigravity).
  final String agent;

  /// Model name as provided (may be alias like "flash").
  final String model;

  /// Stance for this model.
  final ConsensusStance stance;

  /// Session ID from the agent (for resume).
  String? sessionId;

  /// Custom stance prompt (optional).
  final String? stancePrompt;

  /// Resolved model name (full name, not alias).
  String? _resolvedModel;

  /// Get resolved model name, falls back to original model if not resolved.
  String get resolvedModel => _resolvedModel ?? model;

  /// Set resolved model name.
  set resolvedModel(String value) => _resolvedModel = value;

  /// Parse from CLI format: "agent:model:stance"
  factory ConsensusParticipant.parse(
    String input, {
    Iterable<String> allowedAgents = KnownAgents.all,
  }) {
    final parsed = ParticipantParser.parse(
      input: input,
      expectedParts: 3,
      expectedFormat: 'agent:model:stance (e.g., agent:model:for)',
      allowedAgents: allowedAgents,
    );

    return ConsensusParticipant(
      agent: parsed.agent,
      model: parsed.model,
      stance: ConsensusStance.fromString(parsed.extraParts.single),
    );
  }

  Map<String, dynamic> toJson() => {
    'agent': agent,
    'model': resolvedModel,
    'stance': stance.value,
    if (sessionId != null) 'session_id': sessionId,
    if (stancePrompt != null) 'stance_prompt': stancePrompt,
  };

  factory ConsensusParticipant.fromJson(Map<String, dynamic> json) {
    final model = json['model'] as String;
    return ConsensusParticipant(
      agent: json['agent'] as String,
      model: model,
      stance: ConsensusStance.fromString(json['stance'] as String),
      sessionId: json['session_id'] as String?,
      stancePrompt: json['stance_prompt'] as String?,
      resolvedModel: model,
    );
  }

  @override
  String toString() => '$agent:$model:${stance.value}';
}

/// A consensus session with multiple model participants.
class ConsensusSession {
  ConsensusSession({
    required this.consensusId,
    required this.prompt,
    required this.participants,
    required this.createdAt,
    this.title,
    this.proposal,
    this.updatedAt,
  });

  /// Unique consensus session ID.
  final String consensusId;

  /// Original proposal/idea to analyze (optional context).
  final String? proposal;

  /// Session title shown in lists and inspect views.
  final String? title;

  /// Query/prompt from the calling agent.
  final String prompt;

  /// Participating models with their stances.
  final List<ConsensusParticipant> participants;

  /// When session was created.
  final DateTime createdAt;

  /// When session was last updated.
  DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'consensus_id': consensusId,
    if (title != null) 'title': title,
    if (proposal != null) 'proposal': proposal,
    'prompt': prompt,
    'participants': participants.map((p) => p.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
  };

  factory ConsensusSession.fromJson(Map<String, dynamic> json) {
    return ConsensusSession(
      consensusId: json['consensus_id'] as String,
      title: json['title'] as String?,
      proposal: json['proposal'] as String?,
      prompt: json['prompt'] as String,
      participants: (json['participants'] as List)
          .map((p) => ConsensusParticipant.fromJson(p as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  /// Converts the session to summary JSON for list output.
  Map<String, dynamic> toSummaryJson() => {
    'id': consensusId,
    'created_at': createdAt.toIso8601String(),
    if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    'title': title,
    'prompt': prompt,
    if (proposal != null) 'proposal': proposal,
    'participants': participants
        .map((participant) => participant.toString())
        .toList(),
  };
}

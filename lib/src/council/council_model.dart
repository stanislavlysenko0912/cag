/// A member of the council (participant or chairman).
///
/// Used for both participants and the chairman.
class CouncilMember {
  /// Creates a council member definition.
  ///
  /// Provide agent/model information.
  CouncilMember({
    required this.agent,
    required this.model,
    String? resolvedModel,
  }) : _resolvedModel = resolvedModel;

  /// Agent name (gemini, codex, claude).
  final String agent;

  /// Model name as provided (may be alias like "flash").
  final String model;

  String? _resolvedModel;

  /// Get resolved model name, falls back to original model if not resolved.
  String get resolvedModel => _resolvedModel ?? model;

  /// Set resolved model name.
  set resolvedModel(String value) => _resolvedModel = value;

  /// Parse from CLI format: "agent:model".
  ///
  /// Throws [ArgumentError] if the format is invalid.
  factory CouncilMember.parse(
    String input, {
    Iterable<String> allowedAgents = const ['gemini', 'codex', 'claude'],
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

  Map<String, dynamic> toJson() => {'agent': agent, 'model': resolvedModel};

  factory CouncilMember.fromJson(Map<String, dynamic> json) {
    final model = json['model'] as String;
    return CouncilMember(
      agent: json['agent'] as String,
      model: model,
      resolvedModel: model,
    );
  }

  @override
  String toString() => '$agent:$model';
}

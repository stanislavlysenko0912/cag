/// Parsed participant components shared by command-domain models.
typedef ParsedParticipant = ({
  String agent,
  String model,
  List<String> extraParts,
});

/// Shared parser for `agent:model[:extra...]` participant strings.
class ParticipantParser {
  /// Parses and validates a participant definition.
  static ParsedParticipant parse({
    required String input,
    required int expectedParts,
    required String expectedFormat,
    required Iterable<String> allowedAgents,
  }) {
    final parts = input.split(':');
    if (parts.length != expectedParts) {
      throw ArgumentError(
        'Invalid format: "$input". Expected: $expectedFormat',
      );
    }

    final agent = parts.first.trim().toLowerCase();
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

    final extraParts = parts.skip(2).map((part) => part.trim()).toList();
    return (agent: agent, model: model, extraParts: extraParts);
  }
}

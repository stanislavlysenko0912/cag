/// Model configuration with metadata.
class ModelConfig {
  const ModelConfig({
    required this.name,
    this.description,
    this.model,
    this.scores,
    this.isDefault = false,
    this.enabled = true,
    this.aliases = const [],
  });

  /// Stable model identifier exposed by CAG.
  final String name;

  /// Model identifier passed to the wrapped agent when it differs from [name].
  final String? model;

  /// Optional short routing hint for this model.
  final String? description;

  /// Comparable model routing scores.
  final ModelScores? scores;

  /// Whether this is the default model.
  final bool isDefault;

  /// Whether this model is available for selection.
  final bool enabled;

  /// Alternative names that resolve to this model.
  final List<String> aliases;

  /// Creates a model configuration from a JSON map.
  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    final description = _blankToNull(json['description'] as String?);
    final scores = json['scores'];
    return ModelConfig(
      name: json['name'] as String,
      description: description,
      model: json['model'] as String?,
      scores: scores is Map<String, dynamic>
          ? ModelScores.fromJson(scores)
          : null,
      isDefault: json['is_default'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
      aliases:
          (json['aliases'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  /// Converts this model configuration to a JSON map.
  Map<String, dynamic> toJson() {
    final hint = _blankToNull(description);
    return {
      'name': name,
      if (hint != null) 'description': hint,
      if (model != null) 'model': model,
      if (scores != null) 'scores': scores!.toJson(),
      'is_default': isDefault,
      if (!enabled) 'enabled': enabled,
      'aliases': aliases,
    };
  }

  /// Model identifier to pass to the wrapped agent.
  String get resolvedModel => model ?? name;

  /// Check if given name matches this model.
  bool matches(String input) {
    return name == input || aliases.contains(input);
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

/// Comparable routing scores for a model.
class ModelScores {
  ModelScores({
    required this.cost,
    required this.intelligence,
    required this.speed,
    required this.taste,
  }) {
    _validateScore('cost', cost);
    _validateScore('intelligence', intelligence);
    _validateScore('speed', speed);
    _validateScore('taste', taste);
  }

  /// Cost score from 1 to 10, where higher means cheaper.
  final int cost;

  /// Intelligence score from 1 to 10.
  final int intelligence;

  /// Speed score from 1 to 10.
  final int speed;

  /// Taste score from 1 to 10 for UI, UX, API design, code quality, and copy.
  final int taste;

  /// Creates model scores from a JSON map.
  factory ModelScores.fromJson(Map<String, dynamic> json) {
    return ModelScores(
      cost: json['cost'] as int,
      intelligence: json['intelligence'] as int,
      speed: json['speed'] as int,
      taste: json['taste'] as int,
    );
  }

  /// Converts these scores to a JSON map.
  Map<String, dynamic> toJson() => {
    'cost': cost,
    'intelligence': intelligence,
    'speed': speed,
    'taste': taste,
  };

  static void _validateScore(String name, int value) {
    if (value < 1 || value > 10) {
      throw ArgumentError.value(value, name, 'must be between 1 and 10');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ModelScores &&
      other.cost == cost &&
      other.intelligence == intelligence &&
      other.speed == speed &&
      other.taste == taste;

  @override
  int get hashCode => Object.hash(cost, intelligence, speed, taste);
}

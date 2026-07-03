/// Model configuration with metadata.
class ModelConfig {
  const ModelConfig({
    required this.name,
    required this.description,
    this.model,
    this.isDefault = false,
    this.aliases = const [],
  });

  /// Stable model identifier exposed by CAG.
  final String name;

  /// Model identifier passed to the wrapped agent when it differs from [name].
  final String? model;

  /// Human-readable description of model capabilities.
  final String description;

  /// Whether this is the default model.
  final bool isDefault;

  /// Alternative names that resolve to this model.
  final List<String> aliases;

  /// Creates a model configuration from a JSON map.
  factory ModelConfig.fromJson(Map<String, dynamic> json) {
    return ModelConfig(
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      model: json['model'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
      aliases:
          (json['aliases'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  /// Converts this model configuration to a JSON map.
  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    if (model != null) 'model': model,
    'is_default': isDefault,
    'aliases': aliases,
  };

  /// Model identifier to pass to the wrapped agent.
  String get resolvedModel => model ?? name;

  /// Check if given name matches this model.
  bool matches(String input) {
    return name == input || aliases.contains(input);
  }
}

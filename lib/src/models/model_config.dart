/// Model configuration with metadata.
class ModelConfig {
  const ModelConfig({
    required this.name,
    required this.description,
    this.isDefault = false,
    this.aliases = const [],
  });

  /// Model identifier used in CLI.
  final String name;

  /// Human-readable description of model capabilities.
  final String description;

  /// Whether this is the default model.
  final bool isDefault;

  /// Alternative names that resolve to this model.
  final List<String> aliases;

  /// Check if given name matches this model.
  bool matches(String input) {
    return name == input || aliases.contains(input);
  }
}

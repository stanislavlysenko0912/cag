import '../models/models.dart';

/// Metadata for documenting CLI commands.
class CommandMetadata {
  const CommandMetadata({
    required this.name,
    required this.description,
    this.models = const [],
    this.examples = const [],
    this.flags = const [],
    this.notes,
  });

  /// Command name (e.g., 'claude', 'gemini').
  final String name;

  /// Short description of what the command does.
  final String description;

  /// Available models with their metadata.
  final List<ModelConfig> models;

  /// Usage examples with descriptions.
  final List<CommandExample> examples;

  /// Available flags/options.
  final List<CommandFlag> flags;

  /// Additional notes or tips.
  final String? notes;

  /// Get default model.
  ModelConfig? get defaultModel => models.where((m) => m.isDefault).firstOrNull;

  /// Find model by name or alias.
  ModelConfig? findModel(String name) {
    return models.where((m) => m.matches(name)).firstOrNull;
  }

  /// Validate model name, returns error message or null if valid.
  String? validateModel(String name) {
    if (findModel(name) == null) {
      final available = models.map((m) => m.name).join(', ');
      return 'Unknown model "$name". Available: $available';
    }
    return null;
  }
}

/// Example usage of a command.
class CommandExample {
  const CommandExample({required this.command, required this.description});

  /// The actual command line.
  final String command;

  /// What this example demonstrates.
  final String description;
}

/// Command flag/option documentation.
class CommandFlag {
  const CommandFlag({
    required this.flag,
    required this.description,
    this.shortFlag,
    this.defaultValue,
  });

  /// Long flag name (e.g., '--model').
  final String flag;

  /// Short flag (e.g., '-m').
  final String? shortFlag;

  /// Description of what the flag does.
  final String description;

  /// Default value if any.
  final String? defaultValue;

  /// Format flag for display.
  String get formatted {
    final short = shortFlag != null ? '$shortFlag, ' : '    ';
    return '$short$flag';
  }
}

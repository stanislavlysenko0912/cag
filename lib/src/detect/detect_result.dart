/// Result of checking installed agent CLI executables.
class DetectResult {
  /// Creates a detect result.
  const DetectResult({required this.agents, required this.configPath});

  /// Availability by agent name.
  final Map<String, bool> agents;

  /// Config path updated by detection.
  final String configPath;
}

/// A read-only comparison between detected availability and current config.
///
/// Used to preview what applying detection would change before writing.
class DetectPreview {
  const DetectPreview({required this.rows, required this.configPath});

  final List<DetectRow> rows;
  final String configPath;

  int get changeCount => rows.where((row) => row.willChange).length;

  bool get hasChanges => changeCount > 0;
}

/// A single agent's detection state and whether applying would change it.
class DetectRow {
  const DetectRow({
    required this.name,
    required this.displayName,
    required this.available,
    required this.enabled,
  });

  /// Stable agent identifier.
  final String name;

  /// Human-readable agent name.
  final String displayName;

  /// Whether the agent executable was found on the system.
  final bool available;

  /// Whether the agent is currently enabled in config.
  final bool enabled;

  /// Whether applying detection would flip the enabled state.
  bool get willChange => available != enabled;
}

import 'model_config.dart';

/// Configuration for a CLI agent.
class AgentConfig {
  const AgentConfig({
    required this.name,
    required this.executable,
    required this.parser,
    this.enabled = true,
    this.defaultModel,
    this.additionalArgs = const [],
    this.env = const {},
    this.hardTimeoutSeconds = 1800,
    this.idleTimeoutSeconds = 900,
    this.shellExecutable,
    this.shellArgs = const [],
    this.shellCommandPrefix,
    this.availableModels = const [],
  });

  /// Agent identifier (e.g., 'gemini', 'claude').
  final String name;

  /// CLI executable name or path.
  final String executable;

  /// Parser type to use for output.
  final String parser;

  /// Whether this agent is enabled for use.
  final bool enabled;

  /// Default model if not specified.
  final String? defaultModel;

  /// Additional CLI arguments always passed.
  final List<String> additionalArgs;

  /// Environment variables for the process.
  final Map<String, String> env;

  /// Hard timeout in seconds.
  final int hardTimeoutSeconds;

  /// Idle timeout in seconds.
  final int idleTimeoutSeconds;

  /// Optional shell executable (e.g., /bin/zsh, cmd).
  final String? shellExecutable;

  /// Arguments passed to the shell executable (e.g., -i -c, /c).
  final List<String> shellArgs;

  /// When set, runs via shell and prefixes the command with this string.
  final String? shellCommandPrefix;

  /// List of available models for this agent.
  final List<ModelConfig> availableModels;
}

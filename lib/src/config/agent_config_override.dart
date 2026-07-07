import '../models/model_config.dart';

class AgentConfigOverride {
  AgentConfigOverride({
    this.executable,
    this.enabled,
    this.defaultModel,
    this.additionalArgs,
    this.env,
    this.hardTimeoutSeconds,
    this.idleTimeoutSeconds,
    this.shellExecutable,
    this.shellArgs,
    this.shellCommandPrefix,
    this.models,
  });

  final String? executable;
  final bool? enabled;
  final String? defaultModel;
  final List<String>? additionalArgs;
  final Map<String, String>? env;
  final int? hardTimeoutSeconds;
  final int? idleTimeoutSeconds;
  final String? shellExecutable;
  final List<String>? shellArgs;
  final String? shellCommandPrefix;
  final List<ModelConfig>? models;

  factory AgentConfigOverride.fromJson(Map<String, dynamic> json) {
    return AgentConfigOverride(
      executable: json['executable'] as String?,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : null,
      defaultModel: json['default_model'] as String?,
      additionalArgs: (json['additional_args'] as List?)
          ?.whereType<String>()
          .toList(),
      env: (json['env'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      hardTimeoutSeconds: json['hard_timeout_seconds'] is int
          ? json['hard_timeout_seconds'] as int
          : null,
      idleTimeoutSeconds: json['idle_timeout_seconds'] is int
          ? json['idle_timeout_seconds'] as int
          : null,
      shellExecutable: json['shell_executable'] as String?,
      shellArgs: (json['shell_args'] as List?)?.whereType<String>().toList(),
      shellCommandPrefix: json['shell_command_prefix'] as String?,
      models: (json['models'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(ModelConfig.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (executable != null) 'executable': executable,
    if (enabled != null) 'enabled': enabled,
    if (defaultModel != null) 'default_model': defaultModel,
    if (additionalArgs != null) 'additional_args': additionalArgs,
    if (env != null) 'env': env,
    if (hardTimeoutSeconds != null) 'hard_timeout_seconds': hardTimeoutSeconds,
    if (idleTimeoutSeconds != null) 'idle_timeout_seconds': idleTimeoutSeconds,
    if (shellExecutable != null) 'shell_executable': shellExecutable,
    if (shellArgs != null) 'shell_args': shellArgs,
    if (shellCommandPrefix != null) 'shell_command_prefix': shellCommandPrefix,
    if (models != null) 'models': models!.map((m) => m.toJson()).toList(),
  };
}

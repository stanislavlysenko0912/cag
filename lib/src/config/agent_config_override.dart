class AgentConfigOverride {
  AgentConfigOverride({
    this.executable,
    this.enabled,
    this.defaultModel,
    this.additionalArgs,
    this.env,
    this.timeoutSeconds,
    this.shellExecutable,
    this.shellArgs,
    this.shellCommandPrefix,
  });

  final String? executable;
  final bool? enabled;
  final String? defaultModel;
  final List<String>? additionalArgs;
  final Map<String, String>? env;
  final int? timeoutSeconds;
  final String? shellExecutable;
  final List<String>? shellArgs;
  final String? shellCommandPrefix;

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
      timeoutSeconds: json['timeout_seconds'] is int
          ? json['timeout_seconds'] as int
          : null,
      shellExecutable: json['shell_executable'] as String?,
      shellArgs: (json['shell_args'] as List?)?.whereType<String>().toList(),
      shellCommandPrefix: json['shell_command_prefix'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (executable != null) 'executable': executable,
    if (enabled != null) 'enabled': enabled,
    if (defaultModel != null) 'default_model': defaultModel,
    if (additionalArgs != null) 'additional_args': additionalArgs,
    if (env != null) 'env': env,
    if (timeoutSeconds != null) 'timeout_seconds': timeoutSeconds,
    if (shellExecutable != null) 'shell_executable': shellExecutable,
    if (shellArgs != null) 'shell_args': shellArgs,
    if (shellCommandPrefix != null) 'shell_command_prefix': shellCommandPrefix,
  };
}

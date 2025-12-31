import 'agent_config_override.dart';

class AppConfig {
  AppConfig({required this.agents});

  final Map<String, AgentConfigOverride> agents;

  factory AppConfig.defaults() {
    return AppConfig(agents: const {});
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final rawAgents = json['agents'];
    final agents = <String, AgentConfigOverride>{};
    if (rawAgents is Map<String, dynamic>) {
      for (final entry in rawAgents.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          agents[entry.key] = AgentConfigOverride.fromJson(value);
        }
      }
    }

    return AppConfig(agents: agents);
  }

  Map<String, dynamic> toJson() => {
    'agents': agents.map((key, value) => MapEntry(key, value.toJson())),
  };
}

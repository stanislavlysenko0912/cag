import 'model_config.dart';

/// Models and current default reported by an agent at runtime.
class AgentModelDiscovery {
  const AgentModelDiscovery({required this.models, this.defaultModel});

  final List<ModelConfig> models;
  final String? defaultModel;
}

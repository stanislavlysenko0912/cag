import 'model_config.dart';

/// Canonical model definitions for all agents.
class AgentModelRegistry {
  const AgentModelRegistry._();

  static const claudeModels = [
    ModelConfig(
      name: 'sonnet',
      description:
          'Balanced speed/quality. Use for: general tasks, code review, discussions',
      isDefault: true,
    ),
    ModelConfig(
      name: 'opus',
      description:
          'Most capable, slower. Use for: complex reasoning, architecture decisions',
    ),
    ModelConfig(
      name: 'haiku',
      description:
          'Fastest, cheapest. Use for: simple questions, quick lookups',
    ),
  ];

  static const geminiModels = [
    ModelConfig(
      name: 'gemini-3-flash-preview',
      description: 'Fast responses. Use for: quick search, simple analysis',
      isDefault: true,
      aliases: ['flash'],
    ),
    ModelConfig(
      name: 'gemini-3-pro-preview',
      description:
          'More capable. Use for: complex analysis, architectural questions',
      aliases: ['pro'],
    ),
  ];

  static const codexModels = [
    ModelConfig(
      name: 'gpt-5.2',
      description: 'Balanced. Use for: general tasks, discussions, coding',
      isDefault: true,
      aliases: ['gpt'],
    ),
    ModelConfig(
      name: 'gpt-5.2-codex',
      description: 'Code-specialized. Use for: complex coding, hard debugging',
      aliases: ['codex'],
    ),
    ModelConfig(
      name: 'gpt-5.1-codex-mini',
      description:
          'Lighter code model. Use for: quick code questions, simple fixes',
      aliases: ['mini'],
    ),
  ];

  static const byAgent = {
    'claude': claudeModels,
    'gemini': geminiModels,
    'codex': codexModels,
  };

  static List<ModelConfig> modelsFor(String agent) {
    return byAgent[agent] ?? const [];
  }

  static ModelConfig? findModel(String agent, String input) {
    final models = modelsFor(agent);
    if (models.isEmpty) return null;
    for (final model in models) {
      if (model.matches(input)) return model;
    }
    return null;
  }

  static String? defaultModelName(String agent) {
    final models = modelsFor(agent);
    if (models.isEmpty) return null;
    for (final model in models) {
      if (model.isDefault) return model.name;
    }
    return models.first.name;
  }
}

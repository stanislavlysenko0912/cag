import 'model_config.dart';

/// Canonical model definitions for all agents.
class AgentModelRegistry {
  const AgentModelRegistry._();

  static const claudeModels = [
    ModelConfig(
      name: 'claude-sonnet-4-6',
      description:
          'Top-tier, fast all-rounder. Use for: general tasks, code review, discussions',
      isDefault: true,
      aliases: ['sonnet'],
    ),
    ModelConfig(
      name: 'claude-opus-4-6',
      description:
          'Top-tier, strongest reasoning. Use for: architecture, complex debugging, deep code review',
      aliases: ['opus'],
    ),
    ModelConfig(
      name: 'claude-haiku-4-5',
      description:
          'Light-tier, fastest. Use for: quick lookups, simple questions',
      aliases: ['haiku'],
    ),
  ];

  static const geminiModels = [
    ModelConfig(
      name: 'gemini-3-flash-preview',
      description: 'Mid-tier, fast. Use for: general search, code analysis',
      isDefault: true,
      aliases: ['flash'],
    ),
    ModelConfig(
      name: 'gemini-3.1-pro-preview',
      description:
          'Top-tier, strong analysis. Use for: complex analysis, architecture, deep code review',
      aliases: ['pro'],
    ),
    ModelConfig(
      name: 'gemini-3.1-flash-lite-preview',
      description: 'Light-tier, fastest. Use for: quick search, simple lookups',
      aliases: ['flash-lite'],
    ),
  ];

  static const codexModels = [
    ModelConfig(
      name: 'gpt-5.4',
      description:
          'Top-tier, versatile frontier model. Use for: general tasks, discussions, broad coding',
      isDefault: true,
      aliases: ['gpt'],
    ),
    ModelConfig(
      name: 'gpt-5.3-codex',
      description:
          'Top-tier, thorough code reviewer. Use for: code review, finding subtle bugs, detailed analysis',
      aliases: ['codex'],
    ),
    ModelConfig(
      name: 'gpt-5.4-mini',
      description:
          'Mid-tier, fast. Use for: quick code questions, simple fixes',
      aliases: ['mini'],
    ),
  ];

  static const cursorModels = [
    ModelConfig(
      name: 'composer-2-fast',
      description:
          'Mid-tier, fast variant (higher cost). Use for: foreground tasks, quick research',
      isDefault: true,
    ),
    ModelConfig(
      name: 'composer-2',
      description:
          'Mid-tier, standard variant (lower cost). Use for: background tasks, longer sessions',
    ),
  ];

  static const byAgent = {
    'claude': claudeModels,
    'gemini': geminiModels,
    'codex': codexModels,
    'cursor': cursorModels,
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

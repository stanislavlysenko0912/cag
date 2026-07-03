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
      name: 'claude-opus-4-8',
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
      name: 'gpt-5.5',
      description:
          'Top-tier, versatile frontier model. Use for: general tasks, discussions, broad coding',
      isDefault: true,
      aliases: ['gpt'],
    ),
    ModelConfig(
      name: 'gpt-5.3-codex',
      description:
          'Top-tier code reviewer. Use for: code review, finding subtle bugs',
      aliases: ['codex'],
    ),
    ModelConfig(
      name: 'gpt-5.5-mini',
      description:
          'Mid-tier, fast. Use for: quick code questions, simple fixes',
      aliases: ['mini'],
    ),
  ];

  /// Curated Cursor Agent models for `cag cursor -m`.
  ///
  /// Discover the full account-specific slug list with
  /// `cursor-agent models` (alias: `cursor-agent --list-models`).
  /// Refresh this curated list when new slugs appear there.
  static const cursorModels = [
    ModelConfig(
      name: 'composer-2.5-fast',
      description:
          'Solid-tier agent model, fast variant. Use for: interactive work, delegated tasks, quick research',
      isDefault: true,
    ),
    ModelConfig(
      name: 'composer-2.5',
      description:
          'Solid-tier agent model, standard variant (lower cost). Use for: longer sessions, background tasks',
    ),
    ModelConfig(
      name: 'gemini-3.5-flash',
      description:
          'Solid-tier, fast and capable. Use for: advice, brainstorming, everyday discussion',
    ),
    ModelConfig(
      name: 'gemini-3.1-pro',
      description:
          'Top-tier analysis. Use for: complex reasoning, architecture, deep code review',
    ),
    ModelConfig(
      name: 'gpt-5.5-high',
      description:
          'Front-tier frontier model. Use for: hardest problems, broad coding, high-stakes decisions',
    ),
    ModelConfig(
      name: 'grok-4.3',
      description:
          'Mid-tier alternative viewpoint. Use for: second opinions, contrasting takes',
    ),
    ModelConfig(
      name: 'claude-opus-4-8-thinking-max',
      description:
          'Front-tier, deepest reasoning. Use for: architecture, complex debugging, critical decisions',
    ),
  ];

  static const antigravityModels = [
    ModelConfig(
      name: 'configured',
      description:
          'Uses the reasoning model currently selected in Antigravity CLI via /model or settings.',
      isDefault: true,
      aliases: ['current', 'default'],
    ),
    ModelConfig(
      name: 'gemini-3-5-flash-medium',
      model: 'Gemini 3.5 Flash (Medium)',
      description: 'Medium-tier Gemini model.',
      aliases: ['flash'],
    ),
    ModelConfig(
      name: 'gemini-3-5-flash-high',
      model: 'Gemini 3.5 Flash (High)',
      description: 'Higher-reasoning Gemini Flash model.',
      aliases: ['flash-high'],
    ),
    ModelConfig(
      name: 'gemini-3-5-flash-low',
      model: 'Gemini 3.5 Flash (Low)',
      description: 'Fast Gemini Flash model.',
      aliases: ['flash-low'],
    ),
    ModelConfig(
      name: 'gemini-3-1-pro-high',
      model: 'Gemini 3.1 Pro (High)',
      description: 'Higher-reasoning Gemini Pro model.',
      aliases: ['pro-high'],
    ),
    ModelConfig(
      name: 'gemini-3-1-pro-low',
      model: 'Gemini 3.1 Pro (Low)',
      description: 'Lower-cost Gemini Pro model.',
      aliases: ['pro-low'],
    ),
    ModelConfig(
      name: 'claude-sonnet-4-6-thinking',
      model: 'Claude Sonnet 4.6 (Thinking)',
      description: 'Claude Sonnet thinking model.',
      aliases: ['sonnet'],
    ),
    ModelConfig(
      name: 'claude-opus-4-6-thinking',
      model: 'Claude Opus 4.6 (Thinking)',
      description: 'Claude Opus thinking model.',
      aliases: ['opus'],
    ),
    ModelConfig(
      name: 'gpt-oss-120b-medium',
      model: 'GPT-OSS 120B (Medium)',
      description: 'Open-weight GPT-OSS model.',
      aliases: ['oss'],
    ),
  ];

  static const byAgent = {
    'claude': claudeModels,
    'gemini': geminiModels,
    'codex': codexModels,
    'cursor': cursorModels,
    'antigravity': antigravityModels,
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

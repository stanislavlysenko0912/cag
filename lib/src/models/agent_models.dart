import '../agents/agent_id.dart';
import 'model_config.dart';

/// Canonical model definitions for all agents.
class AgentModelRegistry {
  const AgentModelRegistry._();

  static final claudeModels = [
    ModelConfig(name: 'claude-fable-5', scores: ModelScores(cost: 2, intelligence: 9, speed: 3, taste: 7), isDefault: true),
    ModelConfig(
      name: 'claude-sonnet-4-6',
      scores: ModelScores(cost: 5, intelligence: 5, speed: 7, taste: 7),
      isDefault: true,
      aliases: ['sonnet'],
    ),
    ModelConfig(name: 'claude-opus-4-8', scores: ModelScores(cost: 4, intelligence: 7, speed: 4, taste: 8), aliases: ['opus']),
    ModelConfig(name: 'claude-haiku-4-5', scores: ModelScores(cost: 10, intelligence: 3, speed: 10, taste: 2), aliases: ['haiku']),
  ];

  static final geminiModels = [
    ModelConfig(
      name: 'gemini-3-flash-preview',
      scores: ModelScores(cost: 8, intelligence: 7, speed: 8, taste: 5),
      isDefault: true,
      aliases: ['flash'],
    ),
    ModelConfig(name: 'gemini-3.1-pro-preview', scores: ModelScores(cost: 4, intelligence: 9, speed: 5, taste: 6), aliases: ['pro']),
    ModelConfig(
      name: 'gemini-3.1-flash-lite-preview',
      scores: ModelScores(cost: 10, intelligence: 5, speed: 10, taste: 3),
      aliases: ['flash-lite'],
    ),
  ];

  static final codexModels = [
    ModelConfig(
      name: 'gpt-5.6-sol',
      description: 'frontier agentic coding model',
      scores: ModelScores(cost: 8, intelligence: 8, speed: 6, taste: 6),
      isDefault: true,
      aliases: ['sol', 'gpt-5.6', 'gpt'],
    ),
    ModelConfig(
      name: 'gpt-5.6-terra',
      description: 'everyday agentic coding model',
      scores: ModelScores(cost: 9, intelligence: 7, speed: 7, taste: 5),
      aliases: ['terra'],
    ),
    ModelConfig(
      name: 'gpt-5.6-luna',
      description: 'lightweight agentic coding model',
      scores: ModelScores(cost: 10, intelligence: 6, speed: 8, taste: 4),
      aliases: ['luna'],
    ),
    ModelConfig(
      name: 'gpt-5.3-codex',
      description: 'finding subtle bugs',
      scores: ModelScores(cost: 9, intelligence: 8, speed: 5, taste: 6),
      aliases: ['codex'],
    ),
    ModelConfig(name: 'gpt-5.5-mini', scores: ModelScores(cost: 10, intelligence: 6, speed: 8, taste: 4), aliases: ['mini']),
  ];

  /// Curated Cursor Agent models for `cag cursor -m`.
  ///
  /// Discover the full account-specific slug list with
  /// `cursor-agent models` (alias: `cursor-agent --list-models`).
  /// Refresh this curated list when new slugs appear there.
  static final cursorModels = [
    ModelConfig(name: 'composer-2.5-fast', scores: ModelScores(cost: 7, intelligence: 7, speed: 9, taste: 6), isDefault: true),
    ModelConfig(name: 'composer-2.5', scores: ModelScores(cost: 8, intelligence: 7, speed: 7, taste: 6)),
    ModelConfig(name: 'gemini-3.6-flash', scores: ModelScores(cost: 8, intelligence: 7, speed: 8, taste: 5)),
    ModelConfig(name: 'gemini-3.1-pro', scores: ModelScores(cost: 4, intelligence: 9, speed: 5, taste: 6)),
    ModelConfig(name: 'gpt-5.5-high', scores: ModelScores(cost: 8, intelligence: 9, speed: 4, taste: 5)),
    ModelConfig(
      name: 'cursor-grok-4.5-high',
      description: 'contrasting second opinion',
      scores: ModelScores(cost: 8, intelligence: 7, speed: 6, taste: 6),
      aliases: ['grok-4.5', 'grok'],
    ),
    ModelConfig(
      name: 'cursor-grok-4.5-high-fast',
      scores: ModelScores(cost: 7, intelligence: 7, speed: 8, taste: 6),
      aliases: ['grok-4.5-fast', 'grok-fast'],
    ),
    ModelConfig(name: 'claude-opus-4-8-thinking-max', scores: ModelScores(cost: 4, intelligence: 7, speed: 3, taste: 8)),
  ];

  static final antigravityModels = [
    ModelConfig(
      name: 'gemini-3-6-flash-medium',
      model: 'Gemini 3.6 Flash (Medium)',
      scores: ModelScores(cost: 7, intelligence: 7, speed: 7, taste: 5),
      isDefault: true,
      aliases: ['flash'],
    ),
    ModelConfig(
      name: 'gemini-3-6-flash-high',
      model: 'Gemini 3.6 Flash (High)',
      scores: ModelScores(cost: 5, intelligence: 8, speed: 6, taste: 5),
      aliases: ['flash-high'],
    ),
    ModelConfig(
      name: 'gemini-3-6-flash-low',
      model: 'Gemini 3.6 Flash (Low)',
      scores: ModelScores(cost: 9, intelligence: 6, speed: 9, taste: 4),
      aliases: ['flash-low'],
    ),
    ModelConfig(
      name: 'gemini-3-1-pro-high',
      model: 'Gemini 3.1 Pro (High)',
      scores: ModelScores(cost: 4, intelligence: 9, speed: 5, taste: 6),
      aliases: ['pro-high'],
    ),
    ModelConfig(
      name: 'gemini-3-1-pro-low',
      model: 'Gemini 3.1 Pro (Low)',
      scores: ModelScores(cost: 7, intelligence: 8, speed: 6, taste: 5),
      aliases: ['pro-low'],
    ),
    ModelConfig(
      name: 'claude-sonnet-4-6-thinking',
      model: 'Claude Sonnet 4.6 (Thinking)',
      scores: ModelScores(cost: 5, intelligence: 5, speed: 5, taste: 7),
      aliases: ['sonnet'],
    ),
    ModelConfig(
      name: 'claude-opus-4-6-thinking',
      model: 'Claude Opus 4.6 (Thinking)',
      scores: ModelScores(cost: 4, intelligence: 7, speed: 3, taste: 8),
      aliases: ['opus'],
    ),
    ModelConfig(
      name: 'gpt-oss-120b-medium',
      model: 'GPT-OSS 120B (Medium)',
      scores: ModelScores(cost: 9, intelligence: 6, speed: 6, taste: 4),
      aliases: ['oss'],
    ),
  ];

  static final byAgent = {
    AgentId.claude: claudeModels,
    AgentId.gemini: geminiModels,
    AgentId.codex: codexModels,
    AgentId.cursor: cursorModels,
    AgentId.antigravity: antigravityModels,
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

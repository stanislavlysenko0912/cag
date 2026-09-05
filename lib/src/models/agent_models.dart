import '../agents/agent_id.dart';
import 'model_config.dart';

/// Canonical model definitions for all agents.
class AgentModelRegistry {
  const AgentModelRegistry._();

  static final claudeModels = [
    ModelConfig(
      name: 'claude-opus-5',
      description: 'complex agentic coding and enterprise work',
      scores: ModelScores(cost: 4, intelligence: 8, speed: 5, taste: 9),
      isDefault: true,
      aliases: ['opus'],
    ),
    ModelConfig(
      name: 'claude-fable-5-1',
      description: 'demanding reasoning and long-horizon agentic work',
      scores: ModelScores(cost: 2, intelligence: 10, speed: 3, taste: 7),
      aliases: ['fable', 'fable-5-1', 'claude-fable-5'],
    ),
    ModelConfig(
      name: 'claude-sonnet-5',
      description: 'best combination of speed and intelligence',
      scores: ModelScores(cost: 5, intelligence: 8, speed: 7, taste: 7),
      aliases: ['sonnet'],
    ),
    ModelConfig(
      name: 'claude-haiku-4-5',
      description: 'fastest model with near-frontier intelligence',
      scores: ModelScores(cost: 10, intelligence: 5, speed: 10, taste: 4),
      aliases: ['haiku', 'claude-haiku-4-5-20251001'],
    ),
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
      name: 'gpt-6-astra',
      description: 'frontier model for complex, demanding work',
      scores: ModelScores(cost: 6, intelligence: 10, speed: 6, taste: 8),
      isDefault: true,
      aliases: ['astra', 'gpt-6'],
    ),
    ModelConfig(
      name: 'gpt-5.6-sol',
      description: 'frontier agentic coding model',
      scores: ModelScores(cost: 8, intelligence: 8, speed: 6, taste: 6),
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
      name: 'gpt-5.5',
      description: 'frontier model for complex coding and research',
      scores: ModelScores(cost: 7, intelligence: 8, speed: 5, taste: 6),
      aliases: ['gpt-5'],
    ),
    ModelConfig(
      name: 'gpt-5.4-mini',
      scores: ModelScores(cost: 10, intelligence: 6, speed: 8, taste: 4),
      aliases: ['mini', 'gpt-5.5-mini'],
    ),
    ModelConfig(
      name: 'gpt-5.2',
      description: 'optimized for long-running agents',
      scores: ModelScores(cost: 8, intelligence: 7, speed: 6, taste: 5),
    ),
  ];

  /// Curated Cursor Agent models for `cag cursor -m`.
  ///
  /// Discover the full account-specific slug list with
  /// `cursor-agent models` (alias: `cursor-agent --list-models`).
  /// Refresh this curated list when new slugs appear there.
  static final cursorModels = [
    ModelConfig(name: 'composer-2.5-fast', scores: ModelScores(cost: 7, intelligence: 7, speed: 9, taste: 6), isDefault: true),
    ModelConfig(name: 'composer-2.5', scores: ModelScores(cost: 8, intelligence: 7, speed: 7, taste: 6)),
    ModelConfig(
      name: 'gemini-3.8-flash-high',
      scores: ModelScores(cost: 8, intelligence: 8, speed: 8, taste: 5),
      aliases: ['gemini-3.8-flash', 'gemini-3.6-flash'],
    ),
    ModelConfig(name: 'gemini-3.1-pro', scores: ModelScores(cost: 4, intelligence: 9, speed: 5, taste: 6)),
    ModelConfig(name: 'gpt-5.6-sol-high', scores: ModelScores(cost: 7, intelligence: 9, speed: 5, taste: 6), aliases: ['sol', 'gpt-5.6']),
    ModelConfig(name: 'gpt-5.5-high', scores: ModelScores(cost: 8, intelligence: 9, speed: 4, taste: 5)),
    ModelConfig(
      name: 'cursor-grok-4.6-high',
      description: 'contrasting second opinion',
      scores: ModelScores(cost: 8, intelligence: 7, speed: 6, taste: 6),
      aliases: ['grok-4.6', 'grok', 'cursor-grok-4.5-high', 'grok-4.5'],
    ),
    ModelConfig(
      name: 'cursor-grok-4.6-high-fast',
      scores: ModelScores(cost: 7, intelligence: 7, speed: 8, taste: 6),
      aliases: ['grok-4.6-fast', 'grok-fast', 'cursor-grok-4.5-high-fast', 'grok-4.5-fast'],
    ),
    ModelConfig(
      name: 'claude-sonnet-5-thinking-high',
      scores: ModelScores(cost: 6, intelligence: 8, speed: 6, taste: 7),
      aliases: ['sonnet'],
    ),
    ModelConfig(name: 'claude-opus-5-thinking-max', scores: ModelScores(cost: 4, intelligence: 9, speed: 3, taste: 9), aliases: ['opus']),
  ];

  static final antigravityModels = [
    ModelConfig(
      name: 'gemini-3-8-flash-medium',
      model: 'Gemini 3.8 Flash (Medium)',
      scores: ModelScores(cost: 7, intelligence: 8, speed: 8, taste: 6),
      isDefault: true,
      aliases: ['flash', 'gemini-3.8-flash-medium'],
    ),
    ModelConfig(
      name: 'gemini-3-8-flash-high',
      model: 'Gemini 3.8 Flash (High)',
      scores: ModelScores(cost: 5, intelligence: 9, speed: 7, taste: 6),
      aliases: ['flash-high', 'gemini-3.8-flash-high'],
    ),
    ModelConfig(
      name: 'gemini-3-8-flash-low',
      model: 'Gemini 3.8 Flash (Low)',
      scores: ModelScores(cost: 9, intelligence: 7, speed: 9, taste: 5),
      aliases: ['flash-low', 'gemini-3.8-flash-low'],
    ),
    ModelConfig(
      name: 'gemini-3-1-pro-high',
      model: 'Gemini 3.1 Pro (High)',
      scores: ModelScores(cost: 4, intelligence: 9, speed: 5, taste: 6),
      aliases: ['pro-high', 'pro', 'gemini-3.1-pro-high'],
    ),
    ModelConfig(
      name: 'gemini-3-1-pro-low',
      model: 'Gemini 3.1 Pro (Low)',
      scores: ModelScores(cost: 7, intelligence: 8, speed: 6, taste: 5),
      aliases: ['pro-low', 'gemini-3.1-pro-low'],
    ),
    ModelConfig(
      name: 'claude-sonnet-4-6',
      model: 'Claude Sonnet 4.6 (Thinking)',
      scores: ModelScores(cost: 5, intelligence: 5, speed: 5, taste: 7),
      aliases: ['sonnet', 'claude-sonnet-4-6-thinking'],
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

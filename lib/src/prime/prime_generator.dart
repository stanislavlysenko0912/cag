import '../models/models.dart';
import 'command_metadata.dart';

/// Generates markdown documentation from command metadata.
class PrimeGenerator {
  const PrimeGenerator();

  /// Generate full onboarding markdown.
  String generate(
    List<CommandMetadata> commands, {
    required Map<String, AgentConfig> agentConfigs,
  }) {
    final buffer = StringBuffer();
    final enabledAgents = agentConfigs.entries
        .where((entry) => entry.value.enabled)
        .map((entry) => entry.key)
        .toSet();

    final agentCommands = commands
        .where((c) => enabledAgents.contains(c.name))
        .map((c) {
          final config = agentConfigs[c.name];
          if (config == null || config.availableModels.isEmpty) return c;
          return c.copyWith(models: config.availableModels);
        })
        .toList();

    final agentExamples = _agentExamples(agentCommands);
    final sessionExample = agentExamples.isNotEmpty
        ? agentExamples.first
        : (agent: 'agent', model: 'model');

    buffer.writeln('# CLI Agents CAG - tool usage guide');
    buffer.writeln();
    buffer.writeln(
      '> User has CLI wrapper for AI agents, named "cag". Use it to get another opinion, search code, validate ideas, or discuss architecture.',
    );
    buffer.writeln();
    buffer.writeln(
      '> Always provide a detailed task description (context, constraints, goals, and expected output). Short prompts lead to weak results.',
    );
    buffer.writeln();

    // Agents section
    buffer.writeln('## Agents');
    buffer.writeln();

    for (final cmd in agentCommands) {
      _writeAgent(buffer, cmd);
    }

    // Consensus section - separate and detailed
    final compare = commands.where((c) => c.name == 'compare').firstOrNull;
    final consensus = commands.where((c) => c.name == 'consensus').firstOrNull;
    if (compare != null) {
      _writeCompare(buffer, agentCommands, agentExamples);
    }
    if (consensus != null) {
      _writeConsensus(buffer, agentCommands, agentExamples);
    }

    final council = commands.where((c) => c.name == 'council').firstOrNull;
    if (council != null) {
      _writeCouncil(buffer, agentCommands, agentExamples);
    }

    // Session concept - explain first
    buffer.writeln('## How Sessions Work');
    buffer.writeln();
    buffer.writeln(
      'Every regular agent conversation uses a universal `session_id`. If a tool returns `session_id`, that conversation can be continued later with the matching agent command and `-r <session_id>`.',
    );
    buffer.writeln();
    buffer.writeln(
      'Any other returned ID is an internal CAG wrapper ID for its own flow and is not interchangeable with `session_id`.',
    );
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln(
      'cag ${sessionExample.agent} "How should I organize caching?"',
    );
    buffer.writeln('# Output: session_id: abc-123');
    buffer.writeln('# ... response ...');
    buffer.writeln();
    buffer.writeln(
      'cag ${sessionExample.agent} -r abc-123 "What if data changes frequently?"',
    );
    buffer.writeln(
      '# Continues same conversation, agent remembers previous context',
    );
    buffer.writeln('```');
    buffer.writeln();

    // Common flags
    // Commited for now, not need for agent context
    // buffer.writeln('## Common Flags');
    // buffer.writeln();
    // buffer.writeln('| Flag | Description |');
    // buffer.writeln('|------|-------------|');
    // buffer.writeln('| `-m, --model` | Model override (use alias or full name) |');
    // buffer.writeln('| `-r, --resume` | Continue conversation with session_id |');
    // buffer.writeln('| `-j, --json` | Full JSON output |');
    // buffer.writeln('| `--meta` | Include token/latency metadata |');
    // buffer.writeln();

    // Tips
    buffer.writeln('## Tips');
    buffer.writeln();
    buffer.writeln('- All agents run in current directory with file access');
    buffer.writeln(
      "- Don't delegate code writing — ask for direction/validation",
    );
    buffer.writeln(
      '- Conversations are not just question-answer — use multi-turn dialogue (resume via session_id) to iterate, challenge ideas, and reach better solutions',
    );
    buffer.writeln('- Provide your proposal in consensus mode');
    buffer.writeln();

    // Required
    buffer.writeln('## Required');
    buffer.writeln();
    buffer.writeln(
      '- If a tool returns `session_id`, treat it as a reusable agent conversation handle.',
    );
    buffer.writeln(
      '- Any non-`session_id` returned by CAG belongs to that wrapper flow and should not be treated as a regular agent session handle.',
    );
    buffer.writeln(
      '- At the start of a conversation, you **MUST** provide maximum useful information: background, constraints, goals, current state, and desired output format.',
    );
    buffer.writeln();

    return buffer.toString();
  }

  void _writeAgent(StringBuffer buffer, CommandMetadata cmd) {
    buffer.writeln('### ${cmd.name}');
    buffer.writeln();
    buffer.writeln(cmd.description);
    buffer.writeln();

    // Models table
    if (cmd.models.isNotEmpty) {
      buffer.writeln('| Model | Alias | Use for |');
      buffer.writeln('|-------|-------|---------|');
      for (final model in cmd.models) {
        final name = model.isDefault ? '`${model.name}` ⭐' : '`${model.name}`';
        final alias = model.aliases.isNotEmpty
            ? '`${model.aliases.first}`'
            : '—';
        buffer.writeln('| $name | $alias | ${model.description} |');
      }
      buffer.writeln();
    }

    // Specific flags, only if not an agent
    if (cmd.flags.isNotEmpty && cmd.models.isEmpty) {
      buffer.writeln('**Flags:** ');
      final flagStrs = cmd.flags.map((f) => '`${f.formatted}`').join(', ');
      buffer.writeln(flagStrs);
      buffer.writeln();
    }
  }

  void _writeConsensus(
    StringBuffer buffer,
    List<CommandMetadata> agentCommands,
    List<({String agent, String model})> agentExamples,
  ) {
    final first = agentExamples.isNotEmpty
        ? agentExamples.first
        : (agent: 'agent', model: 'model');
    final second = agentExamples.length > 1 ? agentExamples[1] : first;
    final agentList = _formatAgentList(agentCommands);

    buffer.writeln('## Consensus');
    buffer.writeln();
    buffer.writeln(
      'Multi-model consensus for complex decisions. Models run in parallel with stance-based prompts and don\'t see each other\'s responses.',
    );
    buffer.writeln();

    // How it works
    buffer.writeln('### How It Works');
    buffer.writeln();
    buffer.writeln(
      '1. You provide detailed task context (prompt) and optionally your proposal (`-p`)',
    );
    buffer.writeln(
      '2. Each model evaluates from its assigned stance (for/against/neutral)',
    );
    buffer.writeln(
      '3. Returns `consensus_id` — use with `-r` to ask follow-up questions',
    );
    buffer.writeln();

    // Usage
    buffer.writeln('### Usage');
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln('# Simple question to multiple models');
    buffer.writeln(
      'cag consensus -a "${first.agent}:${first.model}:for" -a "${second.agent}:${second.model}:against" "Should we use microservices?"',
    );
    buffer.writeln('# Output: consensus_id: cons-abc123');
    buffer.writeln();
    buffer.writeln(
      '# With your proposal for models to evaluate. It is desirable to provide this information',
    );
    buffer.writeln('cag consensus \\');
    buffer.writeln('  -p "Use Redis with 5min TTL" \\');
    buffer.writeln(
      '  -a "${first.agent}:${first.model}:for" -a "${second.agent}:${second.model}:against" \\',
    );
    buffer.writeln('  "Need caching for user profiles, 10k RPM"');
    buffer.writeln();
    buffer.writeln('# Continue conversation (context preserved)');
    buffer.writeln('cag consensus -r cons-abc123 "What about costs?"');
    buffer.writeln();
    buffer.writeln('# List saved sessions');
    buffer.writeln('cag consensus --list');
    buffer.writeln();
    buffer.writeln('# Inspect a saved session');
    buffer.writeln('cag consensus --inspect cons-abc123');
    buffer.writeln('```');
    buffer.writeln();

    // Participant format
    buffer.writeln('### Participant Format');
    buffer.writeln();
    buffer.writeln('`-a "agent:model:stance"` — all three required');
    buffer.writeln();
    buffer.writeln('- **agent**: $agentList');
    buffer.writeln('- **model**: full name or alias (see agent tables above)');
    buffer.writeln(
      '- **stance**: `for` (find benefits), `against` (find risks), `neutral` (balanced)',
    );
    buffer.writeln();
  }

  void _writeCompare(
    StringBuffer buffer,
    List<CommandMetadata> agentCommands,
    List<({String agent, String model})> agentExamples,
  ) {
    final first = agentExamples.isNotEmpty
        ? agentExamples.first
        : (agent: 'agent', model: 'model');
    final second = agentExamples.length > 1 ? agentExamples[1] : first;
    final agentList = _formatAgentList(agentCommands);

    buffer.writeln('## Compare');
    buffer.writeln();
    buffer.writeln(
      'Parallel multi-agent compare without synthesis. Use it when you want independent answers first and decide yourself which branch to continue.',
    );
    buffer.writeln();

    buffer.writeln('### How It Works');
    buffer.writeln();
    buffer.writeln('1. Sends the same prompt to multiple agents in parallel');
    buffer.writeln('2. Stores the run under `compare_id`');
    buffer.writeln(
      '3. Returns per-agent answer `session_id` values for branch follow-up with the underlying agent command',
    );
    buffer.writeln();

    buffer.writeln('### Usage');
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln(
      'cag compare -a "${first.agent}:${first.model}" -a "${second.agent}:${second.model}" "How should we cache profiles?"',
    );
    buffer.writeln('# Output: compare_id: cmp-abc123');
    buffer.writeln('# Each answer also includes its own session_id');
    buffer.writeln();
    buffer.writeln(
      '# Continue one branch with its session_id using the same agent command',
    );
    buffer.writeln(
      'cag ${first.agent} -r abc-123 "Continue this direction with concrete implementation details"',
    );
    buffer.writeln();
    buffer.writeln('# List saved compare runs');
    buffer.writeln('cag compare --list');
    buffer.writeln();
    buffer.writeln('# Inspect a saved run');
    buffer.writeln('cag compare --inspect cmp-abc123');
    buffer.writeln('```');
    buffer.writeln();

    buffer.writeln('### Participant Format');
    buffer.writeln();
    buffer.writeln('`-a "agent:model"`');
    buffer.writeln();
    buffer.writeln('- **agent**: $agentList');
    buffer.writeln('- **model**: full name or alias (see agent tables above)');
    buffer.writeln();
  }

  void _writeCouncil(
    StringBuffer buffer,
    List<CommandMetadata> agentCommands,
    List<({String agent, String model})> agentExamples,
  ) {
    final first = agentExamples.isNotEmpty
        ? agentExamples.first
        : (agent: 'agent', model: 'model');
    final second = agentExamples.length > 1 ? agentExamples[1] : first;
    final third = agentExamples.length > 2 ? agentExamples[2] : first;
    final agentList = _formatAgentList(agentCommands);

    buffer.writeln('## Council');
    buffer.writeln();
    buffer.writeln(
      'Multi-stage council: independent answers, peer reviews with ranking, and chairman synthesis.',
    );
    buffer.writeln();
    buffer.writeln(
      'Council stores a `council_id` for inspection and may expose answer `session_id` values for branch follow-up. `council_id` is not a regular agent session handle.',
    );
    buffer.writeln();

    buffer.writeln('### How It Works');
    buffer.writeln();
    buffer.writeln('1. Each participant answers independently');
    buffer.writeln('2. Each participant reviews and ranks anonymized answers');
    buffer.writeln('3. Chairman synthesizes a final response (new session)');
    buffer.writeln();
    buffer.writeln(
      'Chairman tip: pick the strongest reasoning model available for best synthesis.',
    );
    buffer.writeln();

    buffer.writeln('### Usage');
    buffer.writeln();
    buffer.writeln('```bash');
    buffer.writeln(
      'cag council -a "${first.agent}:${first.model}" -a "${second.agent}:${second.model}" -c "${third.agent}:${third.model}" "Design a caching strategy"',
    );
    buffer.writeln('# Output: council_id: council_abc123');
    buffer.writeln('# Use --include-answers to see answer session_id values');
    buffer.writeln('```');
    buffer.writeln();

    buffer.writeln('### Member Format');
    buffer.writeln();
    buffer.writeln('`-a "agent:model"` and `-c "agent:model"`');
    buffer.writeln();
    buffer.writeln('- **agent**: $agentList');
    buffer.writeln('- **model**: full name or alias (see agent tables above)');
    buffer.writeln();
  }

  List<({String agent, String model})> _agentExamples(
    List<CommandMetadata> agentCommands,
  ) {
    return agentCommands.map((cmd) {
      final model = cmd.defaultModel;
      final modelToken = model == null
          ? 'model'
          : (model.aliases.isNotEmpty ? model.aliases.first : model.name);
      return (agent: cmd.name, model: modelToken);
    }).toList();
  }

  String _formatAgentList(List<CommandMetadata> agentCommands) {
    if (agentCommands.isEmpty) {
      return '`agent`';
    }
    return agentCommands.map((cmd) => '`${cmd.name}`').join(', ');
  }
}

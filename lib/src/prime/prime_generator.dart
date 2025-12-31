import 'command_metadata.dart';

/// Generates markdown documentation from command metadata.
class PrimeGenerator {
  const PrimeGenerator();

  /// Generate full onboarding markdown.
  String generate(
    List<CommandMetadata> commands, {
    Set<String>? enabledAgents,
  }) {
    final buffer = StringBuffer();
    final agentCommands = _agentCommands(commands, enabledAgents);
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
    final consensus = commands.where((c) => c.name == 'consensus').firstOrNull;
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
      'Every agent call returns a `session_id`. Pass it with `-r` to continue the conversation with full context preserved.',
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
    buffer.writeln('- Provide your proposal in consensus mode');
    buffer.writeln();

    // Required
    buffer.writeln('## Required');
    buffer.writeln();
    buffer.writeln(
      '- You **MUST ALLWAYS** pass the `session_id` with `-r` flag, or `consensus_id` if you are using consensus mode, to continue the conversation with the agent on same task/subject',
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
    buffer.writeln('Council runs are stateless (no resume).');
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

  List<CommandMetadata> _agentCommands(
    List<CommandMetadata> commands,
    Set<String>? enabledAgents,
  ) {
    final agentCommands = commands.where((c) => c.models.isNotEmpty);
    if (enabledAgents == null) {
      return agentCommands.toList();
    }
    return agentCommands.where((c) => enabledAgents.contains(c.name)).toList();
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

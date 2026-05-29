import '../models/models.dart';
import 'command_metadata.dart';

/// All CLI command definitions with models and examples.
class CommandDefinitions {
  const CommandDefinitions._();

  static const claude = CommandMetadata(
    name: 'claude',
    description:
        'Run ClaudeCode CLI agent from Anthropic. Use for code review, second opinions, complex reasoning.',
    models: AgentModelRegistry.claudeModels,
    flags: [
      CommandFlag(
        flag: '--system',
        shortFlag: '-s',
        description: 'System prompt (appended)',
      ),
    ],
  );

  static const gemini = CommandMetadata(
    name: 'gemini',
    description:
        'Run Gemini CLI agent from Google. Use for quick code lookup and analysis.',
    models: AgentModelRegistry.geminiModels,
    flags: [
      CommandFlag(
        flag: '--system',
        shortFlag: '-s',
        description: 'System prompt',
      ),
    ],
  );

  static const codex = CommandMetadata(
    name: 'codex',
    description:
        'Run Codex CLI agent from OpenAI. Use for architectural advice, alternative perspective.',
    models: AgentModelRegistry.codexModels,
    flags: [
      CommandFlag(
        flag: '--system',
        shortFlag: '-s',
        description: 'System prompt',
      ),
    ],
  );

  static const cursor = CommandMetadata(
    name: 'cursor',
    description: 'Run Cursor Agent CLI. Use for Cursor Composer workflows.',
    models: AgentModelRegistry.cursorModels,
    flags: [
      CommandFlag(
        flag: '--system',
        shortFlag: '-s',
        description: 'System prompt (prepended to prompt)',
      ),
    ],
  );

  static const antigravity = CommandMetadata(
    name: 'antigravity',
    description:
        'Run Antigravity CLI agent. Model selection comes from AGY CLI /model or settings.',
    models: AgentModelRegistry.antigravityModels,
    flags: [
      CommandFlag(
        flag: '--system',
        shortFlag: '-s',
        description: 'System prompt',
      ),
    ],
  );

  static const consensus = CommandMetadata(
    name: 'consensus',
    description:
        '''Multi-model consensus for complex decisions. Models run in parallel with stance-based prompts (blinded).

**Arguments:**
- `<prompt>` — Detailed task context: situation, constraints, goals, expected output
- `-p/--proposal` — Your proposal/reasoning that models will evaluate

**Usage pattern:**
```
cag consensus -p "<your proposal>" -a "agent:model:stance" ... "<task context>"
```''',
    examples: [
      CommandExample(
        command:
            'cag consensus -a "gemini:pro:for" -a "codex:gpt:against" "Should we use microservices for new payment system?"',
        description: 'simple question without proposal',
      ),
      CommandExample(
        command:
            'cag consensus -p "Use Redis with 5min TTL, invalidate on write" -a "gemini:pro:for" -a "codex:gpt:against" "Need caching for user profiles, 10k RPM, data changes hourly"',
        description: 'with your proposal to evaluate',
      ),
      CommandExample(
        command: 'cag consensus -r cons-abc123 "What about costs?"',
        description: 'follow-up question',
      ),
      CommandExample(
        command: 'cag consensus --list',
        description: 'list sessions',
      ),
      CommandExample(
        command: 'cag consensus --inspect cons-abc123',
        description: 'inspect a saved consensus session',
      ),
    ],
    flags: [
      CommandFlag(
        flag: '--add',
        shortFlag: '-a',
        description: 'Add participant: agent:model:stance',
      ),
      CommandFlag(
        flag: '--title',
        description: 'Optional title override for the consensus run',
      ),
      CommandFlag(
        flag: '--proposal',
        shortFlag: '-p',
        description: 'Your proposal/reasoning for models to evaluate',
      ),
      CommandFlag(
        flag: '--list',
        shortFlag: '-l',
        description: 'List saved sessions (last 25)',
      ),
      CommandFlag(
        flag: '--inspect',
        description: 'Inspect a saved consensus session by consensus_id',
      ),
    ],
    notes:
        'Stances: `for` (find benefits), `against` (find risks), `neutral` (balanced)',
  );

  static const compare = CommandMetadata(
    name: 'compare',
    description: '''Run multiple agents in parallel without synthesis.
Use the returned branch `session_id` with the underlying agent command for follow-up.
`compare_id` is only the saved run identifier.

**Arguments:**
- `<prompt>` — Task or question sent to every participant
- `-a/--add` — Participants (agent:model)
- `--title` — Optional run title override

**Usage pattern:**
```
cag compare -a "agent:model" -a "..." "<prompt>"
```''',
    examples: [
      CommandExample(
        command:
            'cag compare -a "claude:sonnet" -a "codex:gpt" "How should we cache profiles?"',
        description: 'run parallel independent answers',
      ),
      CommandExample(
        command:
            'cag compare --title "Profile caching" -a "claude:sonnet" -a "gemini:pro" "Long prompt..."',
        description: 'override compare title',
      ),
      CommandExample(
        command: 'cag compare --list',
        description: 'list saved compare runs',
      ),
      CommandExample(
        command: 'cag compare --inspect cmp_abc123',
        description: 'inspect a saved compare run',
      ),
    ],
    flags: [
      CommandFlag(
        flag: '--add',
        shortFlag: '-a',
        description: 'Add participant: agent:model',
      ),
      CommandFlag(
        flag: '--title',
        description: 'Optional title override for the compare run',
      ),
      CommandFlag(
        flag: '--list',
        shortFlag: '-l',
        description: 'List saved compare runs',
      ),
      CommandFlag(
        flag: '--inspect',
        description: 'Inspect a saved compare run by compare_id',
      ),
    ],
    notes:
        'Creates regular agent sessions and stores their session IDs for later follow-up. `compare_id` is not resumable as an agent session.',
  );

  static const council = CommandMetadata(
    name: 'council',
    description: '''Multi-stage council with ranking and chairman synthesis.

**Arguments:**
- `<prompt>` — Detailed task context/question (goals, constraints, expected output)
- `-a/--add` — Participants (agent:model)
- `-c/--chairman` — Chairman (agent:model)
- `--title` — Optional run title override

**Usage pattern:**
```
cag council -a "agent:model" -a "..." -c "agent:model" "<prompt>"
```''',
    examples: [
      CommandExample(
        command:
            'cag council -a "gemini:pro" -a "codex:gpt" -c "claude:sonnet" "Design a caching strategy for 10k RPM API"',
        description: 'multi-stage council with chairman synthesis',
      ),
      CommandExample(
        command: 'cag council --inspect council_abc123',
        description: 'inspect a saved council run',
      ),
    ],
    flags: [
      CommandFlag(
        flag: '--add',
        shortFlag: '-a',
        description: 'Add participant: agent:model',
      ),
      CommandFlag(
        flag: '--chairman',
        shortFlag: '-c',
        description: 'Chairman: agent:model (required)',
      ),
      CommandFlag(
        flag: '--title',
        description: 'Optional title override for the council run',
      ),
      CommandFlag(
        flag: '--list',
        shortFlag: '-l',
        description: 'List saved council runs',
      ),
      CommandFlag(
        flag: '--inspect',
        description: 'Inspect a saved council run by council_id',
      ),
      CommandFlag(
        flag: '--include-answers',
        description: 'Include participant answers and session IDs in output',
      ),
    ],
    notes:
        'Stages: answers → reviews/ranking → chairman synthesis. `council_id` is for inspection; answer `session_id` values are the regular continuation handles.',
  );

  /// All commands for iteration.
  static const all = [
    claude,
    gemini,
    codex,
    cursor,
    antigravity,
    consensus,
    compare,
    council,
  ];

  /// Find command by name.
  static CommandMetadata? find(String name) {
    return all.where((c) => c.name == name).firstOrNull;
  }
}

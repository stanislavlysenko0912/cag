import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

class PrimeCommand extends Command<void> {
  PrimeCommand({required Map<String, AgentConfig> agentConfigs})
    : _agentConfigs = agentConfigs;

  final Map<String, AgentConfig> _agentConfigs;

  @override
  String get name => 'prime';

  @override
  String get description => 'Output usage docs for AI agents (markdown)';

  @override
  Future<void> run() async {
    const generator = PrimeGenerator();
    final markdown = generator.generate([
      ...CommandDefinitions.all,
      for (final definition in AgentCatalog.definitions)
        if (CommandDefinitions.find(definition.name) == null)
          CommandMetadata(
            name: definition.name,
            description: definition.descriptionText,
            models: _agentConfigs[definition.name]?.availableModels ?? const [],
          ),
    ], agentConfigs: _agentConfigs);
    print(markdown);
  }
}

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

class PrimeCommand extends Command<void> {
  PrimeCommand({required Set<String> enabledAgents}) : _enabledAgents = enabledAgents;

  final Set<String> _enabledAgents;

  @override
  String get name => 'prime';

  @override
  String get description => 'Output usage docs for AI agents (markdown)';

  @override
  Future<void> run() async {
    const generator = PrimeGenerator();
    final markdown = generator.generate(CommandDefinitions.all, enabledAgents: _enabledAgents);
    print(markdown);
  }
}

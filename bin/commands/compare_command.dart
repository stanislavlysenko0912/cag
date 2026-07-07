import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'output_formatter.dart';
import 'stdin_prompt.dart';

/// Run multi-agent compare without synthesis.
class CompareCommand extends Command<void> {
  /// Creates a compare command.
  CompareCommand({required Map<String, AgentConfig> agentConfigs})
    : _agentConfigs = agentConfigs {
    argParser
      ..addMultiOption('add', abbr: 'a', help: 'Add participant: agent:model')
      ..addOption('title', help: 'Optional title override for the compare run')
      ..addFlag(
        'list',
        abbr: 'l',
        negatable: false,
        help: 'List saved compare runs',
      )
      ..addOption('inspect', help: 'Inspect a saved compare run by compare_id')
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output full JSON response',
      );
  }

  final Map<String, AgentConfig> _agentConfigs;

  Set<String> get _enabledAgents => _agentConfigs.entries
      .where((entry) => entry.value.enabled)
      .map((entry) => entry.key)
      .toSet();

  @override
  String get name => 'compare';

  @override
  String get description => 'Run multiple agents in parallel without synthesis';

  @override
  String get invocation =>
      '$name -a "agent:model" -a "..." [--title "..."] <prompt>';

  @override
  Future<void> run() async {
    final listRuns = argResults!['list'] as bool;
    final inspectId = argResults!['inspect'] as String?;
    if (listRuns && inspectId != null) {
      throw UsageException('Cannot use --list and --inspect together', usage);
    }
    _validatePersistenceMode(
      isPersistenceMode: listRuns || inspectId != null,
      hasAddOptions: (argResults!['add'] as List<String>).isNotEmpty,
      hasTitle: (argResults!['title'] as String?) != null,
      hasPrompt: argResults!.rest.isNotEmpty,
    );
    if (listRuns) {
      await _listRuns(argResults!['json'] as bool);
      return;
    }
    if (inspectId != null) {
      await _inspectRun(inspectId, argResults!['json'] as bool);
      return;
    }

    if (_enabledAgents.isEmpty) {
      stderr.writeln(
        'No agents are enabled. Enable at least one agent in config.',
      );
      exit(1);
    }

    final addOptions = argResults!['add'] as List<String>;
    final title = argResults!['title'] as String?;
    final outputJson = argResults!['json'] as bool;
    final rest = argResults!.rest;
    final prompt = await readPromptInput(rest);

    if (prompt.isEmpty) {
      throw UsageException('Missing prompt', usage);
    }
    if (addOptions.length < 2) {
      throw UsageException(
        'Compare requires at least 2 participants (-a)',
        usage,
      );
    }

    final participants = addOptions
        .map(
          (input) =>
              CompareParticipant.parse(input, allowedAgents: _enabledAgents),
        )
        .toList();

    final resolvedParticipants = _resolveModels(participants);

    final runner = CompareRunner(agentConfigs: _agentConfigs);

    try {
      final result = await runner.run(
        prompt: prompt,
        title: title ?? buildCompareTitle(prompt),
        participants: resolvedParticipants,
      );

      if (outputJson) {
        _printJsonOutput(result);
        return;
      }
      _printFormattedOutput(result);
    } on ArgumentError catch (error) {
      stderr.writeln('Error: ${error.message}');
      exit(1);
    } on AgentExecutionException catch (error) {
      stderr.writeln(
        'Execution error [${error.failure.summary}]: ${error.failure.message}',
      );
      exit(1);
    }
  }

  void _validatePersistenceMode({
    required bool isPersistenceMode,
    required bool hasAddOptions,
    required bool hasTitle,
    required bool hasPrompt,
  }) {
    if (!isPersistenceMode) {
      return;
    }
    if (hasAddOptions || hasTitle || hasPrompt) {
      throw UsageException(
        'Cannot combine persisted run browsing with prompt or creation flags.',
        usage,
      );
    }
  }

  List<CompareParticipant> _resolveModels(
    List<CompareParticipant> participants,
  ) {
    return participants.map((participant) {
      final config = _agentConfigs[participant.agent];
      if (config == null || config.availableModels.isEmpty) {
        return participant;
      }

      final modelConfig = config.availableModels
          .where((m) => m.matches(participant.model))
          .firstOrNull;
      if (modelConfig == null) {
        final available = config.availableModels
            .map((model) => model.name)
            .join(', ');
        throw UsageException(
          'Unknown model "${participant.model}" for ${participant.agent}. Available: $available',
          usage,
        );
      }
      return participant.copyWith(resolvedModel: modelConfig.resolvedModel);
    }).toList();
  }

  void _printJsonOutput(CompareRun run) {
    print(const JsonEncoder.withIndent('  ').convert(run.toJson()));
  }

  void _printFormattedOutput(CompareRun run) {
    _printRun(run);
  }

  void _printRun(CompareRun run) {
    OutputFormatter.printCompareStart(run.compareId, run.title);
    for (final result in run.results) {
      final participant = result.participant;
      OutputFormatter.printCompareParticipantHeader(
        agent: participant.agent,
        model: participant.model,
      );
      if (result.success) {
        if (participant.sessionId != null) {
          OutputFormatter.printSessionStart(participant.sessionId!);
        }
        if (result.response != null) {
          print(result.response!.content);
        }
      } else {
        OutputFormatter.printFailure(result.failure!);
      }
      print('');
    }
  }

  Future<void> _listRuns(bool outputJson) async {
    final storage = CompareStorage();
    final runs = await storage.loadAll();
    runs.sort((left, right) => right.createdAt.compareTo(left.createdAt));

    if (outputJson) {
      final output = {'runs': runs.map((run) => run.toSummaryJson()).toList()};
      print(const JsonEncoder.withIndent('  ').convert(output));
      return;
    }

    if (runs.isEmpty) {
      print('No compare runs found.');
      return;
    }

    for (final run in runs.take(25)) {
      OutputFormatter.printCompareListItem(run);
    }
  }

  Future<void> _inspectRun(String compareId, bool outputJson) async {
    final storage = CompareStorage();
    final run = await storage.load(compareId);
    if (run == null) {
      stderr.writeln('Compare run not found: $compareId');
      exit(1);
    }

    if (outputJson) {
      print(const JsonEncoder.withIndent('  ').convert(run.toJson()));
      return;
    }

    _printRun(run);
  }
}

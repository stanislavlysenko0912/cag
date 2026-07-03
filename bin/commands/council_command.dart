import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'output_formatter.dart';
import 'stdin_prompt.dart';

/// Runs multi-stage council flows and inspects saved runs.
class CouncilCommand extends Command<void> {
  /// Creates a council command.
  CouncilCommand({required Map<String, AgentConfig> agentConfigs})
    : _agentConfigs = agentConfigs {
    argParser
      ..addMultiOption('add', abbr: 'a', help: 'Add participant: agent:model')
      ..addOption('title', help: 'Optional title override for the council run')
      ..addFlag(
        'list',
        abbr: 'l',
        negatable: false,
        help: 'List saved council runs',
      )
      ..addOption('inspect', help: 'Inspect a saved council run by council_id')
      ..addOption(
        'chairman',
        abbr: 'c',
        help: 'Chairman: agent:model (required)',
      )
      ..addFlag(
        'include-answers',
        negatable: false,
        help: 'Include participant answers and session IDs in output',
      )
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
  String get name => 'council';

  @override
  String get description => '''Run multi-stage council

Stage 1: independent answers.
Stage 2: peer review and ranking.
Stage 3: chairman synthesis.

Chairman tip: choose the strongest reasoning model available for best synthesis.

Council runs are persisted for inspection and follow-up.''';

  @override
  String get invocation =>
      '$name -a "agent:model" -a "..." -c "agent:model" <prompt>';

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
      hasChairman: (argResults!['chairman'] as String?) != null,
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
    final chairmanRaw = argResults!['chairman'] as String?;
    final includeAnswers = argResults!['include-answers'] as bool;
    final outputJson = argResults!['json'] as bool;
    final rest = argResults!.rest;
    final prompt = await readPromptInput(rest);

    if (prompt.isEmpty) {
      throw UsageException('Missing prompt', usage);
    }
    if (addOptions.length < 2) {
      throw UsageException(
        'Council requires at least 2 participants (-a)',
        usage,
      );
    }
    if (chairmanRaw == null || chairmanRaw.trim().isEmpty) {
      throw UsageException('Chairman is required (-c)', usage);
    }

    final participants = addOptions
        .map(
          (input) => CouncilMember.parse(input, allowedAgents: _enabledAgents),
        )
        .toList();
    final chairman = CouncilMember.parse(
      chairmanRaw,
      allowedAgents: _enabledAgents,
    );

    _resolveModels(participants);
    _resolveModels([chairman]);

    final runner = CouncilRunner(agentConfigs: _agentConfigs);

    try {
      final result = await runner.run(
        prompt: prompt,
        title: title ?? buildCompareTitle(prompt),
        participants: participants,
        chairman: chairman,
      );

      if (outputJson) {
        print(const JsonEncoder.withIndent('  ').convert(result.toJson()));
        return;
      }
      _printFormattedOutput(result, includeAnswers);
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
    required bool hasChairman,
    required bool hasPrompt,
  }) {
    if (!isPersistenceMode) {
      return;
    }
    if (hasAddOptions || hasTitle || hasChairman || hasPrompt) {
      throw UsageException(
        'Cannot combine persisted run browsing with prompt or creation flags.',
        usage,
      );
    }
  }

  void _resolveModels(List<CouncilMember> members) {
    for (final member in members) {
      final config = _agentConfigs[member.agent];
      if (config == null || config.availableModels.isEmpty) {
        continue;
      }

      final modelConfig = config.availableModels
          .where((m) => m.matches(member.model))
          .firstOrNull;
      if (modelConfig == null) {
        final available = config.availableModels
            .map((model) => model.name)
            .join(', ');
        throw UsageException(
          'Unknown model "${member.model}" for ${member.agent}. Available: $available',
          usage,
        );
      }
      member.resolvedModel = modelConfig.name;
    }
  }

  void _printFormattedOutput(CouncilRun result, bool includeAnswers) {
    OutputFormatter.printCouncilStart(result.councilId, result.title);

    if (includeAnswers) {
      OutputFormatter.printStageHeader('Stage 1: Answers');
      for (final answer in result.answers) {
        _printAnswer(answer);
      }
    }

    OutputFormatter.printStageHeader('Stage 2: Reviews');
    for (final review in result.reviews) {
      _printReview(review);
    }

    OutputFormatter.printStageHeader('Stage 3: Chairman');
    _printChairman(result.chairmanResult);

    OutputFormatter.printStageHeader('Answer Map');
    for (var index = 0; index < result.answers.length; index++) {
      final participant = result.answers[index].participant;
      final label = '${participant.agent.toUpperCase()} (${participant.model})';
      print('ans_${index + 1}: $label');
    }
    print('');
  }

  void _printAnswer(CouncilParticipantResult result) {
    final participant = result.participant;
    OutputFormatter.printParticipantHeader(
      agent: participant.agent,
      model: participant.model,
      stance: 'answer',
    );
    if (result.success && result.response != null) {
      if (participant.sessionId != null) {
        OutputFormatter.printSessionStart(participant.sessionId!);
      }
      print(result.response!.content);
    } else {
      OutputFormatter.printFailure(result.failure!);
    }
    print('');
  }

  void _printReview(CouncilReviewResult result) {
    final participant = result.participant;
    OutputFormatter.printParticipantHeader(
      agent: participant.agent,
      model: participant.model,
      stance: 'review',
    );
    if (result.success && result.response != null) {
      print(result.response!.content);
    } else {
      OutputFormatter.printFailure(result.failure!);
    }
    print('');
  }

  void _printChairman(CouncilChairmanResult result) {
    OutputFormatter.printParticipantHeader(
      agent: result.chairman.agent,
      model: result.chairman.model,
      stance: 'chairman',
    );
    if (result.success && result.response != null) {
      print(result.response!.content);
    } else {
      OutputFormatter.printFailure(result.failure!);
    }
    print('');
  }

  Future<void> _listRuns(bool outputJson) async {
    final storage = CouncilStorage();
    final runs = await storage.loadAll();
    runs.sort((left, right) => right.createdAt.compareTo(left.createdAt));

    if (outputJson) {
      final output = {'runs': runs.map((run) => run.toSummaryJson()).toList()};
      print(const JsonEncoder.withIndent('  ').convert(output));
      return;
    }

    if (runs.isEmpty) {
      print('No council runs found.');
      return;
    }

    for (final run in runs.take(25)) {
      OutputFormatter.printCouncilListItem(run);
    }
  }

  Future<void> _inspectRun(String councilId, bool outputJson) async {
    final storage = CouncilStorage();
    final run = await storage.load(councilId);
    if (run == null) {
      stderr.writeln('Council run not found: $councilId');
      exit(1);
    }

    if (outputJson) {
      print(const JsonEncoder.withIndent('  ').convert(run.toJson()));
      return;
    }

    _printFormattedOutput(run, true);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'output_formatter.dart';

/// Runs multi-model consensus sessions.
class ConsensusCommand extends Command<void> {
  ConsensusCommand({required Map<String, AgentConfig> agentConfigs})
    : _agentConfigs = agentConfigs {
    argParser
      ..addMultiOption(
        'add',
        abbr: 'a',
        help: 'Add participant: agent:model:stance',
      )
      ..addOption(
        'title',
        help: 'Optional title override for the consensus run',
      )
      ..addOption(
        'proposal',
        abbr: 'p',
        help: 'Proposal/idea being evaluated (optional, provides context)',
      )
      ..addOption(
        'resume',
        abbr: 'r',
        help: 'Resume consensus session (consensus_id)',
      )
      ..addFlag(
        'json',
        abbr: 'j',
        negatable: false,
        help: 'Output full JSON response',
      )
      ..addFlag(
        'list',
        abbr: 'l',
        negatable: false,
        help: 'List saved consensus sessions',
      )
      ..addOption(
        'inspect',
        help: 'Inspect a saved consensus session by consensus_id',
      );
  }

  final Map<String, AgentConfig> _agentConfigs;

  Set<String> get _enabledAgents => _agentConfigs.entries
      .where((entry) => entry.value.enabled)
      .map((entry) => entry.key)
      .toSet();

  @override
  String get name => 'consensus';

  @override
  String get description => '''Run multi-model consensus

This command runs the specified models in parallel with stance-based prompts.''';

  @override
  String get invocation => '$name -a "agent:model:stance" -a "..." <prompt>';

  @override
  Future<void> run() async {
    final listSessions = argResults!['list'] as bool;
    final inspectId = argResults!['inspect'] as String?;
    if (listSessions && inspectId != null) {
      throw UsageException('Cannot use --list and --inspect together', usage);
    }
    _validatePersistenceMode(
      isPersistenceMode: listSessions || inspectId != null,
      hasAddOptions: (argResults!['add'] as List<String>).isNotEmpty,
      hasProposal: (argResults!['proposal'] as String?) != null,
      hasResume: (argResults!['resume'] as String?) != null,
      hasTitle: (argResults!['title'] as String?) != null,
      hasPrompt: argResults!.rest.isNotEmpty,
    );
    if (listSessions) {
      await _listSessions(argResults!['json'] as bool);
      return;
    }
    if (inspectId != null) {
      await _inspectSession(inspectId, argResults!['json'] as bool);
      return;
    }

    if (_enabledAgents.isEmpty) {
      stderr.writeln(
        'No agents are enabled. Enable at least one agent in config.',
      );
      exit(1);
    }

    final resume = argResults!['resume'] as String?;
    final addOptions = argResults!['add'] as List<String>;
    final title = argResults!['title'] as String?;
    final proposal = argResults!['proposal'] as String?;
    final outputJson = argResults!['json'] as bool;
    final rest = argResults!.rest;

    if (rest.isEmpty) {
      throw UsageException('Missing prompt', usage);
    }

    final prompt = rest.join(' ');
    final runner = ConsensusRunner(agentConfigs: _agentConfigs);

    try {
      final ConsensusResult result;

      if (resume != null) {
        if (title != null) {
          throw UsageException(
            'Cannot use --title when resuming. Title is fixed for the saved session.',
            usage,
          );
        }
        if (addOptions.isNotEmpty) {
          throw UsageException(
            'Cannot add participants when resuming. Participants are fixed.',
            usage,
          );
        }
        await _validateResumeParticipants(resume);
        result = await runner.resume(consensusId: resume, prompt: prompt);
      } else {
        if (addOptions.length < 2) {
          throw UsageException(
            'Consensus requires at least 2 participants (-a)',
            usage,
          );
        }
        final participants = addOptions
            .map(
              (input) => ConsensusParticipant.parse(
                input,
                allowedAgents: _enabledAgents,
              ),
            )
            .toList();

        // Validate and resolve model aliases
        for (final p in participants) {
          final config = _agentConfigs[p.agent];
          if (config == null || config.availableModels.isEmpty) continue;

          final modelConfig = config.availableModels
              .where((m) => m.matches(p.model))
              .firstOrNull;
          if (modelConfig == null) {
            final available = config.availableModels
                .map((m) => m.name)
                .join(', ');
            throw UsageException(
              'Unknown model "${p.model}" for ${p.agent}. Available: $available',
              usage,
            );
          }
          // Resolve alias to full model name
          p.resolvedModel = modelConfig.name;
        }

        result = await runner.run(
          prompt: prompt,
          participants: participants,
          title: title ?? buildCompareTitle(prompt),
          proposal: proposal,
        );
      }

      if (outputJson) {
        _printJsonOutput(result);
      } else {
        _printFormattedOutput(result);
      }
    } on ArgumentError catch (e) {
      stderr.writeln('Error: ${e.message}');
      exit(1);
    } on AgentExecutionException catch (e) {
      stderr.writeln(
        'Execution error [${e.failure.summary}]: ${e.failure.message}',
      );
      exit(1);
    }
  }

  void _validatePersistenceMode({
    required bool isPersistenceMode,
    required bool hasAddOptions,
    required bool hasProposal,
    required bool hasResume,
    required bool hasTitle,
    required bool hasPrompt,
  }) {
    if (!isPersistenceMode) {
      return;
    }
    if (hasAddOptions || hasProposal || hasResume || hasTitle || hasPrompt) {
      throw UsageException(
        'Cannot combine persisted run browsing with prompt or creation flags.',
        usage,
      );
    }
  }

  Future<void> _validateResumeParticipants(String consensusId) async {
    final storage = ConsensusStorage();
    final session = await storage.load(consensusId);
    if (session == null) {
      throw UsageException('Consensus session not found: $consensusId', usage);
    }
    final disabledAgents = session.participants
        .map((p) => p.agent)
        .where((agent) => !_enabledAgents.contains(agent))
        .toSet();
    if (disabledAgents.isNotEmpty) {
      throw UsageException(
        'Consensus session includes disabled agents: ${disabledAgents.join(', ')}',
        usage,
      );
    }
  }

  Future<void> _listSessions(bool outputJson) async {
    final storage = ConsensusStorage();
    final sessions = await storage.loadAll();
    sessions.sort((left, right) => right.createdAt.compareTo(left.createdAt));

    if (outputJson) {
      final output = {
        'runs': sessions
            .take(25)
            .map((session) => session.toSummaryJson())
            .toList(),
      };
      print(const JsonEncoder.withIndent('  ').convert(output));
      return;
    }

    if (sessions.isEmpty) {
      print('No consensus sessions found.');
      return;
    }

    for (final session in sessions.take(25)) {
      OutputFormatter.printConsensusListItem(session);
    }
  }

  Future<void> _inspectSession(String consensusId, bool outputJson) async {
    final storage = ConsensusStorage();
    final session = await storage.load(consensusId);
    if (session == null) {
      stderr.writeln('Consensus session not found: $consensusId');
      exit(1);
    }

    if (outputJson) {
      print(const JsonEncoder.withIndent('  ').convert(session.toJson()));
      return;
    }

    _printStoredSession(session);
  }

  void _printJsonOutput(ConsensusResult result) {
    final output = {
      'consensus_id': result.session.consensusId,
      if (result.session.title != null) 'title': result.session.title,
      'prompt': result.session.prompt,
      'results': result.results.map((r) {
        return {
          'participant': r.participant.toJson(),
          'success': r.success,
          if (r.response != null) 'response': r.response!.toJson(),
          if (r.failure != null) 'failure': r.failure!.toJson(),
        };
      }).toList(),
    };
    print(const JsonEncoder.withIndent('  ').convert(output));
  }

  void _printFormattedOutput(ConsensusResult result) {
    _printStoredSession(result.session);
    if (result.session.proposal != null) {
      print('');
    }

    for (final r in result.results) {
      final p = r.participant;
      OutputFormatter.printParticipantHeader(
        agent: p.agent,
        model: p.model,
        stance: p.stance.value,
      );

      if (r.success) {
        OutputFormatter.printSessionStart(r.response!.sessionId ?? 'unknown');
        print(r.response!.content);
      } else {
        OutputFormatter.printFailure(r.failure!);
      }
      print('');
    }

    // Summary
    print('==== SUMMARY ====');
    print('Total: ${result.results.length}');
    print('Succeeded: ${result.successful.length}');
    if (result.failed.isNotEmpty) {
      print('Failed: ${result.failed.length}');
      for (final f in result.failed) {
        print(
          '  - ${f.participant.agent}: ${OutputFormatter.formatFailure(f.failure!)}',
        );
      }
    }
  }

  void _printStoredSession(ConsensusSession session) {
    OutputFormatter.printConsensusStart(session.consensusId, session.title);
    final participants = session.participants
        .map((participant) => participant.toString())
        .join(', ');
    print('participants: $participants');
    if (session.proposal != null) {
      print('proposal: ${session.proposal}');
    }
    print('prompt: ${session.prompt}');
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'output_formatter.dart';

class ConsensusCommand extends Command<void> {
  ConsensusCommand({required Set<String> enabledAgents}) : _enabledAgents = enabledAgents {
    argParser
      ..addMultiOption('add', abbr: 'a', help: 'Add participant: agent:model:stance')
      ..addOption('proposal', abbr: 'p', help: 'Proposal/idea being evaluated (optional, provides context)')
      ..addOption('resume', abbr: 'r', help: 'Resume consensus session (consensus_id)')
      ..addFlag('json', abbr: 'j', negatable: false, help: 'Output full JSON response')
      ..addFlag('list', abbr: 'l', negatable: false, help: 'List saved consensus sessions');
  }

  final Set<String> _enabledAgents;

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
    if (listSessions) {
      await _listSessions();
      return;
    }

    if (_enabledAgents.isEmpty) {
      stderr.writeln('No agents are enabled. Enable at least one agent in config.');
      exit(1);
    }

    final resume = argResults!['resume'] as String?;
    final addOptions = argResults!['add'] as List<String>;
    final proposal = argResults!['proposal'] as String?;
    final outputJson = argResults!['json'] as bool;
    final rest = argResults!.rest;

    if (rest.isEmpty) {
      throw UsageException('Missing prompt', usage);
    }

    final prompt = rest.join(' ');
    final runner = ConsensusRunner();

    try {
      final ConsensusResult result;

      if (resume != null) {
        if (addOptions.isNotEmpty) {
          throw UsageException('Cannot add participants when resuming. Participants are fixed.', usage);
        }
        await _validateResumeParticipants(resume);
        result = await runner.resume(consensusId: resume, prompt: prompt);
      } else {
        if (addOptions.length < 2) {
          throw UsageException('Consensus requires at least 2 participants (-a)', usage);
        }
        final participants = addOptions.map((input) => ConsensusParticipant.parse(input, allowedAgents: _enabledAgents)).toList();

        // Validate and resolve model aliases
        for (final p in participants) {
          final cmdDef = CommandDefinitions.find(p.agent);
          if (cmdDef == null || cmdDef.models.isEmpty) continue;

          final modelConfig = cmdDef.findModel(p.model);
          if (modelConfig == null) {
            final available = cmdDef.models.map((m) => m.name).join(', ');
            throw UsageException('Unknown model "${p.model}" for ${p.agent}. Available: $available', usage);
          }
          // Resolve alias to full model name
          p.resolvedModel = modelConfig.name;
        }

        result = await runner.run(prompt: prompt, participants: participants, proposal: proposal);
      }

      if (outputJson) {
        _printJsonOutput(result);
      } else {
        _printFormattedOutput(result);
      }
    } on ArgumentError catch (e) {
      stderr.writeln('Error: ${e.message}');
      exit(1);
    } on ParserException catch (e) {
      stderr.writeln('Parse error: $e');
      exit(1);
    } on CLIRunnerException catch (e) {
      stderr.writeln('Execution error: $e');
      exit(1);
    }
  }

  Future<void> _validateResumeParticipants(String consensusId) async {
    final storage = ConsensusStorage();
    final session = await storage.load(consensusId);
    if (session == null) {
      throw UsageException('Consensus session not found: $consensusId', usage);
    }
    final disabledAgents = session.participants.map((p) => p.agent).where((agent) => !_enabledAgents.contains(agent)).toSet();
    if (disabledAgents.isNotEmpty) {
      throw UsageException('Consensus session includes disabled agents: ${disabledAgents.join(', ')}', usage);
    }
  }

  Future<void> _listSessions() async {
    final storage = ConsensusStorage();
    final allSessions = await storage.loadAll();

    if (allSessions.isEmpty) {
      print('No consensus sessions found.');
      return;
    }

    // Sort by date descending and take last 25
    allSessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final sessions = allSessions.take(25).toList();

    print('Consensus sessions (${sessions.length}/${allSessions.length}):\n');
    for (final session in sessions) {
      final participants = session.participants.map((p) => '${p.agent}:${p.model}:${p.stance.value}').join(', ');
      final promptPreview = session.prompt.length > 128 ? '${session.prompt.substring(0, 128)}...' : session.prompt;
      print('  ${session.consensusId}');
      print('    Created: ${session.createdAt.toLocal()}');
      print('    Participants: $participants');
      if (session.proposal != null) {
        final proposalPreview = session.proposal!.length > 128 ? '${session.proposal!.substring(0, 128)}...' : session.proposal;
        print('    Proposal: $proposalPreview');
      }
      print('    Prompt: $promptPreview');
      print('');
    }
  }

  void _printJsonOutput(ConsensusResult result) {
    final output = {
      'consensus_id': result.session.consensusId,
      'prompt': result.session.prompt,
      'results': result.results.map((r) {
        return {
          'participant': r.participant.toJson(),
          'success': r.success,
          if (r.response != null) 'response': r.response!.toJson(),
          if (r.error != null) 'error': r.error,
        };
      }).toList(),
    };
    print(const JsonEncoder.withIndent('  ').convert(output));
  }

  void _printFormattedOutput(ConsensusResult result) {
    OutputFormatter.printConsensusStart(result.session.consensusId);

    for (final r in result.results) {
      final p = r.participant;
      OutputFormatter.printParticipantHeader(agent: p.agent, model: p.model, stance: p.stance.value);

      if (r.success) {
        OutputFormatter.printSessionStart(r.response!.sessionId ?? 'unknown');
        print(r.response!.content);
      } else {
        print('ERROR: ${r.error}');
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
        print('  - ${f.participant.agent}: ${f.error}');
      }
    }
  }
}

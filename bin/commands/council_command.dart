import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'output_formatter.dart';

class CouncilCommand extends Command<void> {
  CouncilCommand({required Set<String> enabledAgents}) : _enabledAgents = enabledAgents {
    argParser
      ..addMultiOption('add', abbr: 'a', help: 'Add participant: agent:model')
      ..addOption('chairman', abbr: 'c', help: 'Chairman: agent:model (required)')
      ..addFlag('include-answers', negatable: false, help: 'Include participant answers and session IDs in output')
      ..addFlag('json', abbr: 'j', negatable: false, help: 'Output full JSON response');
  }

  final Set<String> _enabledAgents;

  @override
  String get name => 'council';

  @override
  String get description => '''Run multi-stage council

Stage 1: independent answers.
Stage 2: peer review and ranking.
Stage 3: chairman synthesis.

Chairman tip: choose the strongest reasoning model available for best synthesis.

Council runs are stateless (no resume).''';

  @override
  String get invocation => '$name -a "agent:model" -a "..." -c "agent:model" <prompt>';

  @override
  Future<void> run() async {
    if (_enabledAgents.isEmpty) {
      stderr.writeln('No agents are enabled. Enable at least one agent in config.');
      exit(1);
    }

    final addOptions = argResults!['add'] as List<String>;
    final chairmanRaw = argResults!['chairman'] as String?;
    final includeAnswers = argResults!['include-answers'] as bool;
    final outputJson = argResults!['json'] as bool;
    final rest = argResults!.rest;

    if (rest.isEmpty) {
      throw UsageException('Missing prompt', usage);
    }

    final prompt = rest.join(' ');
    final runner = CouncilRunner();

    try {
      final CouncilResult result;

      if (addOptions.length < 2) {
        throw UsageException('Council requires at least 2 participants (-a)', usage);
      }
      if (chairmanRaw == null || chairmanRaw.trim().isEmpty) {
        throw UsageException('Chairman is required (-c)', usage);
      }

      final participants = addOptions.map((input) => CouncilMember.parse(input, allowedAgents: _enabledAgents)).toList();
      final chairman = CouncilMember.parse(chairmanRaw, allowedAgents: _enabledAgents);

      _resolveModels(participants);
      _resolveModels([chairman]);

      result = await runner.run(prompt: prompt, participants: participants, chairman: chairman);

      if (outputJson) {
        _printJsonOutput(result, includeAnswers);
      } else {
        _printFormattedOutput(result, includeAnswers);
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

  void _resolveModels(List<CouncilMember> members) {
    for (final member in members) {
      final cmdDef = CommandDefinitions.find(member.agent);
      if (cmdDef == null || cmdDef.models.isEmpty) continue;

      final modelConfig = cmdDef.findModel(member.model);
      if (modelConfig == null) {
        final available = cmdDef.models.map((m) => m.name).join(', ');
        throw UsageException('Unknown model "${member.model}" for ${member.agent}. Available: $available', usage);
      }
      member.resolvedModel = modelConfig.name;
    }
  }

  void _printJsonOutput(CouncilResult result, bool includeAnswers) {
    final output = {
      'prompt': result.prompt,
      if (includeAnswers)
        'answers': result.answers.asMap().entries.map((entry) {
          final index = entry.key;
          final r = entry.value;
          return {
            'answer_id': 'ans_${index + 1}',
            if (r.response != null) 'content': r.response!.content,
            if (includeAnswers && r.response?.sessionId != null) 'session_id': r.response!.sessionId,
            if (r.error != null) 'error': r.error,
          };
        }).toList(),
      'reviews': result.reviews.map((r) {
        return {
          'reviewer': '${r.participant.agent.toUpperCase()} (${r.participant.model})',
          if (r.response != null) 'content': r.response!.content,
          if (r.error != null) 'error': r.error,
        };
      }).toList(),
      'chairman_result': {
        if (result.chairman.response != null) 'content': result.chairman.response!.content,
        if (result.chairman.error != null) 'error': result.chairman.error,
      },
      'answer_map': result.answers.asMap().entries.map((entry) {
        final index = entry.key;
        final r = entry.value;
        return {'answer_id': 'ans_${index + 1}', 'label': '${r.participant.agent.toUpperCase()} (${r.participant.model})'};
      }).toList(),
    };
    print(const JsonEncoder.withIndent('  ').convert(output));
  }

  void _printFormattedOutput(CouncilResult result, bool includeAnswers) {
    if (includeAnswers) {
      OutputFormatter.printStageHeader('Stage 1: Answers');
      for (final r in result.answers) {
        final p = r.participant;
        OutputFormatter.printParticipantHeader(agent: p.agent, model: p.model, stance: 'answer');
        if (r.success) {
          if (r.response != null) {
            if (r.response!.sessionId != null) {
              OutputFormatter.printSessionStart(r.response!.sessionId!);
            }
            print(r.response!.content);
          }
        } else {
          print('ERROR: ${r.error}');
        }
        print('');
      }
    }

    OutputFormatter.printStageHeader('Stage 2: Reviews');
    for (final r in result.reviews) {
      final p = r.participant;
      OutputFormatter.printParticipantHeader(agent: p.agent, model: p.model, stance: 'review');
      if (r.success) {
        print(r.response!.content);
      } else {
        print('ERROR: ${r.error}');
      }
      print('');
    }

    OutputFormatter.printStageHeader('Stage 3: Chairman');
    final chairman = result.chairman;
    OutputFormatter.printParticipantHeader(agent: chairman.chairman.agent, model: chairman.chairman.model, stance: 'chairman');
    if (chairman.success) {
      print(chairman.response!.content);
    } else {
      print('ERROR: ${chairman.error}');
    }
    print('');

    OutputFormatter.printStageHeader('Answer Map');
    for (var i = 0; i < result.answers.length; i++) {
      final participant = result.answers[i].participant;
      final label = '${participant.agent.toUpperCase()} (${participant.model})';
      print('ans_${i + 1}: $label');
    }
    print('');
  }
}

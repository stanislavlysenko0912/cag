import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';

import 'output_formatter.dart';

typedef MetaPrinter = void Function(ParsedResponse response);

/// Shared command runner for agent CLIs.
class AgentCommand extends Command<void> {
  AgentCommand({
    required this.agentName,
    required this.descriptionText,
    required this.defaultModel,
    required this.agent,
    required this.metaPrinter,
    required this.systemHelp,
    required this.resumeHelp,
  }) {
    argParser
      ..addOption('model', abbr: 'm', help: 'Model to use', defaultsTo: defaultModel)
      ..addOption('system', abbr: 's', help: systemHelp)
      ..addFlag('json', abbr: 'j', negatable: false, help: 'Output full JSON response')
      ..addFlag('meta', negatable: false, help: 'Include metadata (tokens, cost)')
      ..addOption('resume', abbr: 'r', help: resumeHelp);
  }

  final String agentName;
  final String descriptionText;
  final String defaultModel;
  final BaseAgent agent;
  final MetaPrinter metaPrinter;
  final String systemHelp;
  final String resumeHelp;

  @override
  String get name => agentName;

  @override
  String get description => descriptionText;

  @override
  String get invocation => '$name [options] <prompt>';

  @override
  Future<void> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw UsageException('Missing prompt', usage);
    }

    final prompt = rest.join(' ');
    final model = argResults!['model'] as String;
    final systemPrompt = argResults!['system'] as String?;
    final outputJson = argResults!['json'] as bool;
    final includeMeta = argResults!['meta'] as bool;
    final resume = argResults!['resume'] as String?;

    final resolvedModel = _resolveModel(model);

    try {
      final response = await agent.execute(prompt: prompt, model: resolvedModel, systemPrompt: systemPrompt, resume: resume);

      if (outputJson) {
        print(const JsonEncoder.withIndent('  ').convert(response.toJson()));
      } else {
        _printTextResponse(response, includeMeta: includeMeta);
      }
    } on ParserException catch (e) {
      stderr.writeln('Parse error: $e');
      exit(1);
    } on CLIRunnerException catch (e) {
      stderr.writeln('Execution error: $e');
      exit(1);
    }
  }

  String _resolveModel(String modelInput) {
    final cmdDef = CommandDefinitions.find(agentName);
    if (cmdDef == null || cmdDef.models.isEmpty) {
      return modelInput;
    }

    final modelConfig = cmdDef.findModel(modelInput);
    if (modelConfig == null) {
      final available = cmdDef.models.map((m) => m.name).join(', ');
      throw UsageException('Unknown model "$modelInput". Available: $available', usage);
    }

    return modelConfig.name;
  }

  void _printTextResponse(ParsedResponse response, {required bool includeMeta}) {
    final sessionId = response.metadata['session_id'] ?? 'unknown';
    OutputFormatter.printSessionStart('$sessionId');
    print(response.content);

    if (includeMeta) {
      OutputFormatter.printMetadataHeader();
      metaPrinter(response);
    }
  }
}

void printClaudeMeta(ParsedResponse response) {
  if (response.metadata['model_used'] != null) {
    print('model: ${response.metadata['model_used']}');
  }
  final usage = response.metadata['usage'] as Map<String, dynamic>?;
  if (usage != null) {
    print('input_tokens: ${usage['input_tokens']}');
    print('output_tokens: ${usage['output_tokens']}');
    if (usage['cache_read_input_tokens'] != null) {
      print('cache_read: ${usage['cache_read_input_tokens']}');
    }
  }
  if (response.metadata['total_cost_usd'] != null) {
    print('cost_usd: ${response.metadata['total_cost_usd']}');
  }
  if (response.metadata['duration_ms'] != null) {
    print('duration_ms: ${response.metadata['duration_ms']}');
  }
}

void printGeminiMeta(ParsedResponse response) {
  if (response.metadata['model_used'] != null) {
    print('model: ${response.metadata['model_used']}');
  }
  if (response.metadata['token_usage'] != null) {
    final tokens = response.metadata['token_usage'] as Map<String, dynamic>;
    print('tokens: ${tokens['total'] ?? tokens}');
  }
  if (response.metadata['latency_ms'] != null) {
    print('latency_ms: ${response.metadata['latency_ms']}');
  }
}

void printCodexMeta(ParsedResponse response) {
  final usage = response.metadata['usage'] as Map<String, dynamic>?;
  if (usage != null) {
    print('input_tokens: ${usage['input_tokens']}');
    print('output_tokens: ${usage['output_tokens']}');
    if (usage['cached_input_tokens'] != null) {
      print('cached_tokens: ${usage['cached_input_tokens']}');
    }
  }
}

void printCursorMeta(ParsedResponse response) {
  if (response.metadata['request_id'] != null) {
    print('request_id: ${response.metadata['request_id']}');
  }
  if (response.metadata['duration_ms'] != null) {
    print('duration_ms: ${response.metadata['duration_ms']}');
  }
  if (response.metadata['duration_api_ms'] != null) {
    print('duration_api_ms: ${response.metadata['duration_api_ms']}');
  }
}

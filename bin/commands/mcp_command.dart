import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';
import 'package:mcp_dart/mcp_dart.dart';

const String _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'unknown');
const _knownAgents = ['claude', 'gemini', 'codex'];

ToolInputSchema _buildAgentInputSchema(List<String> enabledAgents) {
  return JsonSchema.object(
    properties: {
      'agent': JsonSchema.string(description: 'Agent name.', enumValues: enabledAgents),
      'prompt': JsonSchema.string(description: 'User prompt to send to the agent. Provide full context, constraints, and desired output.'),
      'model': JsonSchema.string(description: 'Model name or alias supported by the agent.'),
      'system': JsonSchema.string(description: 'Optional system prompt to prepend.'),
      'resume': JsonSchema.string(description: 'Optional session/thread ID to resume.'),
    },
    required: ['agent', 'prompt'],
    additionalProperties: false,
  );
}

final ToolOutputSchema _agentOutputSchema = JsonSchema.object(
  properties: {
    'content': JsonSchema.string(description: 'Primary text response from the agent.'),
    'metadata': JsonSchema.object(description: 'Session metadata (currently only session_id).'),
  },
  required: ['content', 'metadata'],
  additionalProperties: false,
);

JsonObject _buildConsensusParticipantSchema(List<String> enabledAgents) {
  return JsonSchema.object(
    properties: {
      'agent': JsonSchema.string(description: 'Agent name.', enumValues: enabledAgents),
      'model': JsonSchema.string(description: 'Model name or alias supported by the agent.'),
      'stance': JsonSchema.string(description: 'Stance to take: for, against, or neutral.', enumValues: ['for', 'against', 'neutral']),
      'session_id': JsonSchema.string(description: 'Optional session ID for resume.'),
      'stance_prompt': JsonSchema.string(description: 'Optional custom stance prompt override.'),
    },
    required: ['agent', 'model', 'stance'],
    additionalProperties: false,
  );
}

ToolInputSchema _buildConsensusInputSchema(List<String> enabledAgents) {
  final participantSchema = _buildConsensusParticipantSchema(enabledAgents);
  return JsonSchema.object(
    properties: {
      'prompt': JsonSchema.string(
        description: 'Prompt/question for the consensus round. Provide full context, constraints, and desired output.',
      ),
      'proposal': JsonSchema.string(description: 'Optional proposal to provide context.'),
      'resume': JsonSchema.string(description: 'Consensus session ID to resume.'),
      'participants': JsonSchema.array(description: 'Participants to include in the consensus run.', items: participantSchema, minItems: 2),
    },
    required: ['prompt'],
    additionalProperties: false,
  );
}

final ToolOutputSchema _consensusOutputSchema = JsonSchema.object(
  properties: {
    'consensus_id': JsonSchema.string(description: 'Consensus session ID.'),
    'prompt': JsonSchema.string(description: 'Original prompt for the session.'),
    'results': JsonSchema.array(
      description: 'Per-participant results.',
      items: JsonSchema.object(
        properties: {
          'participant': JsonSchema.object(description: 'Participant details (agent, model, stance).'),
          'success': JsonSchema.boolean(description: 'Whether the participant succeeded.'),
          'response': JsonSchema.object(description: 'Parsed response from the participant (if successful).'),
          'error': JsonSchema.string(description: 'Error message (if failed).'),
        },
        additionalProperties: true,
      ),
    ),
  },
  required: ['consensus_id', 'prompt', 'results'],
  additionalProperties: false,
);

JsonObject _buildCouncilMemberSchema(List<String> enabledAgents) {
  return JsonSchema.object(
    properties: {
      'agent': JsonSchema.string(description: 'Agent name.', enumValues: enabledAgents),
      'model': JsonSchema.string(description: 'Model name or alias supported by the agent.'),
    },
    required: ['agent', 'model'],
    additionalProperties: false,
  );
}

ToolInputSchema _buildCouncilInputSchema(List<String> enabledAgents) {
  final memberSchema = _buildCouncilMemberSchema(enabledAgents);
  return JsonSchema.object(
    properties: {
      'prompt': JsonSchema.string(description: 'Prompt/question for the council. Provide full context, constraints, and desired output.'),
      'participants': JsonSchema.array(description: 'Participants to include in the council run.', items: memberSchema, minItems: 2),
      'chairman': memberSchema,
      'include_answers': JsonSchema.boolean(description: 'Include participant answers and session IDs in output.'),
    },
    required: ['prompt'],
    additionalProperties: false,
  );
}

final ToolOutputSchema _councilOutputSchema = JsonSchema.object(
  properties: {
    'prompt': JsonSchema.string(description: 'Original prompt for the session.'),
    'answers': JsonSchema.array(
      description: 'Stage 1 answers.',
      items: JsonSchema.object(
        properties: {
          'answer_id': JsonSchema.string(description: 'Answer identifier.'),
          'content': JsonSchema.string(description: 'Answer content.'),
          'session_id': JsonSchema.string(description: 'Session ID for answer (optional).'),
          'error': JsonSchema.string(description: 'Error message (if failed).'),
        },
        additionalProperties: false,
      ),
    ),
    'reviews': JsonSchema.array(
      description: 'Stage 2 reviews.',
      items: JsonSchema.object(
        properties: {
          'reviewer': JsonSchema.string(description: 'Reviewer label.'),
          'content': JsonSchema.string(description: 'Review content.'),
          'error': JsonSchema.string(description: 'Error message (if failed).'),
        },
        additionalProperties: false,
      ),
    ),
    'chairman_result': JsonSchema.object(
      description: 'Stage 3 chairman result.',
      properties: {
        'content': JsonSchema.string(description: 'Final synthesized answer.'),
        'error': JsonSchema.string(description: 'Error message (if failed).'),
      },
      additionalProperties: false,
    ),
    'answer_map': JsonSchema.array(description: 'Mapping of answer_id to participants.'),
  },
  required: ['prompt', 'reviews', 'chairman_result', 'answer_map'],
  additionalProperties: false,
);

final ToolOutputSchema _modelsOutputSchema = JsonSchema.object(
  properties: {
    'agents': JsonSchema.array(
      description: 'Agents and their supported models.',
      items: JsonSchema.object(
        properties: {
          'agent': JsonSchema.string(description: 'Agent name.'),
          'default_model': JsonSchema.string(description: 'Default model name.'),
          'models': JsonSchema.array(
            description: 'Supported models.',
            items: JsonSchema.object(
              properties: {
                'name': JsonSchema.string(description: 'Model name.'),
                'aliases': JsonSchema.array(description: 'Model aliases.', items: JsonSchema.string()),
                'description': JsonSchema.string(description: 'Model description.'),
                'is_default': JsonSchema.boolean(description: 'Whether model is default.'),
              },
              additionalProperties: false,
            ),
          ),
        },
        additionalProperties: false,
      ),
    ),
  },
  required: ['agents'],
  additionalProperties: false,
);

/// Runs the MCP server for cag over stdio.
class McpCommand extends Command<void> {
  McpCommand() {
    argParser
      ..addOption('transport', allowed: ['stdio', 'http'], defaultsTo: 'stdio', help: 'Transport type (stdio or http).')
      ..addOption('host', defaultsTo: '127.0.0.1', help: 'Host to bind for HTTP transport.')
      ..addOption('port', defaultsTo: '7331', help: 'Port to bind for HTTP transport.')
      ..addOption('http-path', defaultsTo: '/mcp', help: 'Path for HTTP MCP requests.');
  }

  @override
  String get name => 'mcp';

  @override
  String get description => 'Run MCP server over stdio or HTTP';

  @override
  Future<void> run() async {
    final transport = (argResults?['transport'] as String?)?.toLowerCase();
    if (transport == null) {
      throw UsageException('Missing transport', usage);
    }

    switch (transport) {
      case 'stdio':
        await _runStdio();
        return;
      case 'http':
        await _runHttp();
        return;
      default:
        throw UsageException('Unknown transport "$transport"', usage);
    }
  }

  Future<void> _runStdio() async {
    final server = await _buildServer();
    final transport = StdioServerTransport(stdin: stdin, stdout: stdout);

    await runZoned(
      () => server.connect(transport),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {
          stderr.writeln(line);
        },
      ),
    );
  }

  Future<void> _runHttp() async {
    final host = argResults?['host'] as String? ?? '127.0.0.1';
    final portRaw = argResults?['port'] as String? ?? '7331';
    final httpPathRaw = argResults?['http-path'] as String? ?? '/mcp';

    final port = int.tryParse(portRaw);
    if (port == null || port <= 0 || port > 65535) {
      throw UsageException('Invalid --port value "$portRaw"', usage);
    }

    final httpPath = _normalizePath(httpPathRaw);

    final mcpServer = await _buildServer();
    final transport = StreamableHTTPServerTransport(options: StreamableHTTPServerTransportOptions(sessionIdGenerator: generateUUID));
    mcpServer.onError = (error) {
      stderr.writeln('MCP server error: $error');
    };

    await mcpServer.connect(transport);

    final server = await HttpServer.bind(host, port);
    stderr.writeln('MCP HTTP server listening on http://$host:${server.port}$httpPath');

    await for (final request in server) {
      if (request.uri.path == httpPath) {
        await transport.handleRequest(request);
        continue;
      }

      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Not Found');
      await request.response.close();
    }
  }
}

Future<McpServer> _buildServer() async {
  final configService = ConfigService();
  final config = await configService.loadOrCreate();

  final claudeConfig = configService.applyOverrides(ClaudeAgent.defaultConfig, configService.overridesFor(config, 'claude'));
  final geminiConfig = configService.applyOverrides(GeminiAgent.defaultConfig, configService.overridesFor(config, 'gemini'));
  final codexConfig = configService.applyOverrides(CodexAgent.defaultConfig, configService.overridesFor(config, 'codex'));

  final enabledAgents = <String>[if (claudeConfig.enabled) 'claude', if (geminiConfig.enabled) 'gemini', if (codexConfig.enabled) 'codex'];

  final agentDefaults = <String, String>{
    if (claudeConfig.enabled) 'claude': claudeConfig.defaultModel ?? (AgentModelRegistry.defaultModelName('claude') ?? 'sonnet'),
    if (geminiConfig.enabled)
      'gemini': geminiConfig.defaultModel ?? (AgentModelRegistry.defaultModelName('gemini') ?? 'gemini-3-flash-preview'),
    if (codexConfig.enabled) 'codex': codexConfig.defaultModel ?? (AgentModelRegistry.defaultModelName('codex') ?? 'gpt-5.2'),
  };

  final agents = <String, BaseAgent>{
    if (claudeConfig.enabled) 'claude': ClaudeAgent(config: claudeConfig),
    if (geminiConfig.enabled) 'gemini': GeminiAgent(config: geminiConfig),
    if (codexConfig.enabled) 'codex': CodexAgent(config: codexConfig),
  };

  final consensusRunner = ConsensusRunner();
  final councilRunner = CouncilRunner();

  final server = McpServer(
    Implementation(name: 'cag', version: _appVersion),
    options: const ServerOptions(instructions: 'cag MCP server exposing agent, consensus, and council tools.'),
  );

  server.registerTool(
    'cag_agent',
    description: 'Run a single agent.',
    inputSchema: _buildAgentInputSchema(enabledAgents),
    outputSchema: _agentOutputSchema,
    callback: (args, extra) async {
      final errors = <String>[];
      final agentName = _readStringArg(args, 'agent', errors, required: true)?.toLowerCase();
      final prompt = _readStringArg(args, 'prompt', errors, required: true);
      final modelInput = _readStringArg(args, 'model', errors);
      final systemPrompt = _readStringArg(args, 'system', errors);
      final resume = _readStringArg(args, 'resume', errors);

      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      if (agentName == null) {
        return _errorResult(_agentRequiredMessage(enabledAgents));
      }

      if (!_knownAgents.contains(agentName)) {
        return _errorResult(_agentUnknownMessage(agentName, enabledAgents));
      }

      if (!enabledAgents.contains(agentName)) {
        return _errorResult(_agentDisabledMessage(agentName, enabledAgents));
      }

      final agent = agents[agentName];
      if (agent == null) {
        return _errorResult(_agentUnknownMessage(agentName, enabledAgents));
      }

      final model = modelInput ?? agentDefaults[agentName];
      if (model == null || model.isEmpty) {
        return _errorResult('Model is required for agent "$agentName".');
      }

      final resolvedModel = _resolveModel(agentName, model, errors);
      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      try {
        final response = await agent.execute(prompt: prompt!, model: resolvedModel, systemPrompt: systemPrompt, resume: resume);

        return CallToolResult.fromStructuredContent(_minimalResponse(response));
      } on ParserException catch (e) {
        return _errorResult('Parse error: $e');
      } on CLIRunnerException catch (e) {
        return _errorResult('Execution error: $e');
      }
    },
  );

  server.registerTool(
    'cag_consensus',
    description: 'Run consensus across multiple agents.',
    inputSchema: _buildConsensusInputSchema(enabledAgents),
    outputSchema: _consensusOutputSchema,
    callback: (args, extra) async {
      final errors = <String>[];
      final prompt = _readStringArg(args, 'prompt', errors, required: true);
      final proposal = _readStringArg(args, 'proposal', errors);
      final resume = _readStringArg(args, 'resume', errors);
      final participantsRaw = args['participants'];

      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      if (resume != null && participantsRaw != null) {
        return _errorResult('participants cannot be provided when resume is set.');
      }

      final participants = <ConsensusParticipant>[];
      if (resume == null) {
        if (participantsRaw == null) {
          return _errorResult('participants is required when resume is not set.');
        }
        if (participantsRaw is! List) {
          return _errorResult('participants must be an array of objects.');
        }
        if (participantsRaw.length < 2) {
          return _errorResult('participants must include at least 2 entries.');
        }

        for (final entry in participantsRaw) {
          if (entry is! Map) {
            return _errorResult('participants entries must be objects.');
          }

          final agentName = _readMapString(entry, 'agent', errors, required: true)?.toLowerCase();
          final model = _readMapString(entry, 'model', errors, required: true);
          final stanceValue = _readMapString(entry, 'stance', errors, required: true);
          final sessionId = _readMapString(entry, 'session_id', errors);
          final stancePrompt = _readMapString(entry, 'stance_prompt', errors);

          if (errors.isNotEmpty) {
            return _errorResult(errors.join(' '));
          }

          if (!_knownAgents.contains(agentName)) {
            return _errorResult(_agentUnknownMessage(agentName!, enabledAgents));
          }

          if (!enabledAgents.contains(agentName)) {
            return _errorResult(_agentDisabledMessage(agentName!, enabledAgents));
          }

          try {
            final participant = ConsensusParticipant(
              agent: agentName!,
              model: model!,
              stance: ConsensusStance.fromString(stanceValue!),
              sessionId: sessionId,
              stancePrompt: stancePrompt,
            );
            participant.resolvedModel = _resolveModel(agentName, model, errors);
            if (errors.isNotEmpty) {
              return _errorResult(errors.join(' '));
            }
            participants.add(participant);
          } on ArgumentError catch (e) {
            return _errorResult(e.message ?? e.toString());
          }
        }
      }

      try {
        final ConsensusResult result;
        if (resume != null) {
          final resumeError = await _validateConsensusResume(resume, enabledAgents);
          if (resumeError != null) {
            return _errorResult(resumeError);
          }
          result = await consensusRunner.resume(consensusId: resume, prompt: prompt!);
        } else {
          result = await consensusRunner.run(prompt: prompt!, participants: participants, proposal: proposal);
        }

        final output = {
          'consensus_id': result.session.consensusId,
          'prompt': result.session.prompt,
          'results': result.results.map((r) {
            return {
              'participant': r.participant.toJson(),
              'success': r.success,
              if (r.response != null) 'response': _minimalResponse(r.response!),
              if (r.error != null) 'error': r.error,
            };
          }).toList(),
        };

        return CallToolResult.fromStructuredContent(output);
      } on ArgumentError catch (e) {
        return _errorResult(e.message ?? e.toString());
      } on ParserException catch (e) {
        return _errorResult('Parse error: $e');
      } on CLIRunnerException catch (e) {
        return _errorResult('Execution error: $e');
      }
    },
  );

  server.registerTool(
    'cag_council',
    description: 'Run multi-stage council (answers, reviews, chairman).',
    inputSchema: _buildCouncilInputSchema(enabledAgents),
    outputSchema: _councilOutputSchema,
    callback: (args, extra) async {
      final errors = <String>[];
      final prompt = _readStringArg(args, 'prompt', errors, required: true);
      final includeAnswers = args['include_answers'] == true;
      final participantsRaw = args['participants'];
      final chairmanRaw = args['chairman'];

      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      if (participantsRaw == null) {
        return _errorResult('participants is required.');
      }
      if (participantsRaw is! List) {
        return _errorResult('participants must be an array of objects.');
      }
      if (participantsRaw.length < 2) {
        return _errorResult('participants must include at least 2 entries.');
      }
      if (chairmanRaw == null || chairmanRaw is! Map) {
        return _errorResult('chairman is required and must be an object.');
      }

      final participants = <CouncilMember>[];
      for (final entry in participantsRaw) {
        if (entry is! Map) {
          return _errorResult('participants entries must be objects.');
        }

        final agentName = _readMapString(entry, 'agent', errors, required: true)?.toLowerCase();
        final model = _readMapString(entry, 'model', errors, required: true);

        if (errors.isNotEmpty) {
          return _errorResult(errors.join(' '));
        }

        if (!_knownAgents.contains(agentName)) {
          return _errorResult(_agentUnknownMessage(agentName!, enabledAgents));
        }

        if (!enabledAgents.contains(agentName)) {
          return _errorResult(_agentDisabledMessage(agentName!, enabledAgents));
        }

        final member = CouncilMember(agent: agentName!, model: model!);
        member.resolvedModel = _resolveModel(agentName, model, errors);
        if (errors.isNotEmpty) {
          return _errorResult(errors.join(' '));
        }
        participants.add(member);
      }

      final chairmanAgent = _readMapString(chairmanRaw, 'agent', errors, required: true)?.toLowerCase();
      final chairmanModel = _readMapString(chairmanRaw, 'model', errors, required: true);

      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      if (!_knownAgents.contains(chairmanAgent)) {
        return _errorResult(_agentUnknownMessage(chairmanAgent!, enabledAgents));
      }

      if (!enabledAgents.contains(chairmanAgent)) {
        return _errorResult(_agentDisabledMessage(chairmanAgent!, enabledAgents));
      }

      final chairman = CouncilMember(agent: chairmanAgent!, model: chairmanModel!);
      chairman.resolvedModel = _resolveModel(chairmanAgent, chairmanModel, errors);
      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      try {
        final result = await councilRunner.run(prompt: prompt!, participants: participants, chairman: chairman);

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

        return CallToolResult.fromStructuredContent(output);
      } on ArgumentError catch (e) {
        return _errorResult(e.message ?? e.toString());
      } on ParserException catch (e) {
        return _errorResult('Parse error: $e');
      } on CLIRunnerException catch (e) {
        return _errorResult('Execution error: $e');
      }
    },
  );

  server.registerTool(
    'cag_models',
    description: 'List supported models for each agent.',
    outputSchema: _modelsOutputSchema,
    callback: (args, extra) async {
      final agentsInfo = CommandDefinitions.all.where((c) => c.models.isNotEmpty).where((c) => enabledAgents.contains(c.name)).map((cmd) {
        return {
          'agent': cmd.name,
          'default_model': cmd.defaultModel?.name,
          'models': cmd.models.map((model) {
            return {'name': model.name, 'aliases': model.aliases, 'description': model.description, 'is_default': model.isDefault};
          }).toList(),
        };
      }).toList();

      return CallToolResult.fromStructuredContent({'agents': agentsInfo});
    },
  );

  return server;
}

CallToolResult _errorResult(String message) {
  return CallToolResult(content: [TextContent(text: message)], isError: true);
}

Map<String, dynamic> _minimalResponse(ParsedResponse response) {
  return {
    'content': response.content,
    'metadata': {if (response.sessionId != null) 'session_id': response.sessionId},
  };
}

String _normalizePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '/';
  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}

String? _readStringArg(Map<String, dynamic> args, String key, List<String> errors, {bool required = false}) {
  final value = args[key];
  if (value == null) {
    if (required) {
      errors.add('Missing required field "$key".');
    }
    return null;
  }
  if (value is! String) {
    errors.add('Field "$key" must be a string.');
    return null;
  }
  if (required && value.trim().isEmpty) {
    errors.add('Field "$key" cannot be empty.');
  }
  return value;
}

String? _readMapString(Map entry, String key, List<String> errors, {bool required = false}) {
  final value = entry[key];
  if (value == null) {
    if (required) {
      errors.add('Missing required field "$key" in participants entry.');
    }
    return null;
  }
  if (value is! String) {
    errors.add('Field "$key" in participants entry must be a string.');
    return null;
  }
  if (required && value.trim().isEmpty) {
    errors.add('Field "$key" in participants entry cannot be empty.');
  }
  return value;
}

String _agentRequiredMessage(List<String> enabledAgents) {
  if (enabledAgents.isEmpty) {
    return 'No agents are enabled.';
  }
  return 'Agent is required. Use: ${enabledAgents.join(', ')}.';
}

String _agentUnknownMessage(String agentName, List<String> enabledAgents) {
  if (enabledAgents.isEmpty) {
    return 'Unknown agent "$agentName". No agents are enabled.';
  }
  return 'Unknown agent "$agentName". Use: ${enabledAgents.join(', ')}.';
}

String _agentDisabledMessage(String agentName, List<String> enabledAgents) {
  if (enabledAgents.isEmpty) {
    return 'Agent "$agentName" is disabled. No agents are enabled.';
  }
  return 'Agent "$agentName" is disabled. Enabled: ${enabledAgents.join(', ')}.';
}

Future<String?> _validateConsensusResume(String consensusId, List<String> enabledAgents) async {
  final storage = ConsensusStorage();
  final session = await storage.load(consensusId);
  if (session == null) {
    return 'Consensus session not found: $consensusId';
  }

  final unknownAgents = session.participants.map((p) => p.agent).where((agent) => !_knownAgents.contains(agent)).toSet();
  if (unknownAgents.isNotEmpty) {
    return 'Consensus session includes unknown agents: ${unknownAgents.join(', ')}';
  }

  final disabledAgents = session.participants.map((p) => p.agent).where((agent) => !enabledAgents.contains(agent)).toSet();
  if (disabledAgents.isNotEmpty) {
    return 'Consensus session includes disabled agents: ${disabledAgents.join(', ')}';
  }

  return null;
}

String _resolveModel(String agentName, String modelInput, List<String> errors) {
  final cmdDef = CommandDefinitions.find(agentName);
  if (cmdDef == null || cmdDef.models.isEmpty) {
    return modelInput;
  }

  final modelConfig = cmdDef.findModel(modelInput);
  if (modelConfig == null) {
    final available = cmdDef.models.map((m) => m.name).join(', ');
    errors.add('Unknown model "$modelInput" for $agentName. Available: $available');
    return modelInput;
  }

  return modelConfig.name;
}

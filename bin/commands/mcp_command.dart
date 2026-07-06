import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:cag/cag.dart';
import 'package:cag/src/doctor/doctor.dart';
import 'package:mcp_dart/mcp_dart.dart';

import 'mcp_agent_tasks.dart';
import 'output_formatter.dart';

const String _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'unknown',
);
final _knownAgents = AgentCatalog.names;
const _agentToolDescription =
    'Ask one enabled CAG agent to inspect, reason about, or answer a task. '
    'Use CAG only when the user asks for CAG or a specific CAG agent/model, '
    'or when external independent judgment or cross-agent comparison would materially improve the answer. '
    'Prefer your own native tools, subagents, or direct model tools for ordinary delegation and simple same-family model calls. '
    'The agent runs in the same working directory and can inspect files directly, '
    'so reference paths and goals instead of pasting large file contents. '
    'Call cag_models first when you are unsure which agent IDs or model aliases are available, '
    'or when model choice matters. '
    'Only pass resume with a session_id returned by cag_agent for the same agent; '
    'compare_id, consensus_id, and council_id are CAG wrapper IDs, not agent sessions.';
const _modelsToolDescription =
    'List enabled CAG agent IDs, default models, supported model names, aliases, '
    'and short model guidance. Call this before cag_agent when you need the exact '
    'agent ID/model alias, want to choose an appropriate model, or receive a model error.';
// ignore: unused_element
const _agentsStatusToolDescription =
    'Report CAG agent runtime status without running model calls. '
    'Use this to see which known agents are enabled, whether their executable is found, '
    'which default model CAG will use, and why an agent is not currently runnable.';

ToolInputSchema _buildAgentInputSchema(List<String> enabledAgents) {
  return JsonSchema.object(
    properties: {
      'agent': JsonSchema.string(
        description:
            'Enabled CAG agent ID to run. Use cag_models if you are unsure which IDs are available.',
        enumValues: enabledAgents,
      ),
      'prompt': JsonSchema.string(
        description:
            'Task or question for the agent. Provide context, constraints, relevant paths, and desired output; the agent can inspect the shared working directory directly.',
      ),
      'model': JsonSchema.string(
        description:
            'Optional model name or alias supported by the selected agent. Omit to use the configured default; call cag_models first when choosing a model or resolving aliases.',
      ),
      'system': JsonSchema.string(
        description:
            'Optional system prompt to prepend when you need agent-specific behavior beyond the user prompt.',
      ),
      'resume': JsonSchema.string(
        description:
            'Optional session_id returned by cag_agent for the same agent. Do not pass compare_id, consensus_id, or council_id here.',
      ),
      'cwd': JsonSchema.string(
        description:
            'Optional working directory for the agent process. Omit to use the MCP server working directory.',
      ),
      'name': JsonSchema.string(
        description:
            'Optional human-readable label for task-capable clients and cag://tasks resources.',
      ),
      'mode': JsonSchema.string(
        description:
            'sync waits for the agent result. background returns a task handle immediately; check progress and fetch the result with cag_task. task_id is not a session_id.',
        enumValues: ['sync', 'background'],
      ),
      'verbose': JsonSchema.boolean(
        description:
            'Optional expanded output. Avoid unless raw metadata or a full structured payload is specifically needed.',
      ),
    },
    required: ['agent', 'prompt'],
    additionalProperties: false,
  );
}

final ToolOutputSchema _agentOutputSchema = JsonSchema.object(
  properties: {
    'result': JsonSchema.string(description: 'CLI-like output string.'),
    'session_id': JsonSchema.string(description: 'Session ID, if available.'),
    'task_id': JsonSchema.string(
      description: 'Background task ID, only when mode=background.',
    ),
    'status': JsonSchema.string(
      description: 'Background task status, only when mode=background.',
    ),
    'agent': JsonSchema.string(
      description: 'Background task agent, only when mode=background.',
    ),
    'model': JsonSchema.string(
      description: 'Background task model, only when mode=background.',
    ),
    'cwd': JsonSchema.string(
      description: 'Background task working directory, only when set.',
    ),
    'name': JsonSchema.string(
      description: 'Background task label, only when set.',
    ),
    'started_at': JsonSchema.string(
      description:
          'Background task start timestamp, only when mode=background.',
    ),
    'message': JsonSchema.string(
      description:
          'Latest background task status message, only when mode=background.',
    ),
    'verbose_data': JsonSchema.object(
      description:
          'Expanded structured payload returned only when verbose=true.',
    ),
  },
  required: ['result'],
  additionalProperties: false,
);

JsonObject _buildConsensusParticipantSchema(List<String> enabledAgents) {
  return JsonSchema.object(
    properties: {
      'agent': JsonSchema.string(
        description: 'Agent name.',
        enumValues: enabledAgents,
      ),
      'model': JsonSchema.string(
        description: 'Model name or alias supported by the agent.',
      ),
      'stance': JsonSchema.string(
        description: 'Stance to take: for, against, or neutral.',
        enumValues: ['for', 'against', 'neutral'],
      ),
      'session_id': JsonSchema.string(
        description: 'Optional session ID for resume.',
      ),
      'stance_prompt': JsonSchema.string(
        description: 'Optional custom stance prompt override.',
      ),
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
        description:
            'Prompt/question for the consensus round. Provide full context, constraints, and desired output.',
      ),
      'proposal': JsonSchema.string(
        description: 'Optional proposal to provide context.',
      ),
      'resume': JsonSchema.string(
        description: 'Consensus session ID to resume.',
      ),
      'participants': JsonSchema.array(
        description: 'Participants to include in the consensus run.',
        items: participantSchema,
        minItems: 2,
      ),
      'verbose': JsonSchema.boolean(
        description:
            'Optional expanded output. Avoid unless per-participant payloads or metadata are specifically needed.',
      ),
    },
    required: ['prompt'],
    additionalProperties: false,
  );
}

final ToolOutputSchema _consensusOutputSchema = JsonSchema.object(
  properties: {
    'result': JsonSchema.string(description: 'CLI-like output string.'),
    'consensus_id': JsonSchema.string(description: 'Consensus session ID.'),
    'verbose_data': JsonSchema.object(
      description:
          'Expanded structured payload returned only when verbose=true.',
    ),
  },
  required: ['result', 'consensus_id'],
  additionalProperties: false,
);

JsonObject _buildCouncilMemberSchema(List<String> enabledAgents) {
  return JsonSchema.object(
    properties: {
      'agent': JsonSchema.string(
        description: 'Agent name.',
        enumValues: enabledAgents,
      ),
      'model': JsonSchema.string(
        description: 'Model name or alias supported by the agent.',
      ),
    },
    required: ['agent', 'model'],
    additionalProperties: false,
  );
}

ToolInputSchema _buildCouncilInputSchema(List<String> enabledAgents) {
  final memberSchema = _buildCouncilMemberSchema(enabledAgents);
  return JsonSchema.object(
    properties: {
      'prompt': JsonSchema.string(
        description:
            'Prompt/question for the council. Provide full context, constraints, and desired output.',
      ),
      'participants': JsonSchema.array(
        description: 'Participants to include in the council run.',
        items: memberSchema,
        minItems: 2,
      ),
      'chairman': memberSchema,
      'include_answers': JsonSchema.boolean(
        description: 'Include participant answers and session IDs in output.',
      ),
      'verbose': JsonSchema.boolean(
        description:
            'Optional expanded output. Avoid unless stage-level structured data is specifically needed.',
      ),
    },
    required: ['prompt'],
    additionalProperties: false,
  );
}

ToolInputSchema _buildCompareInputSchema(List<String> enabledAgents) {
  final memberSchema = _buildCouncilMemberSchema(enabledAgents);
  return JsonSchema.object(
    properties: {
      'prompt': JsonSchema.string(
        description:
            'Prompt/question for the compare run. Provide full context, constraints, and desired output.',
      ),
      'title': JsonSchema.string(
        description: 'Optional title override for the compare run.',
      ),
      'participants': JsonSchema.array(
        description: 'Participants to include in the compare run.',
        items: memberSchema,
        minItems: 2,
      ),
      'verbose': JsonSchema.boolean(
        description:
            'Optional expanded output. Avoid unless per-participant payloads or metadata are specifically needed.',
      ),
    },
    required: ['prompt', 'participants'],
    additionalProperties: false,
  );
}

final ToolOutputSchema _councilOutputSchema = JsonSchema.object(
  properties: {
    'result': JsonSchema.string(description: 'CLI-like output string.'),
    'verbose_data': JsonSchema.object(
      description:
          'Expanded structured payload returned only when verbose=true.',
    ),
  },
  required: ['result'],
  additionalProperties: false,
);

final ToolOutputSchema _compareOutputSchema = JsonSchema.object(
  properties: {
    'result': JsonSchema.string(description: 'CLI-like output string.'),
    'compare_id': JsonSchema.string(description: 'Compare run ID.'),
    'verbose_data': JsonSchema.object(
      description:
          'Expanded structured payload returned only when verbose=true.',
    ),
  },
  required: ['result', 'compare_id'],
  additionalProperties: false,
);

final ToolOutputSchema _modelsOutputSchema = JsonSchema.object(
  properties: {
    'result': JsonSchema.string(description: 'Compact model summary.'),
    'verbose_data': JsonSchema.object(
      description:
          'Expanded structured payload returned only when verbose=true.',
    ),
  },
  required: ['result'],
  additionalProperties: false,
);

final ToolInputSchema _taskInputSchema = JsonSchema.object(
  properties: {
    'action': JsonSchema.string(
      description: 'Task action.',
      enumValues: ['list', 'get', 'result', 'wait', 'wait_any', 'cancel'],
    ),
    'task_id': JsonSchema.string(
      description: 'Task ID for get, result, wait, or cancel.',
    ),
    'task_ids': JsonSchema.array(
      description: 'Task IDs for wait_any.',
      items: JsonSchema.string(),
    ),
    'timeout_ms': JsonSchema.integer(
      description:
          'Timeout for wait and wait_any. Defaults to 30000 and is clamped to 1000..120000.',
    ),
    'include_log': JsonSchema.boolean(
      description:
          'Include stdout/stderr logs for get, result, wait, and wait_any when one task is returned. Defaults to false.',
    ),
  },
  required: ['action'],
  additionalProperties: false,
);

final ToolOutputSchema _taskOutputSchema = JsonSchema.object(
  properties: {
    'result': JsonSchema.string(description: 'Compact task action summary.'),
    'task': JsonSchema.object(description: 'Single task payload.'),
    'tasks': JsonSchema.array(
      description: 'Task list payload.',
      items: JsonSchema.object(),
    ),
    'log': JsonSchema.object(description: 'Opt-in stdout/stderr log payload.'),
    'timed_out': JsonSchema.boolean(description: 'Whether a wait timed out.'),
  },
  required: ['result'],
  additionalProperties: false,
);

// ignore: unused_element
final ToolOutputSchema _agentsStatusOutputSchema = JsonSchema.object(
  properties: {
    'result': JsonSchema.string(description: 'Compact agent status summary.'),
    'config': JsonSchema.object(description: 'Config file status.'),
    'agents': JsonSchema.array(
      description: 'Per-agent runtime status rows.',
      items: JsonSchema.object(),
    ),
    'summary': JsonSchema.object(description: 'Runtime status counts.'),
  },
  required: ['result', 'config', 'agents', 'summary'],
  additionalProperties: false,
);

// ignore: unused_element
final ToolInputSchema _emptyInputSchema = JsonSchema.object(
  additionalProperties: false,
);

final ToolInputSchema _modelsInputSchema = JsonSchema.object(
  properties: {
    'verbose': JsonSchema.boolean(
      description:
          'Optional expanded output. Avoid unless the full per-model metadata is specifically needed.',
    ),
  },
  additionalProperties: false,
);

/// Runs the MCP server for cag over stdio.
class McpCommand extends Command<void> {
  McpCommand() {
    argParser
      ..addOption(
        'transport',
        allowed: ['stdio', 'http'],
        defaultsTo: 'stdio',
        help: 'Transport type (stdio or http).',
      )
      ..addOption(
        'host',
        defaultsTo: '127.0.0.1',
        help: 'Host to bind for HTTP transport.',
      )
      ..addOption(
        'port',
        defaultsTo: '7331',
        help: 'Port to bind for HTTP transport.',
      )
      ..addOption(
        'http-path',
        defaultsTo: '/mcp',
        help: 'Path for HTTP MCP requests.',
      );
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
    final transport = StreamableHTTPServerTransport(
      options: StreamableHTTPServerTransportOptions(
        sessionIdGenerator: generateUUID,
      ),
    );
    mcpServer.onError = (error) {
      stderr.writeln('MCP server error: $error');
    };

    await mcpServer.connect(transport);

    final server = await HttpServer.bind(host, port);
    stderr.writeln(
      'MCP HTTP server listening on http://$host:${server.port}$httpPath',
    );

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
  final agentConfigs = AgentCatalog.resolveConfigs(configService, config);
  final enabledAgents = AgentCatalog.enabledNames(agentConfigs);
  final agentDefaults = {
    for (final definition in AgentCatalog.definitions)
      if (agentConfigs[definition.name]?.enabled == true)
        definition.name: definition.defaultModel(
          agentConfigs[definition.name]!,
        ),
  };
  final agents = AgentCatalog.createEnabledAgents(agentConfigs);

  final compareRunner = CompareRunner(agentConfigs: agentConfigs);
  final consensusRunner = ConsensusRunner(agentConfigs: agentConfigs);
  final councilRunner = CouncilRunner(agentConfigs: agentConfigs);

  final modelsSection = _buildModelsSection(agentConfigs);
  final server = McpServer(
    Implementation(name: 'cag', version: _appVersion),
    options: McpServerOptions(
      instructions:
          'cag is a multi-agent gateway that lets you query external AI agents '
          'from within your current session. '
          'Use CAG only when the user explicitly asks for CAG or a specific CAG agent/model, '
          'or when external independent judgment or cross-agent comparison would materially improve the work. '
          'Prefer your own native tools, subagents, or direct model tools for ordinary delegation and simple same-family model calls.\n\n'
          'Regular agent conversations use a universal session_id. If a tool returns session_id, that conversation can be continued later through the matching agent tool with resume/session_id. '
          'Any other returned ID belongs to a CAG wrapper flow and is not interchangeable with session_id. '
          'Provide detailed prompts with full context, constraints, and goals — short prompts produce weak results.\n\n'
          'Agent conversations are not just question-answer — use multi-turn dialogue (resume via session_id) to iterate, challenge ideas, and reach better solutions together.\n\n'
          'Available models:\n$modelsSection',
    ),
  );

  final taskManager = CagAgentTaskManager(
    resolveRequest: (args) => _buildAgentRequest(
      args,
      enabledAgents: enabledAgents,
      agentDefaults: agentDefaults,
      agents: agents,
      agentConfigs: agentConfigs,
    ),
  );

  server.experimental.onListTasks((extra) {
    return taskManager.listTasks();
  });
  server.experimental.onGetTask((taskId, extra) {
    return taskManager.getTask(taskId);
  });
  server.experimental.onTaskResult((taskId, extra) {
    return taskManager.getTaskResult(taskId);
  });
  server.experimental.onCancelTask((taskId, extra) {
    return taskManager.cancelTask(taskId);
  });

  server.registerResource(
    'CAG tasks',
    'cag://tasks',
    (
      description: 'Compact list of CAG agent tasks.',
      mimeType: 'application/json',
    ),
    (uri, extra) async => _jsonResource(uri, await taskManager.readTasksJson()),
  );
  server.registerResourceTemplate(
    'CAG task detail',
    ResourceTemplateRegistration(
      'cag://tasks/{id}',
      listCallback: (extra) => taskManager.listResources(),
    ),
    (
      description: 'CAG task metadata and status.',
      mimeType: 'application/json',
    ),
    (uri, variables, extra) async {
      final taskId = variables['id'] as String;
      return _jsonResource(uri, await taskManager.readTaskJson(taskId));
    },
  );
  server.registerResourceTemplate(
    'CAG task log',
    ResourceTemplateRegistration('cag://tasks/{id}/log', listCallback: null),
    (
      description: 'Full stdout and stderr for a CAG task.',
      mimeType: 'application/json',
    ),
    (uri, variables, extra) async {
      final taskId = variables['id'] as String;
      return _jsonResource(uri, await taskManager.readTaskLog(taskId));
    },
  );
  server.registerResourceTemplate(
    'CAG task result',
    ResourceTemplateRegistration('cag://tasks/{id}/result', listCallback: null),
    (
      description: 'Compact result or failure for a CAG task.',
      mimeType: 'application/json',
    ),
    (uri, variables, extra) async {
      final taskId = variables['id'] as String;
      return _jsonResource(uri, await taskManager.readTaskResultJson(taskId));
    },
  );

  server.experimental.registerToolTask(
    'cag_agent',
    description: _agentToolDescription,
    inputSchema: _buildAgentInputSchema(enabledAgents),
    outputSchema: _agentOutputSchema,
    execution: const ToolExecution(taskSupport: 'optional'),
    handler: CagAgentToolTaskHandler(taskManager),
  );

  server.registerTool(
    'cag_task',
    description:
        'Manage background tasks started with cag_agent mode=background. '
        'Use cag_task to list, inspect, wait for, cancel, or fetch those task results. '
        'Logs are opt-in with include_log=true. task_id is not a session_id. '
        'Prefer action=wait over tight polling loops.',
    inputSchema: _taskInputSchema,
    outputSchema: _taskOutputSchema,
    callback: (args, extra) => taskManager.handleTaskTool(args),
  );

  server.registerTool(
    'cag_compare',
    description:
        'Run multiple agents in parallel without synthesis and return per-branch session_id values plus compare_id for inspection.',
    inputSchema: _buildCompareInputSchema(enabledAgents),
    outputSchema: _compareOutputSchema,
    callback: (args, extra) async {
      final errors = <String>[];
      final prompt = _readStringArg(args, 'prompt', errors, required: true);
      final title = _readStringArg(args, 'title', errors);
      final participantsRaw = args['participants'];
      final verbose = args['verbose'] == true;

      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }
      if (participantsRaw is! List) {
        return _errorResult('participants must be an array of objects.');
      }
      if (participantsRaw.length < 2) {
        return _errorResult('participants must include at least 2 entries.');
      }

      final participants = <CompareParticipant>[];
      for (final entry in participantsRaw) {
        if (entry is! Map) {
          return _errorResult('participants entries must be objects.');
        }

        final agentName = _readMapString(
          entry,
          'agent',
          errors,
          required: true,
        )?.toLowerCase();
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

        final participant = CompareParticipant(agent: agentName!, model: model!)
            .copyWith(
              resolvedModel: _resolveModel(
                agentName,
                model,
                agentConfigs,
                errors,
              ),
            );
        if (errors.isNotEmpty) {
          return _errorResult(errors.join(' '));
        }
        participants.add(participant);
      }

      try {
        final result = await compareRunner.run(
          prompt: prompt!,
          title: title?.trim().isNotEmpty == true
              ? title!
              : buildCompareTitle(prompt),
          participants: participants,
        );
        final output = {
          'result': _formatCompareOutput(result),
          'compare_id': result.compareId,
          if (verbose) 'verbose_data': result.toJson(),
        };
        return CallToolResult.fromStructuredContent(output);
      } on ArgumentError catch (e) {
        return _errorResult(e.message ?? e.toString());
      } on AgentExecutionException catch (e) {
        return _errorResult(
          'Execution error [${e.failure.summary}]: ${e.failure.message}',
        );
      }
    },
  );

  server.registerTool(
    'cag_consensus',
    description:
        'Run consensus across multiple agents. Resume uses consensus_id because this is a CAG-managed flow.',
    inputSchema: _buildConsensusInputSchema(enabledAgents),
    outputSchema: _consensusOutputSchema,
    callback: (args, extra) async {
      final errors = <String>[];
      final prompt = _readStringArg(args, 'prompt', errors, required: true);
      final proposal = _readStringArg(args, 'proposal', errors);
      final resume = _readStringArg(args, 'resume', errors);
      final participantsRaw = args['participants'];
      final verbose = args['verbose'] == true;

      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      if (resume != null && participantsRaw != null) {
        return _errorResult(
          'participants cannot be provided when resume is set.',
        );
      }

      final participants = <ConsensusParticipant>[];
      if (resume == null) {
        if (participantsRaw == null) {
          return _errorResult(
            'participants is required when resume is not set.',
          );
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

          final agentName = _readMapString(
            entry,
            'agent',
            errors,
            required: true,
          )?.toLowerCase();
          final model = _readMapString(entry, 'model', errors, required: true);
          final stanceValue = _readMapString(
            entry,
            'stance',
            errors,
            required: true,
          );
          final sessionId = _readMapString(entry, 'session_id', errors);
          final stancePrompt = _readMapString(entry, 'stance_prompt', errors);

          if (errors.isNotEmpty) {
            return _errorResult(errors.join(' '));
          }

          if (!_knownAgents.contains(agentName)) {
            return _errorResult(
              _agentUnknownMessage(agentName!, enabledAgents),
            );
          }

          if (!enabledAgents.contains(agentName)) {
            return _errorResult(
              _agentDisabledMessage(agentName!, enabledAgents),
            );
          }

          try {
            final participant = ConsensusParticipant(
              agent: agentName!,
              model: model!,
              stance: ConsensusStance.fromString(stanceValue!),
              sessionId: sessionId,
              stancePrompt: stancePrompt,
            );
            participant.resolvedModel = _resolveModel(
              agentName,
              model,
              agentConfigs,
              errors,
            );
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
          final resumeError = await _validateConsensusResume(
            resume,
            enabledAgents,
          );
          if (resumeError != null) {
            return _errorResult(resumeError);
          }
          result = await consensusRunner.resume(
            consensusId: resume,
            prompt: prompt!,
          );
        } else {
          result = await consensusRunner.run(
            prompt: prompt!,
            participants: participants,
            proposal: proposal,
          );
        }

        final verboseData = {
          'consensus_id': result.session.consensusId,
          'prompt': result.session.prompt,
          'results': result.results.map((r) {
            return {
              'participant': r.participant.toJson(),
              'success': r.success,
              if (r.response != null) 'response': _minimalResponse(r.response!),
              if (r.failure != null) 'failure': r.failure!.toJson(),
            };
          }).toList(),
        };

        return CallToolResult.fromStructuredContent({
          'result': _formatConsensusOutput(result),
          'consensus_id': result.session.consensusId,
          if (verbose) 'verbose_data': verboseData,
        });
      } on ArgumentError catch (e) {
        return _errorResult(e.message ?? e.toString());
      } on AgentExecutionException catch (e) {
        return _errorResult(
          'Execution error [${e.failure.summary}]: ${e.failure.message}',
        );
      }
    },
  );

  server.registerTool(
    'cag_council',
    description:
        'Run multi-stage council (answers, reviews, chairman). Returns council_id for inspection and may include answer session_id values for branch follow-up.',
    inputSchema: _buildCouncilInputSchema(enabledAgents),
    outputSchema: _councilOutputSchema,
    callback: (args, extra) async {
      final errors = <String>[];
      final prompt = _readStringArg(args, 'prompt', errors, required: true);
      final includeAnswers = args['include_answers'] == true;
      final verbose = args['verbose'] == true;
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

        final agentName = _readMapString(
          entry,
          'agent',
          errors,
          required: true,
        )?.toLowerCase();
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
        member.resolvedModel = _resolveModel(
          agentName,
          model,
          agentConfigs,
          errors,
        );
        if (errors.isNotEmpty) {
          return _errorResult(errors.join(' '));
        }
        participants.add(member);
      }

      final chairmanAgent = _readMapString(
        chairmanRaw,
        'agent',
        errors,
        required: true,
      )?.toLowerCase();
      final chairmanModel = _readMapString(
        chairmanRaw,
        'model',
        errors,
        required: true,
      );

      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      if (!_knownAgents.contains(chairmanAgent)) {
        return _errorResult(
          _agentUnknownMessage(chairmanAgent!, enabledAgents),
        );
      }

      if (!enabledAgents.contains(chairmanAgent)) {
        return _errorResult(
          _agentDisabledMessage(chairmanAgent!, enabledAgents),
        );
      }

      final chairman = CouncilMember(
        agent: chairmanAgent!,
        model: chairmanModel!,
      );
      chairman.resolvedModel = _resolveModel(
        chairmanAgent,
        chairmanModel,
        agentConfigs,
        errors,
      );
      if (errors.isNotEmpty) {
        return _errorResult(errors.join(' '));
      }

      try {
        final result = await councilRunner.run(
          prompt: prompt!,
          title: buildCompareTitle(prompt),
          participants: participants,
          chairman: chairman,
        );

        return CallToolResult.fromStructuredContent({
          'result': _formatCouncilOutput(
            result,
            includeAnswers: includeAnswers,
          ),
          if (verbose) 'verbose_data': result.toJson(),
        });
      } on ArgumentError catch (e) {
        return _errorResult(e.message ?? e.toString());
      } on AgentExecutionException catch (e) {
        return _errorResult(
          'Execution error [${e.failure.summary}]: ${e.failure.message}',
        );
      }
    },
  );

  /*
  server.registerTool(
    'cag_agents_status',
    description: _agentsStatusToolDescription,
    inputSchema: _emptyInputSchema,
    outputSchema: _agentsStatusOutputSchema,
    callback: (args, extra) async {
      final report = await DoctorService().inspect(includeVersions: false);
      final agents = _mcpAgentStatusRows(report.agents);
      final summary = _mcpStatusSummary(config: report.config, agents: agents);

      return CallToolResult.fromStructuredContent({
        'result': _formatAgentsStatusOutput(report.config, agents, summary),
        'config': _mcpConfigStatus(report.config),
        'agents': agents,
        'summary': summary,
      });
    },
  );
  */

  server.registerTool(
    'cag_models',
    description: _modelsToolDescription,
    inputSchema: _modelsInputSchema,
    outputSchema: _modelsOutputSchema,
    callback: (args, extra) async {
      final verbose = args['verbose'] == true;
      final agentsInfo = _modelAgentsInfo(agentConfigs, enabledAgents);

      return CallToolResult.fromStructuredContent({
        'result': _formatModelsOutput(agentsInfo),
        if (verbose) 'verbose_data': {'agents': agentsInfo},
      });
    },
  );

  server.registerPrompt(
    'cag_discuss',
    title: 'Discuss with AI agent',
    description:
        'Start an iterative dialogue with another AI agent via cag. '
        'You and the agent are colleagues solving a task together.',
    callback: (args, extra) {
      return GetPromptResult(
        description: 'Iterative dialogue with AI agent via cag',
        messages: [
          PromptMessage(
            role: PromptMessageRole.user,
            content: TextContent(text: discussPrompt),
          ),
        ],
      );
    },
  );

  return server;
}

CallToolResult _errorResult(String message) {
  return CallToolResult(content: [TextContent(text: message)], isError: true);
}

ReadResourceResult _jsonResource(Uri uri, String text) {
  return ReadResourceResult(
    contents: [
      TextResourceContents(
        uri: uri.toString(),
        mimeType: 'application/json',
        text: text,
      ),
    ],
  );
}

CagAgentRequest _buildAgentRequest(
  Map<String, dynamic>? args, {
  required List<String> enabledAgents,
  required Map<String, String> agentDefaults,
  required Map<String, BaseAgent> agents,
  required Map<String, AgentConfig> agentConfigs,
}) {
  final input = args ?? <String, dynamic>{};
  final errors = <String>[];
  final agentName = _readStringArg(
    input,
    'agent',
    errors,
    required: true,
  )?.toLowerCase();
  final prompt = _readStringArg(input, 'prompt', errors, required: true);
  final modelInput = _readStringArg(input, 'model', errors);
  final systemPrompt = _readStringArg(input, 'system', errors);
  final resume = _readStringArg(input, 'resume', errors);
  final cwd = _readStringArg(input, 'cwd', errors);
  final name = _readStringArg(input, 'name', errors);
  final modeInput = _readStringArg(input, 'mode', errors) ?? 'sync';
  final verbose = input['verbose'] == true;

  if (errors.isNotEmpty) {
    _throwInvalidParams(errors.join(' '));
  }

  if (agentName == null) {
    _throwInvalidParams(_agentRequiredMessage(enabledAgents));
  }
  if (!_knownAgents.contains(agentName)) {
    _throwInvalidParams(_agentUnknownMessage(agentName, enabledAgents));
  }
  if (!enabledAgents.contains(agentName)) {
    _throwInvalidParams(_agentDisabledMessage(agentName, enabledAgents));
  }

  final agent = agents[agentName];
  if (agent == null) {
    _throwInvalidParams(_agentUnknownMessage(agentName, enabledAgents));
  }

  final model = modelInput ?? agentDefaults[agentName];
  if (model == null || model.isEmpty) {
    _throwInvalidParams('Model is required for agent "$agentName".');
  }

  final mode = switch (modeInput) {
    'sync' => CagAgentMode.sync,
    'background' => CagAgentMode.background,
    _ => null,
  };
  if (mode == null) {
    _throwInvalidParams('mode must be "sync" or "background".');
  }

  final resolvedModel = _resolveModel(agentName, model, agentConfigs, errors);
  if (errors.isNotEmpty) {
    _throwInvalidParams(errors.join(' '));
  }

  return CagAgentRequest(
    agentName: agentName,
    agent: agent,
    prompt: prompt!,
    model: resolvedModel,
    mode: mode,
    systemPrompt: systemPrompt,
    resume: resume,
    cwd: cwd,
    name: name,
    verbose: verbose,
  );
}

Never _throwInvalidParams(String message) {
  throw McpError(ErrorCode.invalidParams.value, message);
}

Map<String, dynamic> _minimalResponse(ParsedResponse response) {
  final metadata = <String, dynamic>{};
  final modelUsed = response.metadata['model_used'];
  final durationMs = response.metadata['duration_ms'];
  final usage = response.metadata['usage'];

  if (response.sessionId != null) {
    metadata['session_id'] = response.sessionId;
  }
  if (modelUsed is String && modelUsed.isNotEmpty) {
    metadata['model_used'] = modelUsed;
  }
  if (durationMs is num) {
    metadata['duration_ms'] = durationMs;
  }
  if (usage is Map) {
    metadata['usage'] = usage;
  }

  return {'content': response.content, 'metadata': metadata};
}

String _formatCompareOutput(CompareRun run) {
  final buffer = StringBuffer();
  buffer.writeln('compare_id: ${run.compareId}');
  buffer.writeln('title: ${run.title}');
  buffer.writeln('====');
  buffer.writeln();

  for (final result in run.results) {
    final participant = result.participant;
    buffer.writeln(
      '=== ${participant.agent.toUpperCase()} (${participant.model}) ===',
    );
    if (result.success) {
      if (participant.sessionId != null) {
        buffer.writeln('session_id: ${participant.sessionId}');
        buffer.writeln('----');
      }
      if (result.response != null) {
        buffer.writeln(result.response!.content);
      }
    } else {
      buffer.writeln('ERROR [${result.failure!.summary}]');
      buffer.writeln(result.failure!.message);
    }
    buffer.writeln();
  }

  return buffer.toString().trimRight();
}

String _formatModelsOutput(List<Map<String, Object?>> agentsInfo) {
  final lines = <String>[];
  for (final agentInfo in agentsInfo) {
    final agent = agentInfo['agent'] as String;
    final models = (agentInfo['models'] as List).cast<Map<String, Object?>>();
    final aliases = models
        .map((model) {
          final name = model['name'] as String;
          final modelAliases = (model['aliases'] as List).cast<String>();
          final description = model['description'] as String? ?? '';
          final parts = <String>[name];
          if (modelAliases.isEmpty) {
            if (description.isNotEmpty) {
              parts.add('- $description');
            }
            return parts.join(' ');
          }
          parts.add('(${modelAliases.join(', ')})');
          if (description.isNotEmpty) {
            parts.add('- $description');
          }
          return parts.join(' ');
        })
        .join(', ');

    lines.add('$agent: $aliases');
  }
  return lines.join(' | ');
}

List<Map<String, Object?>> _modelAgentsInfo(
  Map<String, AgentConfig> agentConfigs,
  List<String> enabledAgents,
) {
  return [
    for (final definition in AgentCatalog.definitions)
      if (enabledAgents.contains(definition.name))
        if (agentConfigs[definition.name] case final config?)
          if (config.availableModels.isNotEmpty)
            {
              'agent': definition.name,
              'default_model': definition.defaultModel(config),
              'models': config.availableModels.map((model) {
                final defaultModel = definition.defaultModel(config);
                return {
                  'name': model.name,
                  'aliases': model.aliases,
                  'description': model.description,
                  'is_default': model.matches(defaultModel),
                };
              }).toList(),
            },
  ];
}

// ignore: unused_element
Map<String, dynamic> _mcpConfigStatus(ConfigDiagnostic config) {
  return {
    'path': config.path,
    'exists': config.exists,
    'valid': config.valid,
    'status': config.status,
    if (config.error != null) 'error': config.error,
  };
}

// ignore: unused_element
List<Map<String, dynamic>> _mcpAgentStatusRows(List<AgentDiagnostic> agents) {
  return agents.map((agent) {
    final status = _mcpAgentStatus(agent);
    final reason = _mcpAgentReason(agent, status);
    return {
      'agent': agent.name,
      'enabled': agent.enabled,
      'status': status,
      if (reason != null) 'reason': reason,
      'executable': agent.executable,
      'executable_found': agent.available,
      'default_model': agent.defaultModel,
      'model_count': agent.modelCount,
      'auth_status': agent.authStatus,
      'execution_mode': agent.executionMode,
    };
  }).toList();
}

String _mcpAgentStatus(AgentDiagnostic agent) {
  if (!agent.enabled) return 'disabled';
  if (!agent.available) return 'missing_executable';
  return 'available';
}

String? _mcpAgentReason(AgentDiagnostic agent, String status) {
  return switch (status) {
    'disabled' => 'disabled in CAG config',
    'missing_executable' => agent.hint,
    _ => null,
  };
}

// ignore: unused_element
Map<String, dynamic> _mcpStatusSummary({
  required ConfigDiagnostic config,
  required List<Map<String, dynamic>> agents,
}) {
  var available = 0;
  var disabled = 0;
  var missingExecutable = 0;

  for (final agent in agents) {
    switch (agent['status']) {
      case 'available':
        available++;
      case 'disabled':
        disabled++;
      case 'missing_executable':
        missingExecutable++;
    }
  }

  return {
    'total': agents.length,
    'available': available,
    'disabled': disabled,
    'missing_executable': missingExecutable,
    'config_valid': config.valid,
  };
}

// ignore: unused_element
String _formatAgentsStatusOutput(
  ConfigDiagnostic config,
  List<Map<String, dynamic>> agents,
  Map<String, dynamic> summary,
) {
  final parts = <String>[
    'config: ${config.status}',
    'available: ${summary['available']}/${summary['total']}',
    'disabled: ${summary['disabled']}',
    'missing_executable: ${summary['missing_executable']}',
  ];

  final unavailable = agents
      .where((agent) => agent['status'] != 'available')
      .map((agent) => '${agent['agent']}=${agent['status']}')
      .join(', ');
  if (unavailable.isNotEmpty) {
    parts.add('attention: $unavailable');
  }

  return parts.join(' | ');
}

String _formatConsensusOutput(ConsensusResult result) {
  final buffer = StringBuffer();
  buffer.writeln('consensus_id: ${result.session.consensusId}');
  buffer.writeln('====');
  buffer.writeln();

  for (final entry in result.results) {
    final participant = entry.participant;
    buffer.writeln(
      '=== ${participant.agent.toUpperCase()} (${participant.model}) [${participant.stance.value.toUpperCase()}] ===',
    );
    if (entry.success) {
      final sessionId = entry.response?.sessionId ?? participant.sessionId;
      if (sessionId != null) {
        buffer.writeln('session_id: $sessionId');
        buffer.writeln('----');
      }
      buffer.writeln(entry.response!.content);
    } else {
      buffer.writeln('ERROR [${entry.failure!.summary}]');
      buffer.writeln(entry.failure!.message);
    }
    buffer.writeln();
  }

  buffer.writeln('==== SUMMARY ====');
  buffer.writeln('Total: ${result.results.length}');
  buffer.writeln('Succeeded: ${result.successful.length}');
  if (result.failed.isNotEmpty) {
    buffer.writeln('Failed: ${result.failed.length}');
    for (final failed in result.failed) {
      buffer.writeln(
        '  - ${failed.participant.agent}: ${OutputFormatter.formatFailure(failed.failure!)}',
      );
    }
  }

  return buffer.toString().trimRight();
}

String _formatCouncilOutput(CouncilRun result, {required bool includeAnswers}) {
  final buffer = StringBuffer();
  buffer.writeln('council_id: ${result.councilId}');
  buffer.writeln('title: ${result.title}');
  buffer.writeln('====');
  buffer.writeln();

  if (includeAnswers) {
    buffer.writeln('==== Stage 1: Answers ====');
    for (final answer in result.answers) {
      final participant = answer.participant;
      buffer.writeln(
        '=== ${participant.agent.toUpperCase()} (${participant.model}) [ANSWER] ===',
      );
      if (answer.success) {
        if (participant.sessionId != null) {
          buffer.writeln('session_id: ${participant.sessionId}');
          buffer.writeln('----');
        }
        buffer.writeln(answer.response!.content);
      } else {
        buffer.writeln('ERROR [${answer.failure!.summary}]');
        buffer.writeln(answer.failure!.message);
      }
      buffer.writeln();
    }
  }

  buffer.writeln('==== Stage 2: Reviews ====');
  for (final review in result.reviews) {
    final participant = review.participant;
    buffer.writeln(
      '=== ${participant.agent.toUpperCase()} (${participant.model}) [REVIEW] ===',
    );
    if (review.success) {
      buffer.writeln(review.response!.content);
    } else {
      buffer.writeln('ERROR [${review.failure!.summary}]');
      buffer.writeln(review.failure!.message);
    }
    buffer.writeln();
  }

  buffer.writeln('==== Stage 3: Chairman ====');
  buffer.writeln(
    '=== ${result.chairmanResult.chairman.agent.toUpperCase()} (${result.chairmanResult.chairman.model}) [CHAIRMAN] ===',
  );
  if (result.chairmanResult.success) {
    buffer.writeln(result.chairmanResult.response!.content);
  } else {
    buffer.writeln('ERROR [${result.chairmanResult.failure!.summary}]');
    buffer.writeln(result.chairmanResult.failure!.message);
  }
  buffer.writeln();

  buffer.writeln('==== Answer Map ====');
  for (var index = 0; index < result.answers.length; index++) {
    final participant = result.answers[index].participant;
    buffer.writeln(
      'ans_${index + 1}: ${participant.agent.toUpperCase()} (${participant.model})',
    );
  }

  return buffer.toString().trimRight();
}

String _buildModelsSection(Map<String, AgentConfig> agentConfigs) {
  final buffer = StringBuffer();
  for (final definition in AgentCatalog.definitions) {
    final config = agentConfigs[definition.name];
    if (config == null || !config.enabled || config.availableModels.isEmpty) {
      continue;
    }
    buffer.writeln('${definition.name}:');
    for (final m in config.availableModels) {
      final alias = m.aliases.isNotEmpty ? ' (${m.aliases.join(', ')})' : '';
      final desc = m.description.isNotEmpty ? ' - ${m.description}' : '';
      buffer.writeln('  ${m.name}$alias$desc');
    }
  }
  return buffer.toString().trimRight();
}

String _normalizePath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '/';
  return trimmed.startsWith('/') ? trimmed : '/$trimmed';
}

String? _readStringArg(
  Map<String, dynamic> args,
  String key,
  List<String> errors, {
  bool required = false,
}) {
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

String? _readMapString(
  Map entry,
  String key,
  List<String> errors, {
  bool required = false,
}) {
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

Future<String?> _validateConsensusResume(
  String consensusId,
  List<String> enabledAgents,
) async {
  final storage = ConsensusStorage();
  final session = await storage.load(consensusId);
  if (session == null) {
    return 'Consensus session not found: $consensusId';
  }

  final unknownAgents = session.participants
      .map((p) => p.agent)
      .where((agent) => !_knownAgents.contains(agent))
      .toSet();
  if (unknownAgents.isNotEmpty) {
    return 'Consensus session includes unknown agents: ${unknownAgents.join(', ')}';
  }

  final disabledAgents = session.participants
      .map((p) => p.agent)
      .where((agent) => !enabledAgents.contains(agent))
      .toSet();
  if (disabledAgents.isNotEmpty) {
    return 'Consensus session includes disabled agents: ${disabledAgents.join(', ')}';
  }

  return null;
}

String _resolveModel(
  String agentName,
  String modelInput,
  Map<String, AgentConfig> agentConfigs,
  List<String> errors,
) {
  final config = agentConfigs[agentName];
  if (config == null || config.availableModels.isEmpty) {
    return modelInput;
  }

  final modelConfig = config.availableModels
      .where((model) => model.matches(modelInput))
      .firstOrNull;
  if (modelConfig == null) {
    final available = config.availableModels.map((m) => m.name).join(', ');
    errors.add(
      'Unknown model "$modelInput" for $agentName. Available: $available',
    );
    return modelInput;
  }

  return modelConfig.resolvedModel;
}

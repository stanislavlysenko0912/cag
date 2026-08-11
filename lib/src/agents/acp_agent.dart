import 'dart:async';
import 'dart:io';

import 'package:acp_dart/acp_dart.dart' as acp;

import '../models/models.dart';
import '../runners/runners.dart';
import 'acp_process.dart';
import 'agent_id.dart';
import 'base_agent.dart';

/// Runs an ACP v1 agent over JSON-RPC using stdio.
class AcpAgent extends BaseAgent {
  AcpAgent({AgentConfig? config, AcpProcessRunner? processRunner})
    : _processRunner = processRunner ?? AcpProcessRunner(),
      super(config: config ?? defaultConfig);

  static final defaultConfig = AgentConfig(
    name: AgentId.acp,
    executable: 'acp-agent',
    parser: 'acp',
    enabled: false,
  );

  final AcpProcessRunner _processRunner;

  /// Starts a short-lived ACP session and reads its advertised model catalog.
  Future<AgentModelDiscovery> discoverModels({String? workingDirectory}) async {
    final cwd = workingDirectory ?? Directory.current.path;
    final execution = await _processRunner.run<AgentModelDiscovery>(
      config: config,
      args: buildArgs(prompt: ''),
      workingDirectory: cwd,
      interact: (process, stdout) =>
          _runDiscovery(process: process, stdout: stdout, cwd: cwd),
    );
    if (execution.error != null || execution.result.failure != null) {
      final failure =
          execution.result.failure ?? _protocolFailure(execution.error!);
      throw AgentExecutionException(failure, result: execution.result);
    }
    return execution.value!;
  }

  @override
  List<String> buildArgs({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
    AgentRunContext? runContext,
  }) {
    return [
      ...config.additionalArgs,
      if (extraArgs != null)
        for (final entry in extraArgs.entries) ...[entry.key, entry.value],
    ];
  }

  @override
  Future<AgentDetailedExecution> executeDetailed({
    required String prompt,
    String? model,
    String? systemPrompt,
    String? resume,
    Map<String, String>? extraArgs,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) async {
    final args = buildArgs(
      prompt: prompt,
      model: model,
      systemPrompt: systemPrompt,
      resume: resume,
      extraArgs: extraArgs,
    );
    final execution = await _processRunner.run<_AcpTurn>(
      config: config,
      args: args,
      model: model,
      workingDirectory: workingDirectory ?? Directory.current.path,
      onProcessStarted: onProcessStarted,
      keepCapture: keepCapture,
      interact: (process, stdout) => _runTurn(
        process: process,
        stdout: stdout,
        prompt: prompt,
        model: model,
        systemPrompt: systemPrompt,
        resume: resume,
        cwd: workingDirectory ?? Directory.current.path,
      ),
    );

    final result = execution.result;
    if (execution.error != null || result.failure != null) {
      final failure = result.failure ?? _protocolFailure(execution.error!);
      throw AgentExecutionException(failure, result: result);
    }

    final turn = execution.value!;
    if (turn.content.trim().isEmpty) {
      final failure = AgentFailure(
        reason: AgentExitReason.emptyResponse,
        message: '${config.name} returned an empty ACP response.',
        exitCode: result.exitCode,
        durationMs: result.durationMs,
        hadPartialOutput:
            result.stdout.trim().isNotEmpty || result.stderr.trim().isNotEmpty,
      );
      throw AgentExecutionException(failure, result: result);
    }

    return AgentDetailedExecution(
      response: ParsedResponse(
        content: turn.content,
        metadata: {
          'session_id': turn.sessionId,
          'stop_reason': turn.stopReason,
          if (turn.usage != null) 'usage': turn.usage,
          if (model != null) 'model_used': model,
          'duration_ms': result.durationMs,
        },
      ),
      result: result,
    );
  }

  Future<_AcpTurn> _runTurn({
    required Process process,
    required Stream<List<int>> stdout,
    required String prompt,
    required String? model,
    required String? systemPrompt,
    required String? resume,
    required String cwd,
  }) {
    final parseError = Completer<_AcpTurn>();
    final stream = acp.ndJsonStream(
      stdout,
      process.stdin,
      onParseError: (line, error) {
        if (!parseError.isCompleted) {
          parseError.completeError(
            FormatException('Invalid ACP message: $error', line),
          );
        }
      },
    );
    final client = _CagAcpClient();
    final connection = acp.ClientSideConnection((_) => client, stream);

    return Future.any([
      _runLifecycle(
        connection: connection,
        client: client,
        prompt: prompt,
        model: model,
        systemPrompt: systemPrompt,
        resume: resume,
        cwd: cwd,
      ),
      parseError.future,
    ]);
  }

  Future<AgentModelDiscovery> _runDiscovery({
    required Process process,
    required Stream<List<int>> stdout,
    required String cwd,
  }) {
    final parseError = Completer<AgentModelDiscovery>();
    final stream = acp.ndJsonStream(
      stdout,
      process.stdin,
      onParseError: (line, error) {
        if (!parseError.isCompleted) {
          parseError.completeError(
            FormatException('Invalid ACP message: $error', line),
          );
        }
      },
    );
    final connection = acp.ClientSideConnection((_) => _CagAcpClient(), stream);
    return Future.any([
      _discoverLifecycle(connection: connection, cwd: cwd),
      parseError.future,
    ]);
  }

  Future<_AcpTurn> _runLifecycle({
    required acp.ClientSideConnection connection,
    required _CagAcpClient client,
    required String prompt,
    required String? model,
    required String? systemPrompt,
    required String? resume,
    required String cwd,
  }) async {
    final initialized = await _initialize(connection);

    final session = await _openSession(
      connection: connection,
      initialized: initialized,
      resume: resume,
      cwd: cwd,
    );
    client.resetMessages();
    if (model != null) {
      await _selectModel(
        connection: connection,
        session: session,
        model: model,
      );
    }

    final response = await connection.prompt(
      acp.PromptRequest(
        sessionId: session.sessionId,
        prompt: [
          acp.TextContentBlock(
            text: _promptText(
              prompt: prompt,
              systemPrompt: systemPrompt,
              isResume: resume != null,
            ),
          ),
        ],
      ),
    );
    final responseJson = response.toJson();
    return _AcpTurn(
      content: client.message,
      sessionId: session.sessionId,
      stopReason: responseJson['stopReason'].toString(),
      usage: response.usage?.toJson(),
    );
  }

  Future<AgentModelDiscovery> _discoverLifecycle({
    required acp.ClientSideConnection connection,
    required String cwd,
  }) async {
    final initialized = await _initialize(connection);
    final session = await _openSession(
      connection: connection,
      initialized: initialized,
      resume: null,
      cwd: cwd,
    );
    return _modelDiscovery(session);
  }

  Future<acp.InitializeResponse> _initialize(
    acp.ClientSideConnection connection,
  ) async {
    final initialized = await connection.initialize(
      acp.InitializeRequest(
        protocolVersion: 1,
        clientCapabilities: acp.ClientCapabilities(
          fs: acp.FileSystemCapability(),
        ),
        clientInfo: acp.Implementation(
          name: 'cag',
          title: 'CAG',
          version: '0.3.1',
        ),
      ),
    );
    if (initialized.protocolVersion != 1) {
      throw StateError(
        'Unsupported ACP protocol version ${initialized.protocolVersion}.',
      );
    }
    return initialized;
  }

  Future<_AcpSession> _openSession({
    required acp.ClientSideConnection connection,
    required acp.InitializeResponse initialized,
    required String? resume,
    required String cwd,
  }) async {
    if (resume == null) {
      final created = await connection.newSession(
        acp.NewSessionRequest(cwd: cwd, mcpServers: const []),
      );
      return _AcpSession(
        sessionId: created.sessionId,
        configOptions: created.configOptions,
        models: created.models,
      );
    }

    if (initialized.agentCapabilities?.loadSession != true) {
      throw StateError('${config.name} does not support ACP session/load.');
    }
    final loaded = await connection.loadSession(
      acp.LoadSessionRequest(cwd: cwd, mcpServers: const [], sessionId: resume),
    );
    if (loaded == null) {
      throw StateError('${config.name} did not load ACP session "$resume".');
    }
    return _AcpSession(
      sessionId: resume,
      configOptions: loaded.configOptions,
      models: loaded.models,
    );
  }

  Future<void> _selectModel({
    required acp.ClientSideConnection connection,
    required _AcpSession session,
    required String model,
  }) async {
    final modelOption = _modelOption(session.configOptions);
    if (modelOption != null) {
      await connection.setSessionConfigOption(
        acp.SetSessionConfigOptionRequest(
          sessionId: session.sessionId,
          configId: modelOption.id,
          value: model,
        ),
      );
      return;
    }
    final supportsLegacyModel =
        session.models?.availableModels.any(
          (candidate) => candidate.modelId == model,
        ) ??
        false;
    if (supportsLegacyModel) {
      await connection.setSessionModel(
        acp.SetSessionModelRequest(
          sessionId: session.sessionId,
          modelId: model,
        ),
      );
      return;
    }
    throw StateError(
      '${config.name} does not advertise ACP model selection for "$model".',
    );
  }

  AgentModelDiscovery _modelDiscovery(_AcpSession session) {
    final option = _modelOption(session.configOptions);
    if (option != null) {
      final options = switch (option.options) {
        acp.UngroupedSessionConfigSelectOptions(:final options) => options,
        acp.GroupedSessionConfigSelectOptions(:final groups) => groups.expand(
          (group) => group.options,
        ),
        _ => const <acp.SessionConfigSelectOption>[],
      };
      return AgentModelDiscovery(
        defaultModel: option.currentValue,
        models: [
          for (final model in options)
            ModelConfig(
              name: model.value,
              description:
                  model.description ??
                  (model.name == model.value ? null : model.name),
              isDefault: model.value == option.currentValue,
            ),
        ],
      );
    }

    final legacy = session.models;
    if (legacy == null) {
      return const AgentModelDiscovery(models: []);
    }
    return AgentModelDiscovery(
      defaultModel: legacy.currentModelId,
      models: [
        for (final model in legacy.availableModels)
          ModelConfig(
            name: model.modelId,
            description:
                model.description ??
                (model.name == model.modelId ? null : model.name),
            isDefault: model.modelId == legacy.currentModelId,
          ),
      ],
    );
  }

  acp.SessionConfigOption? _modelOption(
    List<acp.SessionConfigOption>? options,
  ) {
    if (options == null) return null;
    return options.where((option) => option.category == 'model').firstOrNull ??
        options.where((option) => option.id == 'model').firstOrNull;
  }

  String _promptText({
    required String prompt,
    required String? systemPrompt,
    required bool isResume,
  }) {
    if (isResume || systemPrompt == null || systemPrompt.trim().isEmpty) {
      return prompt;
    }
    return '<system_instructions>\n$systemPrompt\n</system_instructions>\n\n'
        '$prompt';
  }

  AgentFailure _protocolFailure(Object error) {
    return AgentFailure(
      reason: AgentExitReason.cliError,
      message: 'ACP execution failed: $error',
    );
  }
}

class _CagAcpClient implements acp.Client {
  final StringBuffer _messages = StringBuffer();

  String get message => _messages.toString();

  void resetMessages() => _messages.clear();

  @override
  Future<acp.RequestPermissionResponse> requestPermission(
    acp.RequestPermissionRequest params,
  ) async {
    final allowOnce = params.options
        .where((option) => option.kind == acp.PermissionOptionKind.allowOnce)
        .firstOrNull;
    final outcome = allowOnce == null
        ? acp.CancelledOutcome()
        : acp.SelectedOutcome(optionId: allowOnce.optionId);
    return acp.RequestPermissionResponse(outcome: outcome);
  }

  @override
  Future<void> sessionUpdate(acp.SessionNotification params) async {
    final update = params.update;
    if (update is acp.AgentMessageChunkSessionUpdate &&
        update.content is acp.TextContentBlock) {
      _messages.write((update.content as acp.TextContentBlock).text);
    }
  }

  @override
  Future<acp.WriteTextFileResponse>? writeTextFile(
    acp.WriteTextFileRequest params,
  ) => null;

  @override
  Future<acp.ReadTextFileResponse>? readTextFile(
    acp.ReadTextFileRequest params,
  ) => null;

  @override
  Future<acp.CreateTerminalResponse>? createTerminal(
    acp.CreateTerminalRequest params,
  ) => null;

  @override
  Future<acp.TerminalOutputResponse>? terminalOutput(
    acp.TerminalOutputRequest params,
  ) => null;

  @override
  Future<acp.ReleaseTerminalResponse?>? releaseTerminal(
    acp.ReleaseTerminalRequest params,
  ) => null;

  @override
  Future<acp.WaitForTerminalExitResponse>? waitForTerminalExit(
    acp.WaitForTerminalExitRequest params,
  ) => null;

  @override
  Future<acp.KillTerminalCommandResponse?>? killTerminal(
    acp.KillTerminalCommandRequest params,
  ) => null;

  @override
  Future<Map<String, dynamic>>? extMethod(
    String method,
    Map<String, dynamic> params,
  ) => null;

  @override
  Future<void>? extNotification(String method, Map<String, dynamic> params) =>
      null;
}

class _AcpSession {
  const _AcpSession({
    required this.sessionId,
    required this.configOptions,
    required this.models,
  });

  final String sessionId;
  final List<acp.SessionConfigOption>? configOptions;
  final acp.SessionModelState? models;
}

class _AcpTurn {
  const _AcpTurn({
    required this.content,
    required this.sessionId,
    required this.stopReason,
    required this.usage,
  });

  final String content;
  final String sessionId;
  final String stopReason;
  final Map<String, dynamic>? usage;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cag/cag.dart';
import 'package:mcp_dart/mcp_dart.dart';

typedef AgentRequestResolver =
    CagAgentRequest Function(Map<String, dynamic>? args);

/// Manages MCP task-backed CAG agent executions.
class CagAgentTaskManager {
  CagAgentTaskManager({
    required AgentRequestResolver resolveRequest,
    Duration retention = const Duration(hours: 1),
    Duration pollInterval = const Duration(seconds: 1),
    int perAgentConcurrencyLimit = 3,
  }) : _resolveRequest = resolveRequest,
       _retention = retention,
       _pollInterval = pollInterval,
       _perAgentConcurrencyLimit = perAgentConcurrencyLimit {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(sweepExpiredTasks());
    });
  }

  final AgentRequestResolver _resolveRequest;
  final Duration _retention;
  final Duration _launcherRetention = const Duration(minutes: 2);
  final Duration _pollInterval;
  final int _perAgentConcurrencyLimit;
  final Map<String, _CagAgentTask> _tasks = {};
  final Map<String, List<Completer<void>>> _waiters = {};
  Timer? _cleanupTimer;

  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) async {
    await sweepExpiredTasks();

    final request = _resolveRequest(args);
    final runningForAgent = _tasks.values
        .where(
          (task) =>
              task.request.agentName == request.agentName &&
              task.status == TaskStatus.working,
        )
        .length;
    if (runningForAgent >= _perAgentConcurrencyLimit) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Agent "${request.agentName}" is overloaded: '
        '$_perAgentConcurrencyLimit background task(s) already running.',
      );
    }

    final task = _createRealTask(request);
    _tasks[task.taskId] = task;
    _notify(task.taskId);

    unawaited(_runTask(task));

    if (request.mode == CagAgentMode.background) {
      final launcher = _createLauncherTask(request, task);
      _tasks[launcher.taskId] = launcher;
      _notify(launcher.taskId);
      return CreateTaskResult(task: launcher.toMcpTask());
    }

    return CreateTaskResult(task: task.toMcpTask());
  }

  Future<void> waitForTerminal(String taskId) async {
    await sweepExpiredTasks();
    final task = _visibleTaskOrThrow(taskId);
    if (task.status.isTerminal) return;

    final completer = Completer<void>();
    _waiters.putIfAbsent(taskId, () => []).add(completer);
    await completer.future;
  }

  Future<CallToolResult> handleTaskTool(Map<String, dynamic>? args) async {
    try {
      final input = args ?? <String, dynamic>{};
      final action = input['action'];
      if (action is! String) {
        return _taskToolError('action is required.');
      }

      return switch (action) {
        'list' => _taskToolList(),
        'get' => _taskToolGet(input),
        'result' => _taskToolResult(input),
        'wait' => _taskToolWait(input),
        'wait_any' => _taskToolWaitAny(input),
        'cancel' => _taskToolCancel(input),
        _ => _taskToolError(
          'Unknown action "$action". Use list, get, result, wait, wait_any, or cancel.',
        ),
      };
    } on McpError catch (error) {
      return _taskToolError(error.message);
    }
  }

  _CagAgentTask _createRealTask(CagAgentRequest request) {
    return _CagAgentTask(
      taskId: generateUUID().replaceAll('-', ''),
      request: request,
      createdAt: DateTime.now(),
      retention: _retention,
      pollInterval: _pollInterval,
    );
  }

  _CagAgentTask _createLauncherTask(
    CagAgentRequest request,
    _CagAgentTask realTask,
  ) {
    final launcher = _CagAgentTask(
      taskId: generateUUID().replaceAll('-', ''),
      request: request,
      createdAt: DateTime.now(),
      retention: _launcherRetention,
      pollInterval: _pollInterval,
      isLauncher: true,
      launcherPayload: realTask.toBackgroundHandle(),
    );
    launcher
      ..status = TaskStatus.completed
      ..latestMessage = 'Background task started'
      ..terminalAt = launcher.createdAt;
    return launcher;
  }

  Future<ListTasksResult> listTasks() async {
    await sweepExpiredTasks();
    return ListTasksResult(
      tasks: _visibleTasks().map((t) => t.toMcpTask()).toList(),
    );
  }

  Future<Task> getTask(String taskId) async {
    await sweepExpiredTasks();
    return _taskOrThrow(taskId).toMcpTask();
  }

  Future<void> cancelTask(String taskId) async {
    await sweepExpiredTasks();
    final task = _visibleTaskOrThrow(taskId);
    if (task.status.isTerminal) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Cannot cancel task: not found or already terminal',
      );
    }

    task.status = TaskStatus.cancelled;
    task.latestMessage = 'Task cancelled by client';
    task.terminalAt = DateTime.now();
    task.updatedAt = DateTime.now();
    await task.runningProcess?.kill();
    task.runningProcess = null;
    _notify(taskId);
  }

  Future<CallToolResult> getTaskResult(String taskId) async {
    await sweepExpiredTasks();
    final task = _taskOrThrow(taskId);
    if (!task.status.isTerminal) {
      throw McpError(
        ErrorCode.invalidParams.value,
        'Result not available for non-terminal task: $taskId',
      );
    }
    return task.toCallToolResult();
  }

  Future<String> readTasksJson() async {
    final result = await listTasks();
    return const JsonEncoder.withIndent('  ').convert(result.toJson());
  }

  Future<String> readTaskJson(String taskId) async {
    final task = _visibleTaskOrThrow(taskId);
    return const JsonEncoder.withIndent('  ').convert(task.toResourceJson());
  }

  Future<String> readTaskResultJson(String taskId) async {
    final task = _visibleTaskOrThrow(taskId);
    return const JsonEncoder.withIndent('  ').convert(task.toResultJson());
  }

  Future<String> readTaskLog(String taskId) async {
    final task = _visibleTaskOrThrow(taskId);
    final stdoutText = await _readIfExists(task.stdoutPath);
    final stderrText = await _readIfExists(task.stderrPath);
    return const JsonEncoder.withIndent('  ').convert({
      'task_id': task.taskId,
      'stdout': stdoutText,
      'stderr': stderrText,
    });
  }

  Future<ListResourcesResult> listResources() async {
    await sweepExpiredTasks();
    final resources = <Resource>[];
    for (final task in _visibleTasks()) {
      resources
        ..add(
          _resource('cag://tasks/${task.taskId}', 'CAG task ${task.taskId}'),
        )
        ..add(
          _resource(
            'cag://tasks/${task.taskId}/result',
            'CAG task ${task.taskId} result',
          ),
        )
        ..add(
          _resource(
            'cag://tasks/${task.taskId}/log',
            'CAG task ${task.taskId} log',
          ),
        );
    }
    return ListResourcesResult(resources: resources);
  }

  Future<String?> debugStdoutPath(String taskId) async {
    return _taskOrThrow(taskId).stdoutPath;
  }

  Future<void> sweepExpiredTasks() async {
    final now = DateTime.now();
    final expiredIds = <String>[];
    for (final entry in _tasks.entries) {
      final task = entry.value;
      if (!task.status.isTerminal) continue;
      final terminalAt = task.terminalAt;
      if (terminalAt == null) continue;
      if (now.difference(terminalAt) >= _retention) {
        expiredIds.add(entry.key);
      }
    }

    for (final taskId in expiredIds) {
      final task = _tasks.remove(taskId);
      await task?.deleteCaptureFiles();
      _notify(taskId);
    }
  }

  Future<void> dispose() async {
    _cleanupTimer?.cancel();
    for (final task in _tasks.values) {
      await task.deleteCaptureFiles();
    }
    _tasks.clear();
    for (final waiters in _waiters.values) {
      for (final waiter in waiters) {
        if (!waiter.isCompleted) {
          waiter.complete();
        }
      }
    }
    _waiters.clear();
  }

  Future<void> _runTask(_CagAgentTask task) async {
    try {
      final execution = await task.request.agent.executeDetailed(
        prompt: task.request.prompt,
        model: task.request.model,
        systemPrompt: task.request.systemPrompt,
        resume: task.request.resume,
        workingDirectory: task.request.cwd,
        keepCapture: true,
        onProcessStarted: (process) {
          if (task.status == TaskStatus.cancelled) {
            unawaited(process.kill());
            return;
          }
          task
            ..pid = process.pid
            ..runningProcess = process
            ..latestMessage = 'Process started (PID ${process.pid})'
            ..updatedAt = DateTime.now();
          _notify(task.taskId);
        },
      );

      if (task.status == TaskStatus.cancelled) {
        return;
      }
      task
        ..status = TaskStatus.completed
        ..response = execution.response
        ..stdoutPath = execution.result.stdoutPath
        ..stderrPath = execution.result.stderrPath
        ..latestMessage = 'Completed'
        ..terminalAt = DateTime.now()
        ..updatedAt = DateTime.now()
        ..runningProcess = null;
    } on AgentExecutionException catch (error) {
      if (task.status == TaskStatus.cancelled) {
        return;
      }
      task
        ..status = TaskStatus.failed
        ..failure = error.failure
        ..stdoutPath = error.result?.stdoutPath
        ..stderrPath = error.result?.stderrPath
        ..latestMessage = error.failure.message
        ..terminalAt = DateTime.now()
        ..updatedAt = DateTime.now()
        ..runningProcess = null;
    } catch (error) {
      if (task.status == TaskStatus.cancelled) {
        return;
      }
      task
        ..status = TaskStatus.failed
        ..failure = AgentFailure(
          reason: AgentExitReason.crash,
          message: error.toString(),
        )
        ..latestMessage = error.toString()
        ..terminalAt = DateTime.now()
        ..updatedAt = DateTime.now()
        ..runningProcess = null;
    } finally {
      _notify(task.taskId);
    }
  }

  _CagAgentTask _taskOrThrow(String taskId) {
    final task = _tasks[taskId];
    if (task == null) {
      throw McpError(ErrorCode.invalidParams.value, 'Task not found: $taskId');
    }
    return task;
  }

  _CagAgentTask _visibleTaskOrThrow(String taskId) {
    final task = _taskOrThrow(taskId);
    if (task.isLauncher) {
      throw McpError(ErrorCode.invalidParams.value, 'Task not found: $taskId');
    }
    return task;
  }

  Iterable<_CagAgentTask> _visibleTasks() {
    return _tasks.values.where((task) => !task.isLauncher);
  }

  void _notify(String taskId) {
    final task = _tasks[taskId];
    if (task != null && !task.status.isTerminal) return;
    final waiters = _waiters.remove(taskId);
    if (waiters == null) return;
    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  Future<String> _readIfExists(String? path) async {
    if (path == null) return '';
    final file = File(path);
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Resource _resource(String uri, String name) {
    return Resource(uri: uri, name: name, mimeType: 'application/json');
  }

  Future<CallToolResult> _taskToolList() async {
    await sweepExpiredTasks();
    final tasks = _visibleTasks().map((task) => task.toListJson()).toList();
    return CallToolResult.fromStructuredContent({
      'result': tasks.isEmpty
          ? 'No background CAG tasks.'
          : '${tasks.length} task(s).',
      'tasks': tasks,
    });
  }

  Future<CallToolResult> _taskToolGet(Map<String, dynamic> input) async {
    final taskId = _requiredTaskId(input);
    await sweepExpiredTasks();
    final task = _visibleTaskOrThrow(taskId);
    final includeLog = input['include_log'] == true;
    return CallToolResult.fromStructuredContent({
      'result': 'Task $taskId is ${task.status.name}.',
      'task': task.toResourceJson(),
      if (includeLog) 'log': await _taskLogJson(task),
    });
  }

  Future<CallToolResult> _taskToolResult(Map<String, dynamic> input) async {
    final taskId = _requiredTaskId(input);
    await sweepExpiredTasks();
    final task = _visibleTaskOrThrow(taskId);
    if (!task.status.isTerminal) {
      return _taskToolError(
        'Task $taskId is still ${task.status.name}; use action=wait.',
      );
    }
    final includeLog = input['include_log'] == true;
    return CallToolResult.fromStructuredContent({
      'result': _taskResultMessage(task),
      'task': task.toResultJson(),
      if (includeLog) 'log': await _taskLogJson(task),
    });
  }

  Future<CallToolResult> _taskToolWait(Map<String, dynamic> input) async {
    final taskId = _requiredTaskId(input);
    final timeout = _timeout(input);
    final completed = await waitForTerminal(
      taskId,
    ).then((_) => true).timeout(timeout, onTimeout: () => false);
    final task = _visibleTaskOrThrow(taskId);
    final includeLog = input['include_log'] == true;
    if (!completed) {
      return CallToolResult.fromStructuredContent({
        'result': 'Task $taskId is still ${task.status.name}.',
        'timed_out': true,
        'task': task.toResourceJson(),
        if (includeLog) 'log': await _taskLogJson(task),
      });
    }

    return CallToolResult.fromStructuredContent({
      'result': _taskResultMessage(task),
      'task': task.toResultJson(),
      if (includeLog) 'log': await _taskLogJson(task),
    });
  }

  Future<CallToolResult> _taskToolWaitAny(Map<String, dynamic> input) async {
    final taskIds = _requiredTaskIds(input);
    final timeout = _timeout(input);
    for (final taskId in taskIds) {
      _visibleTaskOrThrow(taskId);
    }

    final completedTaskId = await Future.any<String?>(
      taskIds.map((taskId) => waitForTerminal(taskId).then((_) => taskId)),
    ).timeout(timeout, onTimeout: () => null);

    if (completedTaskId == null) {
      final tasks = <Map<String, dynamic>>[];
      for (final taskId in taskIds) {
        tasks.add(_visibleTaskOrThrow(taskId).toListJson());
      }
      return CallToolResult.fromStructuredContent({
        'result': 'No task finished before timeout.',
        'timed_out': true,
        'tasks': tasks,
      });
    }

    final task = _visibleTaskOrThrow(completedTaskId);
    final includeLog = input['include_log'] == true;
    return CallToolResult.fromStructuredContent({
      'result': _taskResultMessage(task),
      'task': task.toResultJson(),
      if (includeLog) 'log': await _taskLogJson(task),
    });
  }

  Future<CallToolResult> _taskToolCancel(Map<String, dynamic> input) async {
    final taskId = _requiredTaskId(input);
    await cancelTask(taskId);
    final task = _visibleTaskOrThrow(taskId);
    return CallToolResult.fromStructuredContent({
      'result': 'Task $taskId cancelled.',
      'task': task.toResourceJson(),
    });
  }

  String _requiredTaskId(Map<String, dynamic> input) {
    final taskId = input['task_id'];
    if (taskId is! String || taskId.isEmpty) {
      _throwInvalidParams('task_id is required for this action.');
    }
    return taskId;
  }

  List<String> _requiredTaskIds(Map<String, dynamic> input) {
    final taskIds = input['task_ids'];
    if (taskIds is! List || taskIds.isEmpty) {
      _throwInvalidParams('task_ids is required for wait_any.');
    }
    final result = <String>[];
    for (final taskId in taskIds) {
      if (taskId is! String || taskId.isEmpty) {
        _throwInvalidParams('task_ids must contain non-empty strings.');
      }
      result.add(taskId);
    }
    return result;
  }

  Duration _timeout(Map<String, dynamic> input) {
    final value = input['timeout_ms'];
    final milliseconds = value is int ? value : 30000;
    return Duration(milliseconds: milliseconds.clamp(1000, 120000).toInt());
  }

  Future<Map<String, String>> _taskLogJson(_CagAgentTask task) async {
    return {
      'stdout': await _readIfExists(task.stdoutPath),
      'stderr': await _readIfExists(task.stderrPath),
    };
  }

  String _taskResultMessage(_CagAgentTask task) {
    return switch (task.status) {
      TaskStatus.completed => 'Task ${task.taskId} completed.',
      TaskStatus.cancelled => 'Task ${task.taskId} cancelled.',
      TaskStatus.failed => 'Task ${task.taskId} failed.',
      _ => 'Task ${task.taskId} is ${task.status.name}.',
    };
  }

  CallToolResult _taskToolError(String message) {
    return CallToolResult(content: [TextContent(text: message)], isError: true);
  }
}

class CagAgentToolTaskHandler implements ToolTaskHandler {
  CagAgentToolTaskHandler(this._manager);

  final CagAgentTaskManager _manager;

  @override
  Future<CreateTaskResult> createTask(
    Map<String, dynamic>? args,
    RequestHandlerExtra? extra,
  ) {
    return _manager.createTask(args, extra);
  }

  @override
  Future<Task> getTask(String taskId, RequestHandlerExtra? extra) {
    return _manager.getTask(taskId);
  }

  @override
  Future<void> cancelTask(String taskId, RequestHandlerExtra? extra) {
    return _manager.cancelTask(taskId);
  }

  @override
  Future<CallToolResult> getTaskResult(
    String taskId,
    RequestHandlerExtra? extra,
  ) {
    return _manager.getTaskResult(taskId);
  }
}

class CagAgentRequest {
  CagAgentRequest({
    required this.agentName,
    required this.agent,
    required this.prompt,
    required this.model,
    required this.mode,
    required this.verbose,
    this.systemPrompt,
    this.resume,
    this.cwd,
    this.name,
  });

  final String agentName;
  final BaseAgent agent;
  final String prompt;
  final String model;
  final CagAgentMode mode;
  final bool verbose;
  final String? systemPrompt;
  final String? resume;
  final String? cwd;
  final String? name;
}

enum CagAgentMode { sync, background }

class _CagAgentTask {
  _CagAgentTask({
    required this.taskId,
    required this.request,
    required this.createdAt,
    required this.retention,
    required this.pollInterval,
    this.isLauncher = false,
    this.launcherPayload,
  }) : updatedAt = createdAt;

  final String taskId;
  final CagAgentRequest request;
  final DateTime createdAt;
  final Duration retention;
  final Duration pollInterval;
  final bool isLauncher;
  final Map<String, dynamic>? launcherPayload;
  DateTime updatedAt;
  DateTime? terminalAt;
  TaskStatus status = TaskStatus.working;
  String latestMessage = 'Task started';
  int? pid;
  RunningProcess? runningProcess;
  String? stdoutPath;
  String? stderrPath;
  ParsedResponse? response;
  AgentFailure? failure;

  Task toMcpTask() {
    return Task(
      taskId: taskId,
      status: status,
      statusMessage: latestMessage,
      ttl: retention.inMilliseconds,
      pollInterval: pollInterval.inMilliseconds,
      createdAt: createdAt.toIso8601String(),
      lastUpdatedAt: updatedAt.toIso8601String(),
      meta: {
        'name': request.name ?? request.prompt,
        'agent': request.agentName,
        'model': request.model,
        if (request.cwd != null) 'cwd': request.cwd,
        if (pid != null) 'pid': pid,
      },
    );
  }

  CallToolResult toCallToolResult() {
    if (isLauncher && launcherPayload != null) {
      return CallToolResult.fromStructuredContent(launcherPayload!);
    }

    if (status == TaskStatus.completed && response != null) {
      return CallToolResult.fromStructuredContent({
        'result': response!.content,
        if (response!.sessionId != null) 'session_id': response!.sessionId,
        if (request.verbose) 'verbose_data': _minimalResponse(response!),
      });
    }

    final message = failure?.message ?? latestMessage;
    return CallToolResult(
      content: [
        TextContent(
          text: status == TaskStatus.cancelled
              ? 'Execution cancelled: $message'
              : 'Execution error [${failure?.summary ?? status.name}]: $message',
        ),
      ],
      isError: true,
    );
  }

  Map<String, dynamic> toResourceJson() {
    return {
      'task_id': taskId,
      'status': status.name,
      'latest_message': latestMessage,
      'agent': request.agentName,
      'model': request.model,
      if (request.name != null) 'name': request.name,
      if (request.cwd != null) 'cwd': request.cwd,
      if (pid != null) 'pid': pid,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      if (terminalAt != null) 'terminal_at': terminalAt!.toIso8601String(),
      'ttl_ms': retention.inMilliseconds,
    };
  }

  Map<String, dynamic> toListJson() {
    return {
      'task_id': taskId,
      'status': status.name,
      'agent': request.agentName,
      'model': request.model,
      if (request.name != null) 'name': request.name,
      'created_at': createdAt.toIso8601String(),
      'message': latestMessage,
    };
  }

  Map<String, dynamic> toBackgroundHandle() {
    return {
      'result':
          'Started ${request.agentName} background task $taskId; use cag_task to wait or fetch the result.',
      'task_id': taskId,
      'status': status.name,
      'agent': request.agentName,
      'model': request.model,
      if (request.cwd != null) 'cwd': request.cwd,
      if (request.name != null) 'name': request.name,
      'started_at': createdAt.toIso8601String(),
      'message': latestMessage,
    };
  }

  Map<String, dynamic> toResultJson() {
    return {
      ...toResourceJson(),
      if (response != null)
        'result': {
          'content': response!.content,
          if (response!.sessionId != null) 'session_id': response!.sessionId,
        },
      if (failure != null) 'failure': failure!.toJson(),
    };
  }

  Future<void> deleteCaptureFiles() async {
    await Future.wait([
      _deleteIfExists(stdoutPath),
      _deleteIfExists(stderrPath),
    ]);
    final parent = stdoutPath == null ? null : File(stdoutPath!).parent;
    if (parent != null && await parent.exists()) {
      try {
        await parent.delete(recursive: true);
      } on FileSystemException {
        // Best effort: retained logs should not block task eviction.
      }
    }
  }

  Future<void> _deleteIfExists(String? path) async {
    if (path == null) return;
    final file = File(path);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best effort cleanup.
    }
  }
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

Never _throwInvalidParams(String message) {
  throw McpError(ErrorCode.invalidParams.value, message);
}

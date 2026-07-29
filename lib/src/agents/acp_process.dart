import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/models.dart';
import '../runners/runners.dart';

typedef AcpInteraction<T> =
    Future<T> Function(Process process, Stream<List<int>> stdout);

class AcpProcessExecution<T> {
  const AcpProcessExecution({
    required this.result,
    this.value,
    this.error,
    this.stackTrace,
  });

  final CLIResult result;
  final T? value;
  final Object? error;
  final StackTrace? stackTrace;
}

class AcpProcessRunner {
  AcpProcessRunner({CLIRunner? runner}) : _runner = runner ?? CLIRunner();

  final CLIRunner _runner;

  Future<AcpProcessExecution<T>> run<T>({
    required AgentConfig config,
    required List<String> args,
    required AcpInteraction<T> interact,
    String? model,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) async {
    final capture = await _AcpOutputCapture.create(retainFiles: keepCapture);
    var retainCapture = false;
    try {
      final execution = await _runProcess(
        config: config,
        args: args,
        interact: interact,
        capture: capture,
        model: model,
        workingDirectory: workingDirectory,
        onProcessStarted: onProcessStarted,
      );
      if (!keepCapture) return execution;
      retainCapture = true;
      return AcpProcessExecution<T>(
        value: execution.value,
        error: execution.error,
        stackTrace: execution.stackTrace,
        result: execution.result.copyWith(
          stdoutPath: capture.stdoutPath,
          stderrPath: capture.stderrPath,
        ),
      );
    } finally {
      if (!retainCapture) await capture.delete();
    }
  }

  Future<AcpProcessExecution<T>> _runProcess<T>({
    required AgentConfig config,
    required List<String> args,
    required AcpInteraction<T> interact,
    required _AcpOutputCapture capture,
    required String? model,
    required String? workingDirectory,
    required ProcessStarted? onProcessStarted,
  }) async {
    final stopwatch = Stopwatch()..start();
    final command = ProcessCommand.forAgent(config, args);
    final Process process;
    try {
      process = await Process.start(
        _runner.resolveExecutable(command.executable),
        command.args,
        environment: {...Platform.environment, ...config.environmentFor(model)},
        workingDirectory: workingDirectory,
        runInShell: false,
      );
    } on ProcessException catch (error, stackTrace) {
      return _startFailure(error, stackTrace, stopwatch);
    }

    onProcessStarted?.call(RunningProcess(process));
    final stdout = process.stdout.asBroadcastStream();
    final captureFuture = capture.writeStreams(stdout, process.stderr);
    final interaction = _observeInteraction(interact(process, stdout));
    final outcome = await _waitForOutcome(
      process: process,
      interaction: interaction,
      capture: capture,
      stopwatch: stopwatch,
      config: config,
    );

    final exitCode = await _finishProcess(process, outcome);
    await captureFuture;
    stopwatch.stop();
    final output = await capture.readOutput();
    return _buildExecution(
      outcome: outcome,
      exitCode: exitCode,
      output: output,
      durationMs: stopwatch.elapsedMilliseconds,
      config: config,
    );
  }

  Future<Object> _waitForOutcome<T>({
    required Process process,
    required Future<_InteractionOutcome<T>> interaction,
    required _AcpOutputCapture capture,
    required Stopwatch stopwatch,
    required AgentConfig config,
  }) {
    final timeout = Completer<_AcpTimeout>();
    final timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timeout.isCompleted) return;
      if (stopwatch.elapsed.inSeconds >= config.hardTimeoutSeconds) {
        timeout.complete(
          _AcpTimeout(AgentExitReason.timeoutHard, config.hardTimeoutSeconds),
        );
        return;
      }
      final idleFor = DateTime.now().difference(capture.lastActivityAt);
      if (idleFor.inSeconds >= config.idleTimeoutSeconds) {
        timeout.complete(
          _AcpTimeout(AgentExitReason.timeoutIdle, config.idleTimeoutSeconds),
        );
      }
    });

    return Future.any<Object>([
      interaction,
      process.exitCode.then(_AcpProcessExit.new),
      timeout.future,
    ]).whenComplete(timer.cancel);
  }

  Future<int?> _finishProcess(Process process, Object outcome) async {
    if (outcome is _InteractionSuccess) {
      await process.stdin.close();
      try {
        return await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        return CLIRunner.killProcess(process);
      }
    }
    return CLIRunner.killProcess(process);
  }

  AcpProcessExecution<T> _buildExecution<T>({
    required Object outcome,
    required int? exitCode,
    required ({String stdout, String stderr}) output,
    required int durationMs,
    required AgentConfig config,
  }) {
    final failure = _failureFor(
      outcome,
      exitCode: exitCode,
      output: output,
      durationMs: durationMs,
      config: config,
    );
    final result = CLIResult(
      exitCode: exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
      durationMs: durationMs,
      failure: failure,
    );
    return switch (outcome) {
      _InteractionSuccess<T>(:final value) => AcpProcessExecution(
        value: value,
        result: result,
      ),
      _InteractionError<T>(:final error, :final stackTrace) =>
        AcpProcessExecution(
          error: error,
          stackTrace: stackTrace,
          result: result,
        ),
      _ => AcpProcessExecution(result: result),
    };
  }

  AgentFailure? _failureFor(
    Object outcome, {
    required int? exitCode,
    required ({String stdout, String stderr}) output,
    required int durationMs,
    required AgentConfig config,
  }) {
    if (outcome is _InteractionSuccess && exitCode == 0) return null;
    if (outcome is _AcpTimeout) {
      return AgentFailure(
        reason: outcome.reason,
        message: '${config.name} timed out after ${outcome.seconds}s.',
        exitCode: exitCode,
        timedOutAfter: outcome.seconds,
        stdoutSnippet: _snippet(output.stdout),
        stderrSnippet: _snippet(output.stderr),
        durationMs: durationMs,
        hadPartialOutput: _hasOutput(output),
      );
    }
    if (outcome is _AcpProcessExit) {
      return AgentFailure(
        reason: outcome.exitCode == 0
            ? AgentExitReason.emptyResponse
            : AgentExitReason.cliError,
        message:
            '${config.name} exited before completing the ACP prompt '
            '(code ${outcome.exitCode}).',
        exitCode: outcome.exitCode,
        stdoutSnippet: _snippet(output.stdout),
        stderrSnippet: _snippet(output.stderr),
        durationMs: durationMs,
        hadPartialOutput: _hasOutput(output),
      );
    }
    if (outcome is _InteractionError) {
      return AgentFailure(
        reason: AgentExitReason.cliError,
        message: 'ACP execution failed: ${outcome.error}',
        exitCode: exitCode,
        stdoutSnippet: _snippet(output.stdout),
        stderrSnippet: _snippet(output.stderr),
        durationMs: durationMs,
        hadPartialOutput: _hasOutput(output),
      );
    }
    return AgentFailure(
      reason: AgentExitReason.cliError,
      message: '${config.name} exited with code $exitCode.',
      exitCode: exitCode,
      durationMs: durationMs,
    );
  }

  AcpProcessExecution<T> _startFailure<T>(
    ProcessException error,
    StackTrace stackTrace,
    Stopwatch stopwatch,
  ) {
    stopwatch.stop();
    final failure = AgentFailure(
      reason: AgentExitReason.crash,
      message: 'Failed to start ACP agent: ${error.message}',
      durationMs: stopwatch.elapsedMilliseconds,
    );
    return AcpProcessExecution(
      error: error,
      stackTrace: stackTrace,
      result: CLIResult(
        exitCode: null,
        stdout: '',
        stderr: '',
        durationMs: stopwatch.elapsedMilliseconds,
        failure: failure,
      ),
    );
  }

  Future<_InteractionOutcome<T>> _observeInteraction<T>(
    Future<T> interaction,
  ) async {
    try {
      return _InteractionSuccess(await interaction);
    } catch (error, stackTrace) {
      return _InteractionError(error, stackTrace);
    }
  }

  bool _hasOutput(({String stdout, String stderr}) output) {
    return output.stdout.trim().isNotEmpty || output.stderr.trim().isNotEmpty;
  }

  String? _snippet(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.length <= 400 ? trimmed : '${trimmed.substring(0, 400)}...';
  }
}

sealed class _InteractionOutcome<T> {}

class _InteractionSuccess<T> extends _InteractionOutcome<T> {
  _InteractionSuccess(this.value);

  final T value;
}

class _InteractionError<T> extends _InteractionOutcome<T> {
  _InteractionError(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class _AcpProcessExit {
  const _AcpProcessExit(this.exitCode);

  final int exitCode;
}

class _AcpTimeout {
  const _AcpTimeout(this.reason, this.seconds);

  final AgentExitReason reason;
  final int seconds;
}

class _AcpOutputCapture {
  _AcpOutputCapture._({
    required this.stdoutBuffer,
    required this.stderrBuffer,
    this.directory,
    this.stdoutFile,
    this.stderrFile,
  }) : lastActivityAt = DateTime.now();

  final BytesBuilder stdoutBuffer;
  final BytesBuilder stderrBuffer;
  final Directory? directory;
  final File? stdoutFile;
  final File? stderrFile;
  DateTime lastActivityAt;

  String? get stdoutPath => stdoutFile?.path;
  String? get stderrPath => stderrFile?.path;

  static Future<_AcpOutputCapture> create({required bool retainFiles}) async {
    if (!retainFiles) {
      return _AcpOutputCapture._(
        stdoutBuffer: BytesBuilder(copy: false),
        stderrBuffer: BytesBuilder(copy: false),
      );
    }
    final directory = await Directory.systemTemp.createTemp('cag_acp_');
    return _AcpOutputCapture._(
      stdoutBuffer: BytesBuilder(copy: false),
      stderrBuffer: BytesBuilder(copy: false),
      directory: directory,
      stdoutFile: File('${directory.path}/stdout'),
      stderrFile: File('${directory.path}/stderr'),
    );
  }

  Future<void> writeStreams(
    Stream<List<int>> stdout,
    Stream<List<int>> stderr,
  ) async {
    final stdoutSink = stdoutFile?.openWrite();
    final stderrSink = stderrFile?.openWrite();
    try {
      await Future.wait([
        _capture(stdout, stdoutBuffer, stdoutSink),
        _capture(stderr, stderrBuffer, stderrSink),
      ]);
    } finally {
      await Future.wait([
        if (stdoutSink != null) stdoutSink.close(),
        if (stderrSink != null) stderrSink.close(),
      ]);
    }
  }

  Future<void> _capture(
    Stream<List<int>> stream,
    BytesBuilder buffer,
    IOSink? sink,
  ) async {
    await for (final chunk in stream) {
      buffer.add(chunk);
      sink?.add(chunk);
      lastActivityAt = DateTime.now();
    }
  }

  Future<({String stdout, String stderr})> readOutput() async {
    final stdout = stdoutFile == null
        ? stdoutBuffer.takeBytes()
        : await stdoutFile!.readAsBytes();
    final stderr = stderrFile == null
        ? stderrBuffer.takeBytes()
        : await stderrFile!.readAsBytes();
    return (
      stdout: utf8.decode(stdout, allowMalformed: true),
      stderr: utf8.decode(stderr, allowMalformed: true),
    );
  }

  Future<void> delete() async {
    final target = directory;
    if (target != null && await target.exists()) {
      await target.delete(recursive: true);
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';

/// Result of running a CLI command.
typedef CLIResult = AgentExecutionResult;

/// Runs external CLI commands.
class CLIRunner {
  /// Execute a CLI command and return the result.
  Future<CLIResult> run({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? hardTimeout,
    Duration? idleTimeout,
    String? workingDirectory,
  }) async {
    final resolvedExecutable = _resolveExecutable(executable);
    try {
      return await _runProcess(
        executable: resolvedExecutable,
        args: args,
        env: env,
        hardTimeout: hardTimeout,
        idleTimeout: idleTimeout,
        workingDirectory: workingDirectory,
      );
    } on ProcessException catch (error) {
      return CLIResult(
        exitCode: null,
        stdout: '',
        stderr: '',
        durationMs: 0,
        failure: AgentFailure(
          reason: AgentExitReason.crash,
          message: _friendlyProcessExceptionMessage(
            error,
            executable,
            resolvedExecutable,
          ),
        ),
      );
    }
  }

  Future<CLIResult> _runProcess({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? hardTimeout,
    Duration? idleTimeout,
    String? workingDirectory,
  }) async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      executable,
      args,
      environment: env != null ? {...Platform.environment, ...env} : null,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    await process.stdin.close();

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();
    var lastActivityAt = DateTime.now();

    final stdoutSub = _listen(
      stream: process.stdout,
      buffer: stdoutBuffer,
      done: stdoutDone,
      onActivity: () => lastActivityAt = DateTime.now(),
    );
    final stderrSub = _listen(
      stream: process.stderr,
      buffer: stderrBuffer,
      done: stderrDone,
      onActivity: () => lastActivityAt = DateTime.now(),
    );

    final timeoutReason = Completer<AgentExitReason>();
    final monitor = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timeoutReason.isCompleted) {
        return;
      }
      if (hardTimeout != null && stopwatch.elapsed >= hardTimeout) {
        timeoutReason.complete(AgentExitReason.timeoutHard);
        return;
      }
      if (idleTimeout == null) {
        return;
      }
      if (DateTime.now().difference(lastActivityAt) >= idleTimeout) {
        timeoutReason.complete(AgentExitReason.timeoutIdle);
      }
    });

    final outcome = await Future.any<Object>([
      process.exitCode,
      timeoutReason.future,
    ]);
    monitor.cancel();

    final exitCode = outcome is int
        ? outcome
        : await _killAndCollectExitCode(process);
    await Future.wait([stdoutDone.future, stderrDone.future]);
    await stdoutSub.cancel();
    await stderrSub.cancel();
    stopwatch.stop();

    final stdout = stdoutBuffer.toString();
    final stderr = stderrBuffer.toString();
    if (outcome is AgentExitReason) {
      return CLIResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        durationMs: stopwatch.elapsedMilliseconds,
        failure: _buildTimeoutFailure(
          reason: outcome,
          hardTimeout: hardTimeout,
          idleTimeout: idleTimeout,
          stdout: stdout,
          stderr: stderr,
          durationMs: stopwatch.elapsedMilliseconds,
          exitCode: exitCode,
        ),
      );
    }

    if (exitCode == 0) {
      return CLIResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    return CLIResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
      durationMs: stopwatch.elapsedMilliseconds,
      failure: AgentFailure(
        reason: AgentExitReason.cliError,
        message: 'Process exited with code $exitCode.',
        exitCode: exitCode,
        stdoutSnippet: _snippet(stdout),
        stderrSnippet: _snippet(stderr),
        durationMs: stopwatch.elapsedMilliseconds,
        hadPartialOutput: _hasPartialOutput(stdout, stderr),
      ),
    );
  }

  StreamSubscription<String> _listen({
    required Stream<List<int>> stream,
    required StringBuffer buffer,
    required Completer<void> done,
    required void Function() onActivity,
  }) {
    return stream.transform(utf8.decoder).listen(
      (chunk) {
        if (chunk.isEmpty) {
          return;
        }
        buffer.write(chunk);
        onActivity();
      },
      onDone: done.complete,
    );
  }

  Future<int?> _killAndCollectExitCode(Process process) async {
    process.kill();
    final exited = await Future.any<bool>([
      process.exitCode.then((_) => true),
      Future<bool>.delayed(const Duration(seconds: 2), () => false),
    ]);
    if (!exited) {
      process.kill(ProcessSignal.sigkill);
    }
    return process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () => -1,
    ).then((code) => code == -1 ? null : code);
  }

  AgentFailure _buildTimeoutFailure({
    required AgentExitReason reason,
    required Duration? hardTimeout,
    required Duration? idleTimeout,
    required String stdout,
    required String stderr,
    required int durationMs,
    required int? exitCode,
  }) {
    final timeout = reason == AgentExitReason.timeoutHard
        ? hardTimeout?.inSeconds
        : idleTimeout?.inSeconds;
    final message = reason == AgentExitReason.timeoutHard
        ? 'Process exceeded hard timeout of ${timeout ?? 0}s.'
        : 'Process produced no output for ${timeout ?? 0}s.';
    return AgentFailure(
      reason: reason,
      message: message,
      exitCode: exitCode,
      timedOutAfter: timeout,
      stdoutSnippet: _snippet(stdout),
      stderrSnippet: _snippet(stderr),
      durationMs: durationMs,
      hadPartialOutput: _hasPartialOutput(stdout, stderr),
    );
  }

  bool _hasPartialOutput(String stdout, String stderr) {
    return stdout.trim().isNotEmpty || stderr.trim().isNotEmpty;
  }

  String? _snippet(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.length <= 400) {
      return trimmed;
    }
    return '${trimmed.substring(0, 400)}...';
  }

  String _friendlyProcessExceptionMessage(
    ProcessException error,
    String originalExecutable,
    String resolvedExecutable,
  ) {
    final details = error.message.isNotEmpty ? ': ${error.message}' : '';
    final buffer = StringBuffer(
      'Failed to start "$resolvedExecutable"$details',
    );
    if (Platform.isWindows) {
      buffer.write(
        '\nWindows hint: ensure "$originalExecutable" is installed and on PATH, '
        'or set agents.<name>.executable in %APPDATA%\\cag\\config.json '
        'to a full .exe/.cmd path (npm shims usually end with .cmd).',
      );
    }
    return buffer.toString();
  }

  String _resolveExecutable(String executable) {
    if (!Platform.isWindows) return executable;

    final hasPath = executable.contains(r'\') || executable.contains('/');
    final hasExtension = _hasExtension(executable);
    if (hasPath && File(executable).existsSync()) return executable;

    final extensions = _windowsExtensions();
    if (hasPath) {
      for (final extension in extensions) {
        final candidate = hasExtension ? executable : '$executable$extension';
        if (File(candidate).existsSync()) return candidate;
      }
      return executable;
    }

    final path = Platform.environment['PATH'];
    if (path == null || path.isEmpty) return executable;

    for (final dir in path.split(';')) {
      if (dir.isEmpty) continue;
      if (hasExtension) {
        final candidate = '$dir\\$executable';
        if (File(candidate).existsSync()) return candidate;
        continue;
      }
      for (final extension in extensions) {
        final candidate = '$dir\\$executable$extension';
        if (File(candidate).existsSync()) return candidate;
      }
    }

    return executable;
  }

  bool _hasExtension(String path) {
    final lastSlash = path.lastIndexOf('/');
    final lastBackslash = path.lastIndexOf(r'\');
    final lastSeparator = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    final lastDot = path.lastIndexOf('.');
    return lastDot > lastSeparator;
  }

  List<String> _windowsExtensions() {
    final pathext = Platform.environment['PATHEXT'];
    if (pathext == null || pathext.trim().isEmpty) {
      return const ['.exe', '.cmd', '.bat'];
    }
    return pathext
        .split(';')
        .where((entry) => entry.trim().isNotEmpty)
        .map((entry) => entry.trim().toLowerCase())
        .toList();
  }
}

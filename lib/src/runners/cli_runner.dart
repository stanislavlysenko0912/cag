import 'dart:async';
import 'dart:io';

import '../models/models.dart';

/// Result of running a CLI command.
typedef CLIResult = AgentExecutionResult;

/// Callback invoked after a process starts.
typedef ProcessStarted = void Function(RunningProcess process);

/// Handle for a running CLI process.
class RunningProcess {
  RunningProcess(this._process);

  final Process _process;

  /// Process identifier.
  int get pid => _process.pid;

  /// Stops the process, escalating after a short grace period.
  Future<int?> kill() => CLIRunner.killProcess(_process);
}

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
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
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
        onProcessStarted: onProcessStarted,
        keepCapture: keepCapture,
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

  /// Execute a command prefix through a platform-aware shell.
  Future<CLIResult> runShellCommand({
    required String commandPrefix,
    required List<String> args,
    String? shellExecutable,
    List<String> shellArgs = const [],
    Map<String, String>? env,
    Duration? hardTimeout,
    Duration? idleTimeout,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) {
    final shell = _ShellCommand.forExecutable(shellExecutable);
    final resolvedShellArgs = shellArgs.isNotEmpty ? shellArgs : shell.args;
    final command = shell.buildCommand(commandPrefix, args);

    return run(
      executable: shell.executable,
      args: [...resolvedShellArgs, command],
      env: env,
      hardTimeout: hardTimeout,
      idleTimeout: idleTimeout,
      workingDirectory: workingDirectory,
      onProcessStarted: onProcessStarted,
      keepCapture: keepCapture,
    );
  }

  Future<CLIResult> _runProcess({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? hardTimeout,
    Duration? idleTimeout,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    bool keepCapture = false,
  }) async {
    final capture = await _CaptureDirectory.create();
    var deleteCapture = true;
    try {
      final result = await _runProcessWithCapture(
        executable: executable,
        args: args,
        env: env,
        hardTimeout: hardTimeout,
        idleTimeout: idleTimeout,
        workingDirectory: workingDirectory,
        onProcessStarted: onProcessStarted,
        capture: capture,
      );
      if (keepCapture) {
        deleteCapture = false;
        return result.copyWith(
          stdoutPath: capture.stdoutFile.path,
          stderrPath: capture.stderrFile.path,
        );
      }
      return result;
    } finally {
      if (deleteCapture) {
        await capture.delete();
      }
    }
  }

  Future<CLIResult> _runProcessWithCapture({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? hardTimeout,
    Duration? idleTimeout,
    String? workingDirectory,
    ProcessStarted? onProcessStarted,
    required _CaptureDirectory capture,
  }) async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      executable,
      args,
      environment: env != null ? {...Platform.environment, ...env} : null,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    onProcessStarted?.call(RunningProcess(process));
    final outputCapture = capture.writeProcessOutput(process);
    await process.stdin.close();

    final activity = _OutputActivityTracker(capture: capture);
    final timeoutReason = Completer<AgentExitReason>();
    final monitor = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timeoutReason.isCompleted) {
        return;
      }
      activity.recordChanges();
      if (hardTimeout != null && stopwatch.elapsed >= hardTimeout) {
        timeoutReason.complete(AgentExitReason.timeoutHard);
        return;
      }
      if (idleTimeout != null &&
          DateTime.now().difference(activity.lastActivityAt) >= idleTimeout) {
        timeoutReason.complete(AgentExitReason.timeoutIdle);
      }
    });

    final outcome = await Future.any<Object>([
      process.exitCode,
      timeoutReason.future,
    ]);
    monitor.cancel();

    final exitCode = outcome is int ? outcome : await killProcess(process);
    await outputCapture;
    final output = await capture.readOutput();
    stopwatch.stop();

    if (outcome is AgentExitReason) {
      return CLIResult(
        exitCode: exitCode,
        stdout: output.stdout,
        stderr: output.stderr,
        durationMs: stopwatch.elapsedMilliseconds,
        failure: _buildTimeoutFailure(
          reason: outcome,
          hardTimeout: hardTimeout,
          idleTimeout: idleTimeout,
          stdout: output.stdout,
          stderr: output.stderr,
          durationMs: stopwatch.elapsedMilliseconds,
          exitCode: exitCode,
        ),
      );
    }

    if (exitCode == 0) {
      return CLIResult(
        exitCode: exitCode,
        stdout: output.stdout,
        stderr: output.stderr,
        durationMs: stopwatch.elapsedMilliseconds,
      );
    }

    return CLIResult(
      exitCode: exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
      durationMs: stopwatch.elapsedMilliseconds,
      failure: AgentFailure(
        reason: AgentExitReason.cliError,
        message: 'Process exited with code $exitCode.',
        exitCode: exitCode,
        stdoutSnippet: _snippet(output.stdout),
        stderrSnippet: _snippet(output.stderr),
        durationMs: stopwatch.elapsedMilliseconds,
        hadPartialOutput: _hasPartialOutput(output.stdout, output.stderr),
      ),
    );
  }

  /// Stops a process, escalating to SIGKILL after a short grace period.
  static Future<int?> killProcess(Process process) async {
    process.kill();
    final exited = await Future.any<bool>([
      process.exitCode.then((_) => true),
      Future<bool>.delayed(const Duration(seconds: 2), () => false),
    ]);
    if (!exited) {
      process.kill(ProcessSignal.sigkill);
    }
    return process.exitCode
        .timeout(const Duration(seconds: 2), onTimeout: () => -1)
        .then((code) => code == -1 ? null : code);
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

class _ShellCommand {
  _ShellCommand({
    required this.executable,
    required this.args,
    required this.dialect,
  });

  final String executable;
  final List<String> args;
  final _ShellDialect dialect;

  static _ShellCommand forExecutable(String? shellExecutable) {
    final executable = shellExecutable ?? _defaultExecutable();
    return _ShellCommand(
      executable: executable,
      args: _defaultArgs(executable),
      dialect: _ShellDialect.forExecutable(executable),
    );
  }

  String buildCommand(String prefix, List<String> args) {
    final escapedArgs = args.map(dialect.quote).join(' ');
    final trimmedPrefix = prefix.trim();
    if (escapedArgs.isEmpty) return trimmedPrefix;
    return '$trimmedPrefix $escapedArgs';
  }

  static String _defaultExecutable() {
    if (Platform.isWindows) return 'cmd';
    return '/bin/sh';
  }

  static List<String> _defaultArgs(String executable) {
    final dialect = _ShellDialect.forExecutable(executable);
    return switch (dialect) {
      _ShellDialect.windowsCommand => const ['/c'],
      _ShellDialect.posix => const ['-c'],
    };
  }
}

enum _ShellDialect {
  posix,
  windowsCommand;

  static _ShellDialect forExecutable(String executable) {
    final lower = executable.toLowerCase();
    if (lower.contains('cmd')) return windowsCommand;
    return posix;
  }

  String quote(String value) {
    return switch (this) {
      posix => "'${value.replaceAll("'", "'\\''")}'",
      windowsCommand => '"${value.replaceAll('"', '\\"')}"',
    };
  }
}

class _CaptureDirectory {
  _CaptureDirectory({
    required this.directory,
    required this.stdoutFile,
    required this.stderrFile,
  });

  final Directory directory;
  final File stdoutFile;
  final File stderrFile;

  static Future<_CaptureDirectory> create() async {
    final directory = await Directory.systemTemp.createTemp('cag_cli_');
    return _CaptureDirectory(
      directory: directory,
      stdoutFile: File('${directory.path}/stdout'),
      stderrFile: File('${directory.path}/stderr'),
    );
  }

  Future<({String stdout, String stderr})> readOutput() async {
    final stdout = await _readIfExists(stdoutFile);
    final stderr = await _readIfExists(stderrFile);
    return (stdout: stdout, stderr: stderr);
  }

  Future<void> writeProcessOutput(Process process) async {
    final stdoutSink = stdoutFile.openWrite();
    final stderrSink = stderrFile.openWrite();
    try {
      await Future.wait([
        stdoutSink.addStream(process.stdout),
        stderrSink.addStream(process.stderr),
      ]);
    } finally {
      await Future.wait([stdoutSink.close(), stderrSink.close()]);
    }
  }

  Future<String> _readIfExists(File file) async {
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  Future<void> delete() async {
    try {
      if (await stdoutFile.exists()) {
        await stdoutFile.delete();
      }
      if (await stderrFile.exists()) {
        await stderrFile.delete();
      }
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Best-effort cleanup; temp dir is removed by the OS eventually.
    }
  }
}

class _OutputActivityTracker {
  _OutputActivityTracker({required _CaptureDirectory capture})
    : _capture = capture,
      lastActivityAt = DateTime.now();

  final _CaptureDirectory _capture;
  DateTime lastActivityAt;
  var _stdoutSize = 0;
  var _stderrSize = 0;

  void recordChanges() {
    final stdoutSize = _fileSize(_capture.stdoutFile);
    final stderrSize = _fileSize(_capture.stderrFile);
    if (stdoutSize > _stdoutSize || stderrSize > _stderrSize) {
      _stdoutSize = stdoutSize;
      _stderrSize = stderrSize;
      lastActivityAt = DateTime.now();
    }
  }

  int _fileSize(File file) {
    if (!file.existsSync()) {
      return 0;
    }
    return file.lengthSync();
  }
}

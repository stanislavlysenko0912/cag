import 'dart:async';
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
    final capture = await _CaptureDirectory.create();
    try {
      return await _runProcessWithCapture(
        executable: executable,
        args: args,
        env: env,
        hardTimeout: hardTimeout,
        idleTimeout: idleTimeout,
        workingDirectory: workingDirectory,
        capture: capture,
      );
    } finally {
      await capture.delete();
    }
  }

  Future<CLIResult> _runProcessWithCapture({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? hardTimeout,
    Duration? idleTimeout,
    String? workingDirectory,
    required _CaptureDirectory capture,
  }) async {
    final stopwatch = Stopwatch()..start();
    final shell = _redirectShellCommand(
      executable: executable,
      args: args,
      stdoutPath: capture.stdoutFile.path,
      stderrPath: capture.stderrFile.path,
    );

    final process = await Process.start(
      shell.executable,
      shell.args,
      environment: env != null ? {...Platform.environment, ...env} : null,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
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

    final exitCode = outcome is int
        ? outcome
        : await _killAndCollectExitCode(process);
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

  ({String executable, List<String> args}) _redirectShellCommand({
    required String executable,
    required List<String> args,
    required String stdoutPath,
    required String stderrPath,
  }) {
    if (Platform.isWindows) {
      final command = [
        _cmdQuote(executable),
        ...args.map(_cmdQuote),
        '>',
        _cmdQuote(stdoutPath),
        '2>',
        _cmdQuote(stderrPath),
      ].join(' ');
      return (executable: 'cmd.exe', args: ['/c', command]);
    }

    final command = [
      _posixShellQuote(executable),
      ...args.map(_posixShellQuote),
      '>',
      _posixShellQuote(stdoutPath),
      '2>',
      _posixShellQuote(stderrPath),
    ].join(' ');
    return (executable: '/bin/sh', args: ['-c', command]);
  }

  String _posixShellQuote(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  String _cmdQuote(String value) {
    if (value.contains(' ') || value.contains('"')) {
      return '"${value.replaceAll('"', r'\"')}"';
    }
    return value;
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

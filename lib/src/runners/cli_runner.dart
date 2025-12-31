import 'dart:io';

/// Result of running a CLI command.
class CLIResult {
  CLIResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get success => exitCode == 0;
}

/// Exception thrown when CLI execution fails.
class CLIRunnerException implements Exception {
  CLIRunnerException(this.message, {this.exitCode, this.stderr});

  final String message;
  final int? exitCode;
  final String? stderr;

  @override
  String toString() {
    final buffer = StringBuffer('CLIRunnerException: $message');
    if (exitCode != null) buffer.write(' (exit code: $exitCode)');
    if (stderr != null && stderr!.isNotEmpty) {
      buffer.write('\nstderr: $stderr');
    }
    return buffer.toString();
  }
}

/// Runs external CLI commands.
class CLIRunner {
  /// Execute a CLI command and return the result.
  Future<CLIResult> run({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? timeout,
    String? workingDirectory,
  }) async {
    final resolvedExecutable = _resolveExecutable(executable);
    final result = await _runProcess(
      executable: resolvedExecutable,
      args: args,
      env: env,
      timeout: timeout,
      workingDirectory: workingDirectory,
      originalExecutable: executable,
    );

    return CLIResult(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }

  Future<ProcessResult> _runProcess({
    required String executable,
    required List<String> args,
    Map<String, String>? env,
    Duration? timeout,
    String? workingDirectory,
    required String originalExecutable,
  }) async {
    try {
      return await Process.run(
        executable,
        args,
        environment: env != null ? {...Platform.environment, ...env} : null,
        workingDirectory: workingDirectory,
        runInShell: false,
      ).timeout(
        timeout ?? const Duration(minutes: 30),
        onTimeout: () => throw CLIRunnerException(
          'Process timed out after ${timeout?.inSeconds ?? 1800}s',
        ),
      );
    } on ProcessException catch (error) {
      throw CLIRunnerException(
        _friendlyProcessExceptionMessage(
          error,
          originalExecutable,
          executable,
        ),
      );
    }
  }

  String _friendlyProcessExceptionMessage(
    ProcessException error,
    String originalExecutable,
    String resolvedExecutable,
  ) {
    final details = error.message.isNotEmpty ? ': ${error.message}' : '';
    final buffer = StringBuffer('Failed to start "$resolvedExecutable"$details');
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

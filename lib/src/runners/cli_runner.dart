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
    final result =
        await Process.run(
          executable,
          args,
          environment: env,
          workingDirectory: workingDirectory,
          runInShell: false,
        ).timeout(
          timeout ?? const Duration(minutes: 30),
          onTimeout: () => throw CLIRunnerException(
            'Process timed out after ${timeout?.inSeconds ?? 1800}s',
          ),
        );

    return CLIResult(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }
}

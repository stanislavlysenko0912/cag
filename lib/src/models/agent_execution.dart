/// Normalized reason why an agent run finished.
enum AgentExitReason {
  success('success'),
  timeoutHard('timeout_hard'),
  timeoutIdle('timeout_idle'),
  parseError('parse_error'),
  emptyResponse('empty_response'),
  crash('crash'),
  cliError('cli_error'),
  killed('killed');

  const AgentExitReason(this.value);

  /// Stable serialized value.
  final String value;

  /// Parses a serialized reason.
  static AgentExitReason fromValue(String value) {
    return AgentExitReason.values.firstWhere(
      (reason) => reason.value == value,
      orElse: () => AgentExitReason.crash,
    );
  }
}

/// Structured failure details for an agent run.
class AgentFailure {
  AgentFailure({
    required this.reason,
    required this.message,
    this.exitCode,
    this.timedOutAfter,
    this.stdoutSnippet,
    this.stderrSnippet,
    this.durationMs,
    this.hadPartialOutput = false,
  });

  /// Failure category.
  final AgentExitReason reason;

  /// Human-readable diagnostic message.
  final String message;

  /// Process exit code when available.
  final int? exitCode;

  /// Timeout threshold that triggered the failure.
  final int? timedOutAfter;

  /// Truncated stdout for troubleshooting.
  final String? stdoutSnippet;

  /// Truncated stderr for troubleshooting.
  final String? stderrSnippet;

  /// End-to-end execution duration.
  final int? durationMs;

  /// Whether stdout/stderr contained any partial output.
  final bool hadPartialOutput;

  /// Short label for CLI output.
  String get summary => reason.value;

  /// Serialized failure payload.
  Map<String, dynamic> toJson() => {
    'reason': reason.value,
    'message': message,
    if (exitCode != null) 'exit_code': exitCode,
    if (timedOutAfter != null) 'timed_out_after': timedOutAfter,
    if (stdoutSnippet != null) 'stdout_snippet': stdoutSnippet,
    if (stderrSnippet != null) 'stderr_snippet': stderrSnippet,
    if (durationMs != null) 'duration_ms': durationMs,
    'had_partial_output': hadPartialOutput,
  };

  /// Builds a failure from JSON.
  factory AgentFailure.fromJson(Map<String, dynamic> json) {
    return AgentFailure(
      reason: AgentExitReason.fromValue(json['reason'] as String),
      message: json['message'] as String,
      exitCode: json['exit_code'] as int?,
      timedOutAfter: json['timed_out_after'] as int?,
      stdoutSnippet: json['stdout_snippet'] as String?,
      stderrSnippet: json['stderr_snippet'] as String?,
      durationMs: json['duration_ms'] as int?,
      hadPartialOutput: json['had_partial_output'] as bool? ?? false,
    );
  }

  @override
  String toString() => '$summary: $message';
}

/// Raw execution output for a CLI process.
class AgentExecutionResult {
  AgentExecutionResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
    this.failure,
    this.stdoutPath,
    this.stderrPath,
  });

  /// Process exit code when available.
  final int? exitCode;

  /// Full collected stdout.
  final String stdout;

  /// Full collected stderr.
  final String stderr;

  /// End-to-end execution duration.
  final int durationMs;

  /// Structured failure when execution did not complete cleanly.
  final AgentFailure? failure;

  /// Path to retained stdout capture, when available.
  final String? stdoutPath;

  /// Path to retained stderr capture, when available.
  final String? stderrPath;

  /// Whether the process finished cleanly.
  bool get success => failure == null && exitCode == 0;

  /// Returns a copy with selected fields replaced.
  AgentExecutionResult copyWith({
    int? exitCode,
    String? stdout,
    String? stderr,
    int? durationMs,
    AgentFailure? failure,
    String? stdoutPath,
    String? stderrPath,
  }) {
    return AgentExecutionResult(
      exitCode: exitCode ?? this.exitCode,
      stdout: stdout ?? this.stdout,
      stderr: stderr ?? this.stderr,
      durationMs: durationMs ?? this.durationMs,
      failure: failure ?? this.failure,
      stdoutPath: stdoutPath ?? this.stdoutPath,
      stderrPath: stderrPath ?? this.stderrPath,
    );
  }
}

/// Exception thrown when agent execution fails.
class AgentExecutionException implements Exception {
  AgentExecutionException(this.failure, {this.result});

  /// Structured failure payload.
  final AgentFailure failure;

  /// Raw execution result when the process started.
  final AgentExecutionResult? result;

  @override
  String toString() => 'AgentExecutionException: ${failure.toString()}';
}

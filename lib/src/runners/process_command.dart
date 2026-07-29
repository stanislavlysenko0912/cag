import 'dart:io';

import '../models/agent_config.dart';

/// Executable and arguments resolved from an agent configuration.
class ProcessCommand {
  const ProcessCommand({required this.executable, required this.args});

  final String executable;
  final List<String> args;

  /// Builds the direct or shell-prefixed process command for [config].
  factory ProcessCommand.forAgent(AgentConfig config, List<String> args) {
    final prefix = config.shellCommandPrefix;
    if (prefix == null) {
      return ProcessCommand(executable: config.executable, args: args);
    }

    final shellExecutable =
        config.shellExecutable ?? (Platform.isWindows ? 'cmd' : '/bin/sh');
    final shellArgs = config.shellArgs.isNotEmpty
        ? config.shellArgs
        : _defaultShellArgs(shellExecutable);
    final escapedArgs = args
        .map((argument) => _shellEscape(argument, shellExecutable))
        .join(' ');
    final trimmedPrefix = prefix.trim();
    final command = escapedArgs.isEmpty
        ? trimmedPrefix
        : '$trimmedPrefix $escapedArgs';

    return ProcessCommand(
      executable: shellExecutable,
      args: [...shellArgs, command],
    );
  }

  static List<String> _defaultShellArgs(String executable) {
    return executable.toLowerCase().contains('cmd') ? ['/c'] : ['-c'];
  }

  static String _shellEscape(String value, String executable) {
    if (executable.toLowerCase().contains('cmd')) {
      return '"${value.replaceAll('"', '\\"')}"';
    }
    return "'${value.replaceAll("'", "'\\''")}'";
  }
}

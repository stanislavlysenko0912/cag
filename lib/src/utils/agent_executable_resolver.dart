import 'dart:io';

import '../config/agent_config_override.dart';
import '../models/agent_config.dart';

String resolveAgentExecutable(AgentConfig base, AgentConfigOverride? override) {
  final shellPrefix = override?.shellCommandPrefix ?? base.shellCommandPrefix;
  if (shellPrefix != null && shellPrefix.trim().isNotEmpty) {
    return override?.shellExecutable ??
        base.shellExecutable ??
        defaultShellExecutable();
  }
  return override?.executable ?? base.executable;
}

String defaultShellExecutable() {
  return Platform.isWindows ? 'cmd' : '/bin/sh';
}

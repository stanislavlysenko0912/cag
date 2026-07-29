import '../models/agent_config.dart';
import 'acp_agent.dart';
import 'agent_id.dart';

/// Runs OpenCode through its built-in ACP stdio server.
class OpenCodeAgent extends AcpAgent {
  OpenCodeAgent({AgentConfig? config}) : super(config: config ?? defaultConfig);

  static final defaultConfig = AgentConfig(
    name: AgentId.opencode,
    executable: 'opencode',
    parser: 'acp',
    additionalArgs: const ['acp'],
  );
}

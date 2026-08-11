import '../models/models.dart';
import 'acp_agent.dart';
import 'agent_id.dart';

/// Runs Cursor Agent through its ACP stdio server.
///
/// Model slugs are discovered from the ACP session and enriched with curated
/// metadata from [AgentModelRegistry.cursorModels].
class CursorAgent extends AcpAgent {
  CursorAgent({AgentConfig? config}) : super(config: config ?? defaultConfig);

  static final defaultConfig = AgentConfig(
    name: AgentId.cursor,
    executable: 'cursor-agent',
    parser: 'acp',
    defaultModel:
        AgentModelRegistry.defaultModelName(AgentId.cursor) ??
        'composer-2.5-fast',
    additionalArgs: ['acp'],
    hardTimeoutSeconds: 1800,
    idleTimeoutSeconds: 900,
  );
}

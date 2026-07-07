import 'package:cag/src/doctor/doctor.dart';
import 'package:nocterm/nocterm.dart';

import 'controls.dart';

/// Read-only content describing the current doctor report.
class StatusView extends StatelessComponent {
  const StatusView({super.key, required this.loading, required this.report});

  final bool loading;
  final DoctorReport? report;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    if (loading) {
      return Text('Loading status…', style: TextStyle(color: theme.outline));
    }

    final report = this.report;
    if (report == null) {
      return Text('No status loaded.', style: TextStyle(color: theme.outline));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summary(theme, report.summary),
        const SizedBox(height: 1),
        Text(
          'Config: ${report.config.status}',
          style: TextStyle(color: theme.onBackground),
        ),
        Text(
          report.config.path,
          style: TextStyle(color: theme.outline, fontWeight: FontWeight.dim),
        ),
        const SizedBox(height: 1),
        for (final agent in report.agents) _agentLine(theme, agent),
      ],
    );
  }

  Component _summary(TuiThemeData theme, DoctorSummary summary) {
    return Row(
      children: [
        Text('${summary.ok} ok', style: TextStyle(color: theme.success)),
        const SizedBox(width: 2),
        Text('${summary.warn} warn', style: TextStyle(color: theme.warning)),
        const SizedBox(width: 2),
        Text('${summary.fail} fail', style: TextStyle(color: theme.error)),
      ],
    );
  }

  Component _agentLine(TuiThemeData theme, AgentDiagnostic agent) {
    return Row(
      children: [
        StatusDot(enabled: agent.enabled),
        const SizedBox(width: 1),
        SizedBox(
          width: 20,
          child: Text(agent.name, style: TextStyle(color: theme.onBackground)),
        ),
        Text(
          agent.status,
          style: TextStyle(color: statusColor(theme, agent.status)),
        ),
      ],
    );
  }
}

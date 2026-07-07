import 'package:cag/src/detect/detect.dart';
import 'package:nocterm/nocterm.dart';

import 'controls.dart';

/// Read-only preview of detection: what is installed and what applying would
/// change. Applying is a separate, explicit action owned by the shell.
class DetectView extends StatelessComponent {
  const DetectView({super.key, required this.preview});

  final DetectPreview preview;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final row in preview.rows) _row(theme, row)],
    );
  }

  Component _row(TuiThemeData theme, DetectRow row) {
    return Row(
      children: [
        StatusDot(enabled: row.available),
        const SizedBox(width: 1),
        SizedBox(
          width: 20,
          child: Text(
            row.displayName,
            style: TextStyle(color: theme.onBackground),
          ),
        ),
        SizedBox(
          width: 10,
          child: Text(
            row.available ? 'found' : 'missing',
            style: TextStyle(
              color: row.available ? theme.success : theme.error,
            ),
          ),
        ),
        Expanded(child: _change(theme, row)),
      ],
    );
  }

  Component _change(TuiThemeData theme, DetectRow row) {
    if (!row.willChange) {
      return SizedBox();
    }
    return Text(
      row.available ? '→ will enable' : '→ will disable',
      style: TextStyle(color: theme.warning),
    );
  }
}

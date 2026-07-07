import 'package:nocterm/nocterm.dart';

import 'shell.dart';

/// Starts the interactive terminal UI for CAG.
Future<void> runCagTui({required List<String> commandArgs}) {
  return runApp(_CagTuiApp(commandArgs: commandArgs));
}

class _CagTuiApp extends StatelessComponent {
  const _CagTuiApp({required this.commandArgs});

  final List<String> commandArgs;

  @override
  Component build(BuildContext context) {
    return TuiTheme(
      data: TuiThemeData.dark,
      child: CagTuiShell(commandArgs: commandArgs),
    );
  }
}

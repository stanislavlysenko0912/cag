enum TuiScreen { menu, status, detect, models }

class TuiMenuItem {
  const TuiMenuItem({
    required this.title,
    required this.description,
    required this.screen,
  });

  final String title;
  final String description;
  final TuiScreen screen;
}

const tuiMenuItems = [
  TuiMenuItem(
    title: 'Status',
    description: 'Inspect agents, config, and auth',
    screen: TuiScreen.status,
  ),
  TuiMenuItem(
    title: 'Detect',
    description: 'Scan the system for installed agent CLIs',
    screen: TuiScreen.detect,
  ),
  TuiMenuItem(
    title: 'Models',
    description: 'Enable agents and toggle their models',
    screen: TuiScreen.models,
  ),
];

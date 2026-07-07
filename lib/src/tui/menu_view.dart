import 'package:nocterm/nocterm.dart';

/// Inner content for a main-menu row: a title with a dim description.
class MenuRowContent extends StatelessComponent {
  const MenuRowContent({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
  });

  final String title;
  final String description;
  final bool selected;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: selected ? theme.primary : theme.onBackground,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            description,
            style: TextStyle(color: theme.outline, fontWeight: FontWeight.dim),
          ),
        ),
      ],
    );
  }
}

/// Inner content for a navigational action row such as "Back" or "Add".
class ActionRowContent extends StatelessComponent {
  const ActionRowContent({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
  });

  final String icon;
  final String label;
  final bool selected;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Text(
      '$icon  $label',
      style: TextStyle(
        color: selected ? theme.primary : theme.secondary,
        fontWeight: selected ? FontWeight.bold : null,
      ),
    );
  }
}

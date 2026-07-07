import 'package:nocterm/nocterm.dart';

/// A single hint shown in the [HintBar]: a key and the action it performs.
typedef Hint = (String key, String action);

/// A framed panel with a titled, rounded border.
///
/// Groups related content and communicates the current location through its
/// [title], removing the need for separate breadcrumbs.
class Panel extends StatelessComponent {
  const Panel({super.key, required this.title, required this.child});

  final String title;
  final Component child;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 1, right: 1, top: 1),
      decoration: BoxDecoration(
        border: BoxBorder.all(
          color: theme.outlineVariant,
          style: BoxBorderStyle.rounded,
        ),
        title: BorderTitle(
          text: title,
          style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold),
        ),
      ),
      child: child,
    );
  }
}

/// A selectable list row that carries the selection chrome shared by every
/// screen: a leading accent bar, a subtle highlight, and mouse support.
///
/// Behaviour (open, toggle, go back) is supplied by the caller so a single row
/// widget stays consistent across the whole UI.
class NavRow extends StatelessComponent {
  const NavRow({
    super.key,
    required this.selected,
    required this.onTap,
    required this.onHover,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final Component child;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(color: selected ? theme.surface : null),
          child: Row(
            children: [
              Text(
                selected ? '▌' : ' ',
                style: TextStyle(
                  color: theme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 1),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A colored status indicator whose fill and color convey an on/off state.
class StatusDot extends StatelessComponent {
  const StatusDot({super.key, required this.enabled});

  final bool enabled;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Text(
      enabled ? '●' : '○',
      style: TextStyle(color: enabled ? theme.success : theme.outline),
    );
  }
}

/// A dim section label used to separate groups of rows.
class SectionLabel extends StatelessComponent {
  const SectionLabel({super.key, required this.text});

  final String text;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: theme.outline, fontWeight: FontWeight.dim),
      ),
    );
  }
}

/// A compact, dim bar of keyboard hints separated by dots.
class HintBar extends StatelessComponent {
  const HintBar({super.key, required this.hints});

  final List<Hint> hints;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final keyStyle = TextStyle(color: theme.secondary);
    final actionStyle = TextStyle(
      color: theme.outline,
      fontWeight: FontWeight.dim,
    );
    final children = <Component>[];
    for (var index = 0; index < hints.length; index++) {
      if (index != 0) {
        children.add(Text('   ·   ', style: actionStyle));
      }
      children
        ..add(Text('${hints[index].$1} ', style: keyStyle))
        ..add(Text(hints[index].$2, style: actionStyle));
    }
    return Row(children: children);
  }
}

/// Maps a doctor status string to a theme color.
Color statusColor(TuiThemeData theme, String status) {
  return switch (status) {
    'found' => theme.success,
    'missing' => theme.error,
    'disabled' => theme.outline,
    _ => theme.onBackground,
  };
}

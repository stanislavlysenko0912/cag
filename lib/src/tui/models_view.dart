import 'package:cag/src/models/models.dart';
import 'package:nocterm/nocterm.dart';

import 'controls.dart';

/// A labelled button shown inside the custom model form.
typedef FormButton = (String icon, String label, bool danger);

/// Inner content for an agent row: an enabled dot, the name, and its default
/// model. The dot color and dimmed text convey the enabled state.
class AgentRowContent extends StatelessComponent {
  const AgentRowContent({
    super.key,
    required this.agent,
    required this.selected,
  });

  final AgentModelSettings agent;
  final bool selected;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final nameColor = agent.enabled
        ? (selected ? theme.primary : theme.onBackground)
        : theme.outline;
    return Row(
      children: [
        StatusDot(enabled: agent.enabled),
        const SizedBox(width: 1),
        Text(
          agent.displayName,
          style: TextStyle(
            color: nameColor,
            fontWeight: agent.enabled ? FontWeight.bold : FontWeight.dim,
          ),
        ),
      ],
    );
  }
}

/// Inner content for a model row: an enabled dot, an optional default star,
/// the name, and the provider identifier when it differs. Editable custom
/// rows show a trailing chevron to signal they open.
///
/// The hint and routing scores are hidden on unselected rows to keep the list
/// scannable, and expand into a fully labelled detail block beneath the
/// highlighted row. Built-in models changed by config carry an `edited` tag.
class ModelRowContent extends StatelessComponent {
  const ModelRowContent({
    super.key,
    required this.model,
    required this.selected,
    required this.isDefault,
    this.editable = false,
    this.overridden = false,
  });

  final ModelConfig model;
  final bool selected;
  final bool isDefault;
  final bool editable;
  final bool overridden;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final nameColor = model.enabled
        ? (selected ? theme.primary : theme.onBackground)
        : theme.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            StatusDot(enabled: model.enabled),
            const SizedBox(width: 1),
            Text(isDefault ? '★' : ' ', style: TextStyle(color: theme.warning)),
            const SizedBox(width: 1),
            Text(
              model.name,
              style: TextStyle(
                color: nameColor,
                fontWeight: model.enabled ? null : FontWeight.dim,
              ),
            ),
            if (overridden) ...[
              const SizedBox(width: 1),
              Text(
                'edited',
                style: TextStyle(
                  color: theme.warning,
                  fontWeight: FontWeight.dim,
                ),
              ),
            ],
            const SizedBox(width: 1),
            Expanded(
              child: Text(
                model.model == null ? '' : '→ ${model.model}',
                style: TextStyle(
                  color: theme.outline,
                  fontWeight: FontWeight.dim,
                ),
              ),
            ),
            if (editable)
              Text(
                '›',
                style: TextStyle(
                  color: selected ? theme.primary : theme.outline,
                ),
              ),
          ],
        ),
        if (selected) ..._detail(theme),
      ],
    );
  }

  List<Component> _detail(TuiThemeData theme) {
    final scores = model.scores;
    final lines = <Component>[];
    if (model.description != null) {
      lines.add(
        Text(
          model.description!,
          style: TextStyle(color: theme.outline, fontWeight: FontWeight.dim),
        ),
      );
    }
    if (scores != null) {
      lines.add(
        Text(
          'cost ${scores.cost}  ·  intelligence ${scores.intelligence}'
          '  ·  speed ${scores.speed}  ·  taste ${scores.taste}',
          style: TextStyle(color: theme.secondary),
        ),
      );
    }
    if (lines.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: lines,
        ),
      ),
    ];
  }
}

/// A form for adding or editing a custom model.
///
/// Fields and action buttons share a single focus index so the whole form is
/// navigable with the arrow keys; only the focused text field receives typing.
class CustomModelForm extends StatelessComponent {
  const CustomModelForm({
    super.key,
    required this.nameController,
    required this.descriptionController,
    required this.providerController,
    required this.costController,
    required this.intelligenceController,
    required this.speedController,
    required this.tasteController,
    required this.focusIndex,
    required this.buttons,
    required this.onKeyEvent,
  });

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController providerController;
  final TextEditingController costController;
  final TextEditingController intelligenceController;
  final TextEditingController speedController;
  final TextEditingController tasteController;
  final int focusIndex;
  final List<FormButton> buttons;
  final bool Function(KeyboardEvent event) onKeyEvent;

  @override
  Component build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormField(
          label: 'Name',
          hint: "name you'll pick in CAG",
          controller: nameController,
          focused: focusIndex == 0,
          required: true,
          onKeyEvent: onKeyEvent,
        ),
        _FormField(
          label: 'Hint',
          hint: 'optional routing hint',
          controller: descriptionController,
          focused: focusIndex == 1,
          required: false,
          onKeyEvent: onKeyEvent,
        ),
        _FormField(
          label: 'Provider model',
          hint: 'id sent to the underlying tool',
          controller: providerController,
          focused: focusIndex == 2,
          required: false,
          onKeyEvent: onKeyEvent,
        ),
        const SizedBox(height: 1),
        const SectionLabel(text: 'Scores · optional, 1-10'),
        _FormField(
          label: 'Cost',
          hint: 'higher is cheaper',
          controller: costController,
          focused: focusIndex == 3,
          required: false,
          onKeyEvent: onKeyEvent,
        ),
        _FormField(
          label: 'Intelligence',
          hint: 'reasoning strength',
          controller: intelligenceController,
          focused: focusIndex == 4,
          required: false,
          onKeyEvent: onKeyEvent,
        ),
        _FormField(
          label: 'Speed',
          hint: 'response speed',
          controller: speedController,
          focused: focusIndex == 5,
          required: false,
          onKeyEvent: onKeyEvent,
        ),
        _FormField(
          label: 'Taste',
          hint: 'output quality',
          controller: tasteController,
          focused: focusIndex == 6,
          required: false,
          onKeyEvent: onKeyEvent,
        ),
        const SizedBox(height: 1),
        for (var index = 0; index < buttons.length; index++)
          _FormButtonRow(
            button: buttons[index],
            selected: focusIndex == 7 + index,
          ),
      ],
    );
  }
}

/// A single-line labelled text input for the custom model form.
///
/// The label sits in a fixed-width column so inputs align vertically; a colored
/// `*` marks required fields, and [hint] is shown as in-field placeholder text
/// that disappears once the user types.
class _FormField extends StatelessComponent {
  const _FormField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.focused,
    required this.required,
    required this.onKeyEvent,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool focused;
  final bool required;
  final bool Function(KeyboardEvent event) onKeyEvent;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    return Row(
      children: [
        Text(
          focused ? '▌' : ' ',
          style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 1),
        SizedBox(
          width: 16,
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: focused ? theme.primary : theme.onBackground,
                  fontWeight: focused ? FontWeight.bold : null,
                ),
              ),
              if (required) Text(' *', style: TextStyle(color: theme.error)),
            ],
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(color: focused ? theme.surface : null),
            child: TextField(
              controller: controller,
              focused: focused,
              onKeyEvent: onKeyEvent,
              placeholder: hint,
              placeholderStyle: TextStyle(
                color: theme.outline,
                fontWeight: FontWeight.dim,
              ),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FormButtonRow extends StatelessComponent {
  const _FormButtonRow({required this.button, required this.selected});

  final FormButton button;
  final bool selected;

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final (icon, label, danger) = button;
    final baseColor = danger ? theme.error : theme.secondary;
    return Row(
      children: [
        Text(
          selected ? '▌' : ' ',
          style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 1),
        Text(
          '$icon  $label',
          style: TextStyle(
            color: selected
                ? (danger ? theme.error : theme.primary)
                : baseColor,
            fontWeight: selected ? FontWeight.bold : null,
          ),
        ),
      ],
    );
  }
}

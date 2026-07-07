import 'package:cag/src/detect/detect.dart';
import 'package:cag/src/doctor/doctor.dart';
import 'package:cag/src/models/models.dart';
import 'package:nocterm/nocterm.dart';

import 'controls.dart';
import 'detect_view.dart';
import 'menu_view.dart';
import 'models_view.dart';
import 'screen.dart';
import 'status_view.dart';

/// The interactive CAG terminal UI.
///
/// Navigation is entirely selection driven: arrows (or the mouse) move the
/// highlight, Enter opens the highlighted row, Space toggles it on or off, and
/// Esc goes back one level (or quits from the top). Every destructive or
/// navigational action is also reachable as a highlighted row, so no shortcut
/// needs to be memorised.
class CagTuiShell extends StatefulComponent {
  const CagTuiShell({required this.commandArgs});

  final List<String> commandArgs;

  @override
  State<CagTuiShell> createState() => _CagTuiShellState();
}

class _CagTuiShellState extends State<CagTuiShell> {
  var _screen = TuiScreen.menu;
  var _selectedIndex = 0;
  var _agentListIndex = 1;
  var _loading = false;
  DoctorReport? _statusReport;
  DetectPreview? _detectPreview;
  ModelSettingsSnapshot? _modelSettings;
  String? _openedAgent;
  var _formMode = _FormMode.none;
  String? _editingModelName;
  var _formFocusIndex = 0;
  final _customNameController = TextEditingController();
  final _customProviderController = TextEditingController();
  final _customDescriptionController = TextEditingController();
  final _costController = TextEditingController();
  final _intelligenceController = TextEditingController();
  final _speedController = TextEditingController();
  final _tasteController = TextEditingController();
  String? _error;
  String? _notice;

  _NavList _nav = _NavList();

  @override
  void initState() {
    super.initState();
    final initialScreen = _screenFromArgs(component.commandArgs);
    if (initialScreen != TuiScreen.menu) {
      _openScreen(initialScreen);
    }
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _customProviderController.dispose();
    _customDescriptionController.dispose();
    _costController.dispose();
    _intelligenceController.dispose();
    _speedController.dispose();
    _tasteController.dispose();
    super.dispose();
  }

  TuiScreen _screenFromArgs(List<String> args) {
    if (args.isEmpty) return TuiScreen.menu;
    return switch (args.first) {
      'status' => TuiScreen.status,
      'detect' => TuiScreen.detect,
      'models' => TuiScreen.models,
      _ => TuiScreen.menu,
    };
  }

  // ===== Navigation =====

  void _openScreen(TuiScreen screen) {
    setState(() {
      _screen = screen;
      _loading = screen != TuiScreen.menu;
      _selectedIndex = 0;
      _openedAgent = null;
      _agentListIndex = 1;
      _formMode = _FormMode.none;
      _editingModelName = null;
      _clearCustomForm();
      _error = null;
      _notice = null;
      _statusReport = null;
      _detectPreview = null;
      _modelSettings = null;
    });

    switch (screen) {
      case TuiScreen.status:
        _loadStatus();
      case TuiScreen.detect:
        _runDetect();
      case TuiScreen.models:
        _loadModels();
      case TuiScreen.menu:
        break;
    }
  }

  void _goBack() {
    if (_formMode != _FormMode.none) {
      _cancelForm();
      return;
    }
    if (_screen == TuiScreen.menu) {
      shutdownApp();
      return;
    }
    if (_screen == TuiScreen.models && _openedAgent != null) {
      setState(() {
        _openedAgent = null;
        _selectedIndex = _agentListIndex;
        _notice = null;
        _error = null;
      });
      return;
    }
    _backToMenu();
  }

  void _backToMenu() {
    final index = tuiMenuItems.indexWhere((item) => item.screen == _screen);
    setState(() {
      _screen = TuiScreen.menu;
      _selectedIndex = index < 0 ? 0 : index;
      _openedAgent = null;
      _loading = false;
      _error = null;
      _notice = null;
    });
  }

  void _openAgent(String name) {
    setState(() {
      _agentListIndex = _selectedIndex;
      _openedAgent = name;
      _selectedIndex = 1;
      _formMode = _FormMode.none;
      _notice = null;
      _error = null;
    });
  }

  void _move(int offset) {
    final count = _nav.length;
    if (count == 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + offset + count) % count;
    });
  }

  // ===== Data loading =====

  Future<void> _loadStatus() async {
    try {
      final report = await DoctorService().inspect(includeVersions: false);
      if (!mounted) return;
      setState(() {
        _statusReport = report;
        _loading = false;
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _runDetect() async {
    try {
      final preview = await DetectService().preview();
      if (!mounted) return;
      setState(() {
        _detectPreview = preview;
        _loading = false;
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _applyDetect() async {
    try {
      final count = _detectPreview?.changeCount ?? 0;
      await DetectService().detectAndSave();
      final preview = await DetectService().preview();
      if (!mounted) return;
      setState(() {
        _detectPreview = preview;
        _selectedIndex = 0;
        _notice = 'Applied $count change${count == 1 ? '' : 's'}';
        _error = null;
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _loadModels() async {
    try {
      final snapshot = await ModelSettingsService().load();
      if (!mounted) return;
      setState(() {
        _modelSettings = snapshot;
        _loading = false;
        if (_openedAgent == null) {
          _selectedIndex = snapshot.agents.isEmpty ? 0 : 1;
        }
      });
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _reloadModels({String? notice}) async {
    final snapshot = await ModelSettingsService().load();
    if (!mounted) return;
    setState(() {
      _modelSettings = snapshot;
      _notice = notice;
      _error = null;
    });
  }

  // ===== Mutations =====

  Future<void> _toggleAgent(AgentModelSettings agent) async {
    try {
      await ModelSettingsService().setAgentEnabled(
        agentName: agent.name,
        enabled: !agent.enabled,
      );
      await _reloadModels(
        notice:
            '${agent.displayName} ${agent.enabled ? 'disabled' : 'enabled'}',
      );
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleModel(String agentName, ModelConfig model) async {
    try {
      await ModelSettingsService().setModelEnabled(
        agentName: agentName,
        modelName: model.name,
        enabled: !model.enabled,
      );
      await _reloadModels(
        notice: '${model.name} ${model.enabled ? 'disabled' : 'enabled'}',
      );
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _setDefaultModel(String agentName, ModelConfig model) async {
    if (model.name == _selectedAgent?.defaultModel) return;
    try {
      await ModelSettingsService().setDefaultModel(
        agentName: agentName,
        modelName: model.name,
      );
      await _reloadModels(notice: '${model.name} set as default');
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _addCustomModel() async {
    final agentName = _openedAgent;
    if (agentName == null) return;
    final name = _customNameController.text.trim();
    try {
      await ModelSettingsService().addCustomModel(
        agentName: agentName,
        name: name,
        description: _customDescriptionController.text,
        providerModel: _customProviderController.text,
        scores: _parseScores(),
      );
      _closeForm();
      await _reloadModels(notice: 'Added $name');
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _updateCustomModel() async {
    final agentName = _openedAgent;
    final originalName = _editingModelName;
    if (agentName == null || originalName == null) return;
    final name = _customNameController.text.trim();
    try {
      await ModelSettingsService().updateCustomModel(
        agentName: agentName,
        originalName: originalName,
        name: name,
        description: _customDescriptionController.text,
        providerModel: _customProviderController.text,
        scores: _parseScores(),
      );
      _closeForm();
      await _reloadModels(notice: 'Updated $name');
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteCustomModel() async {
    final agentName = _openedAgent;
    final modelName = _editingModelName;
    if (agentName == null || modelName == null) return;
    try {
      await ModelSettingsService().removeCustomModel(
        agentName: agentName,
        modelName: modelName,
      );
      _closeForm();
      await _reloadModels(notice: 'Deleted $modelName');
    } on Object catch (error) {
      _showError(error);
    }
  }

  // ===== Custom model form =====

  void _startAddModel() {
    setState(() {
      _formMode = _FormMode.add;
      _editingModelName = null;
      _formFocusIndex = 0;
      _clearCustomForm();
      _notice = null;
      _error = null;
    });
  }

  void _startEditModel(ModelConfig model) {
    setState(() {
      _formMode = _FormMode.edit;
      _editingModelName = model.name;
      _formFocusIndex = 0;
      _customNameController.text = model.name;
      _customDescriptionController.text = model.description ?? '';
      _customProviderController.text = model.model ?? '';
      _fillScoreFields(model.scores);
      _notice = null;
      _error = null;
    });
  }

  void _cancelForm() {
    setState(() {
      _formMode = _FormMode.none;
      _editingModelName = null;
      _clearCustomForm();
      _notice = null;
      _error = null;
    });
  }

  void _closeForm() {
    _formMode = _FormMode.none;
    _editingModelName = null;
    _clearCustomForm();
  }

  void _submitForm() {
    if (_formMode == _FormMode.edit) {
      _updateCustomModel();
    } else {
      _addCustomModel();
    }
  }

  void _formEnter() {
    if (_formFocusIndex < _formFieldCount) {
      _submitForm();
      return;
    }
    final buttonIndex = _formFocusIndex - _formFieldCount;
    if (_formMode == _FormMode.edit && buttonIndex == 1) {
      _deleteCustomModel();
    } else {
      _submitForm();
    }
  }

  void _moveFormFocus(int offset) {
    final count = _formItemCount;
    setState(
      () => _formFocusIndex = (_formFocusIndex + offset + count) % count,
    );
  }

  void _clearCustomForm() {
    _customNameController.clear();
    _customProviderController.clear();
    _customDescriptionController.clear();
    _costController.clear();
    _intelligenceController.clear();
    _speedController.clear();
    _tasteController.clear();
  }

  void _fillScoreFields(ModelScores? scores) {
    _costController.text = scores == null ? '' : '${scores.cost}';
    _intelligenceController.text = scores == null
        ? ''
        : '${scores.intelligence}';
    _speedController.text = scores == null ? '' : '${scores.speed}';
    _tasteController.text = scores == null ? '' : '${scores.taste}';
  }

  /// Reads the four score fields into [ModelScores], or null when all are left
  /// blank.
  ///
  /// Scores are all-or-nothing: filling some but not all fields throws, as does
  /// a non-integer or out-of-range value, so the failure surfaces in the form
  /// banner.
  ModelScores? _parseScores() {
    final fields = {
      'cost': _costController.text.trim(),
      'intelligence': _intelligenceController.text.trim(),
      'speed': _speedController.text.trim(),
      'taste': _tasteController.text.trim(),
    };
    if (fields.values.every((value) => value.isEmpty)) return null;
    final values = <String, int>{};
    fields.forEach((label, raw) {
      final value = int.tryParse(raw);
      if (value == null) {
        throw FormatException('$label must be a whole number from 1 to 10');
      }
      values[label] = value;
    });
    return ModelScores(
      cost: values['cost']!,
      intelligence: values['intelligence']!,
      speed: values['speed']!,
      taste: values['taste']!,
    );
  }

  int get _formFieldCount => 7;

  List<FormButton> get _formButtons {
    return _formMode == _FormMode.edit
        ? const [('✓', 'Save changes', false), ('✕', 'Delete model', true)]
        : const [('＋', 'Add model', false)];
  }

  int get _formItemCount => _formFieldCount + _formButtons.length;

  void _showError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error.toString();
      _notice = null;
      _loading = false;
    });
  }

  // ===== Key handling =====

  bool _handleKey(KeyboardEvent event) {
    if (_handleQuitShortcut(event)) return true;
    if (_formMode != _FormMode.none) return _handleFormKey(event);
    switch (event.logicalKey) {
      case LogicalKey.escape:
        _goBack();
      case LogicalKey.arrowDown:
        _move(1);
      case LogicalKey.arrowUp:
        _move(-1);
      case LogicalKey.enter:
        _runAction((action) => action.onEnter);
      case LogicalKey.space:
        _runAction((action) => action.onSpace);
      case LogicalKey.keyD:
        _runAction((action) => action.onDefault);
      default:
        return false;
    }
    return true;
  }

  bool _handleFormKey(KeyboardEvent event) {
    if (_handleQuitShortcut(event)) return true;
    switch (event.logicalKey) {
      case LogicalKey.escape:
        _cancelForm();
      case LogicalKey.arrowDown:
        _moveFormFocus(1);
      case LogicalKey.arrowUp:
        _moveFormFocus(-1);
      case LogicalKey.enter:
        _formEnter();
      default:
        return false;
    }
    return true;
  }

  bool _handleQuitShortcut(KeyboardEvent event) {
    if (event.logicalKey != LogicalKey.keyC || !event.isControlPressed) {
      return false;
    }
    shutdownApp();
    return true;
  }

  void _runAction(VoidCallback? Function(_NavAction) select) {
    if (_selectedIndex < 0 || _selectedIndex >= _nav.length) return;
    select(_nav.actions[_selectedIndex])?.call();
  }

  // ===== Build =====

  @override
  Component build(BuildContext context) {
    final theme = TuiTheme.of(context);
    final nav = _NavList();
    final body = _buildBody(nav);
    _nav = nav;
    return Focusable(
      focused: true,
      onKeyEvent: _handleKey,
      child: Container(
        decoration: BoxDecoration(color: theme.background),
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(theme),
            const SizedBox(height: 1),
            Expanded(child: body),
            const SizedBox(height: 1),
            HintBar(hints: _hints()),
          ],
        ),
      ),
    );
  }

  Component _header(TuiThemeData theme) {
    final subtitleStyle = TextStyle(
      color: theme.outline,
      fontWeight: FontWeight.dim,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Row(
        children: [
          Text(
            '◆ CAG',
            style: TextStyle(color: theme.primary, fontWeight: FontWeight.bold),
          ),
          Text('  /  ', style: subtitleStyle),
          Text('CLI wrapper for AI agents', style: subtitleStyle),
        ],
      ),
    );
  }

  List<Hint> _hints() {
    if (_formMode != _FormMode.none) {
      return const [
        ('↑↓', 'move'),
        ('enter', 'confirm'),
        ('esc', 'cancel'),
        ('^C', 'quit'),
      ];
    }
    return switch (_screen) {
      TuiScreen.menu => const [
        ('↑↓', 'navigate'),
        ('enter', 'open'),
        ('esc', 'quit'),
        ('^C', 'quit'),
      ],
      TuiScreen.models when _openedAgent == null => const [
        ('↑↓', 'navigate'),
        ('enter', 'open'),
        ('space', 'toggle'),
        ('esc', 'back'),
        ('^C', 'quit'),
      ],
      TuiScreen.models => const [
        ('↑↓', 'navigate'),
        ('enter', 'select'),
        ('space', 'toggle'),
        ('d', 'default'),
        ('esc', 'back'),
        ('^C', 'quit'),
      ],
      _ => const [
        ('↑↓', 'navigate'),
        ('enter', 'select'),
        ('esc', 'back'),
        ('^C', 'quit'),
      ],
    };
  }

  Component _buildBody(_NavList nav) {
    return switch (_screen) {
      TuiScreen.menu => _buildMenu(nav),
      TuiScreen.status => _buildInfo(
        nav,
        'Status',
        StatusView(loading: _loading, report: _statusReport),
      ),
      TuiScreen.detect => _buildDetect(nav),
      TuiScreen.models => _buildModels(nav),
    };
  }

  Component _buildMenu(_NavList nav) {
    return Panel(
      title: 'Menu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in tuiMenuItems)
            _navRow(
              nav,
              onEnter: () => _openScreen(item.screen),
              builder: (selected) => MenuRowContent(
                title: item.title,
                description: item.description,
                selected: selected,
              ),
            ),
        ],
      ),
    );
  }

  Component _buildInfo(_NavList nav, String title, Component content) {
    return Panel(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backRow(nav),
          const SizedBox(height: 1),
          ..._banner(),
          content,
        ],
      ),
    );
  }

  Component _buildDetect(_NavList nav) {
    final theme = TuiTheme.of(context);
    if (_loading) {
      return _buildInfo(
        nav,
        'Detect',
        Text('Detecting agent CLIs…', style: TextStyle(color: theme.outline)),
      );
    }

    final preview = _detectPreview;
    if (preview == null) {
      return _buildInfo(nav, 'Detect', const SizedBox());
    }

    return Panel(
      title: 'Detect',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backRow(nav),
          const SizedBox(height: 1),
          ..._banner(),
          DetectView(preview: preview),
          const SizedBox(height: 1),
          if (preview.hasChanges)
            _navRow(
              nav,
              onEnter: _applyDetect,
              builder: (selected) => ActionRowContent(
                icon: '✓',
                label:
                    'Apply ${preview.changeCount} '
                    'change${preview.changeCount == 1 ? '' : 's'}',
                selected: selected,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                'Everything is up to date',
                style: TextStyle(
                  color: theme.outline,
                  fontWeight: FontWeight.dim,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Component _buildModels(_NavList nav) {
    final theme = TuiTheme.of(context);
    if (_loading) {
      return _buildInfo(
        nav,
        'Models',
        Text('Loading models…', style: TextStyle(color: theme.outline)),
      );
    }

    final agents = _modelSettings?.agents ?? const <AgentModelSettings>[];
    final agent = _selectedAgent;
    if (_openedAgent == null || agent == null) {
      return _buildAgentList(nav, agents);
    }
    return _buildAgentDetail(nav, agent);
  }

  Component _buildAgentList(_NavList nav, List<AgentModelSettings> agents) {
    return Panel(
      title: 'Models',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backRow(nav),
          const SizedBox(height: 1),
          ..._banner(),
          for (final agent in agents)
            _navRow(
              nav,
              onEnter: () => _openAgent(agent.name),
              onSpace: () => _toggleAgent(agent),
              builder: (selected) =>
                  AgentRowContent(agent: agent, selected: selected),
            ),
        ],
      ),
    );
  }

  Component _buildAgentDetail(_NavList nav, AgentModelSettings agent) {
    if (_formMode != _FormMode.none) {
      final prefix = _formMode == _FormMode.edit ? 'Edit' : 'New';
      return Panel(
        title: '$prefix model · ${agent.displayName}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._banner(),
            CustomModelForm(
              nameController: _customNameController,
              descriptionController: _customDescriptionController,
              providerController: _customProviderController,
              costController: _costController,
              intelligenceController: _intelligenceController,
              speedController: _speedController,
              tasteController: _tasteController,
              focusIndex: _formFocusIndex,
              buttons: _formButtons,
              onKeyEvent: _handleQuitShortcut,
            ),
          ],
        ),
      );
    }

    return Panel(
      title: agent.displayName,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _backRow(nav),
          const SizedBox(height: 1),
          ..._banner(),
          // const SectionLabel(text: 'Included models'),
          for (final model in agent.standardModels)
            _navRow(
              nav,
              onEnter: () => _toggleModel(agent.name, model),
              onSpace: () => _toggleModel(agent.name, model),
              onDefault: () => _setDefaultModel(agent.name, model),
              builder: (selected) => ModelRowContent(
                model: model,
                selected: selected,
                isDefault: model.name == agent.defaultModel,
                overridden: agent.isOverridden(model),
              ),
            ),
          if (agent.customModels.isNotEmpty) ...[
            const SizedBox(height: 1),
            const SectionLabel(text: 'Custom models'),
          ],
          for (final model in agent.customModels)
            _navRow(
              nav,
              onEnter: () => _startEditModel(model),
              onSpace: () => _toggleModel(agent.name, model),
              onDefault: () => _setDefaultModel(agent.name, model),
              builder: (selected) => ModelRowContent(
                model: model,
                selected: selected,
                isDefault: model.name == agent.defaultModel,
                editable: true,
              ),
            ),
          const SizedBox(height: 1),
          _navRow(
            nav,
            onEnter: _startAddModel,
            builder: (selected) => ActionRowContent(
              icon: '＋',
              label: 'Add custom model',
              selected: selected,
            ),
          ),
        ],
      ),
    );
  }

  Component _backRow(_NavList nav) {
    return _navRow(
      nav,
      onEnter: _goBack,
      builder: (selected) =>
          ActionRowContent(icon: '←', label: 'Back', selected: selected),
    );
  }

  /// A transient banner shown above screen content: the error takes precedence,
  /// otherwise the success notice. Rendered inline so the screen stays navigable
  /// instead of being replaced by a full-screen error.
  List<Component> _banner() {
    if (_error != null) return [_errorLine(_error!)];
    if (_notice != null) return [_noticeLine(_notice!)];
    return const [];
  }

  Component _noticeLine(String notice) {
    final theme = TuiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text(notice, style: TextStyle(color: theme.success)),
    );
  }

  Component _errorLine(String error) {
    final theme = TuiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Text('✕ $error', style: TextStyle(color: theme.error)),
    );
  }

  Component _navRow(
    _NavList nav, {
    required Component Function(bool selected) builder,
    VoidCallback? onEnter,
    VoidCallback? onSpace,
    VoidCallback? onDefault,
  }) {
    final index = nav.add(
      _NavAction(onEnter: onEnter, onSpace: onSpace, onDefault: onDefault),
    );
    final selected = index == _selectedIndex;
    return NavRow(
      selected: selected,
      onTap: () {
        setState(() => _selectedIndex = index);
        onEnter?.call();
      },
      onHover: () {
        if (_selectedIndex != index) {
          setState(() => _selectedIndex = index);
        }
      },
      child: builder(selected),
    );
  }

  AgentModelSettings? get _selectedAgent {
    final name = _openedAgent;
    if (name == null) return null;
    for (final agent
        in _modelSettings?.agents ?? const <AgentModelSettings>[]) {
      if (agent.name == name) return agent;
    }
    return null;
  }
}

/// An ordered registry of focusable actions for the current screen.
///
/// Rows register themselves as they are built, guaranteeing the navigation
/// order matches the visual order without manual index bookkeeping.
class _NavList {
  final List<_NavAction> actions = [];

  int get length => actions.length;

  int add(_NavAction action) {
    actions.add(action);
    return actions.length - 1;
  }
}

class _NavAction {
  const _NavAction({this.onEnter, this.onSpace, this.onDefault});

  final VoidCallback? onEnter;
  final VoidCallback? onSpace;
  final VoidCallback? onDefault;
}

/// The current mode of the custom model form.
enum _FormMode { none, add, edit }

import '../agents/agent_catalog.dart';
import '../config/agent_config_override.dart';
import '../config/app_config.dart';
import '../config/config_service.dart';
import 'agent_models.dart';
import 'model_config.dart';

class ModelSettingsSnapshot {
  const ModelSettingsSnapshot({required this.agents});

  final List<AgentModelSettings> agents;
}

class AgentModelSettings {
  const AgentModelSettings({
    required this.name,
    required this.displayName,
    required this.enabled,
    required this.defaultModel,
    required this.standardModels,
    required this.customModels,
    required this.overriddenModelNames,
  });

  final String name;
  final String displayName;
  final bool enabled;
  final String defaultModel;
  final List<ModelConfig> standardModels;
  final List<ModelConfig> customModels;

  /// Names of built-in models whose definition is changed by config beyond
  /// their enabled state (provider id, hint, scores, or aliases).
  final Set<String> overriddenModelNames;

  /// Whether [model] is a built-in whose definition is overridden by config.
  bool isOverridden(ModelConfig model) => overriddenModelNames.contains(model.name);
}

class ModelSettingsService {
  ModelSettingsService({String? configPath, ConfigService? configService})
    : _configService = configService ?? ConfigService(configPath: configPath);

  final ConfigService _configService;

  Future<ModelSettingsSnapshot> load() async {
    final appConfig = await _configService.loadOrCreate();
    final resolvedConfigs = AgentCatalog.resolveConfigs(
      _configService,
      appConfig,
    );

    return ModelSettingsSnapshot(
      agents: [
        for (final definition in AgentCatalog.definitions)
          _agentSettings(
            definition: definition,
            override: appConfig.agents[definition.name],
            enabled: resolvedConfigs[definition.name]?.enabled ?? false,
            defaultModel: definition.defaultModel(
              resolvedConfigs[definition.name]!,
            ),
          ),
      ],
    );
  }

  Future<void> setDefaultModel({
    required String agentName,
    required String modelName,
  }) async {
    final config = await _configService.loadOrCreate();
    final agents = Map<String, AgentConfigOverride>.from(config.agents);
    agents[agentName] = _mergeOverride(
      current: agents[agentName],
      defaultModel: modelName,
    );
    await _configService.save(AppConfig(agents: agents));
  }

  Future<void> setAgentEnabled({
    required String agentName,
    required bool enabled,
  }) async {
    final config = await _configService.loadOrCreate();
    final agents = Map<String, AgentConfigOverride>.from(config.agents);
    agents[agentName] = _mergeOverride(
      current: agents[agentName],
      enabled: enabled,
    );
    await _configService.save(AppConfig(agents: agents));
  }

  Future<void> setModelEnabled({
    required String agentName,
    required String modelName,
    required bool enabled,
  }) async {
    final config = await _configService.loadOrCreate();
    final agents = Map<String, AgentConfigOverride>.from(config.agents);
    final current = agents[agentName];
    final models = [...?current?.models];
    final index = models.indexWhere((model) => model.name == modelName);

    if (index == -1) {
      final standardModel = _findModel(
        AgentModelRegistry.modelsFor(agentName),
        modelName,
      );
      if (standardModel == null) return;
      models.add(_copyModel(standardModel, enabled: enabled));
    } else {
      models[index] = _copyModel(models[index], enabled: enabled);
    }

    agents[agentName] = _mergeOverride(current: current, models: models);
    await _configService.save(AppConfig(agents: agents));
  }

  Future<void> addCustomModel({
    required String agentName,
    required String name,
    required String description,
    String? providerModel,
    ModelScores? scores,
  }) async {
    final modelName = _requireField(name, 'Model name');
    final modelDescription = _blankToNull(description);

    final config = await _configService.loadOrCreate();
    final agents = Map<String, AgentConfigOverride>.from(config.agents);
    final current = agents[agentName];
    final models = [...?current?.models];
    final model = ModelConfig(
      name: modelName,
      model: _blankToNull(providerModel),
      description: modelDescription,
      scores: scores,
    );

    final index = models.indexWhere((item) => item.name == model.name);
    if (index == -1) {
      models.add(model);
    } else {
      models[index] = model;
    }

    agents[agentName] = _mergeOverride(current: current, models: models);
    await _configService.save(AppConfig(agents: agents));
  }

  /// Updates an existing custom model, preserving its enabled state and
  /// following renames through the agent's default model reference.
  Future<void> updateCustomModel({
    required String agentName,
    required String originalName,
    required String name,
    required String description,
    String? providerModel,
    ModelScores? scores,
  }) async {
    final modelName = _requireField(name, 'Model name');
    final modelDescription = _blankToNull(description);

    final config = await _configService.loadOrCreate();
    final agents = Map<String, AgentConfigOverride>.from(config.agents);
    final current = agents[agentName];
    final models = [...?current?.models];
    final index = models.indexWhere((item) => item.name == originalName);
    final updated = ModelConfig(
      name: modelName,
      model: _blankToNull(providerModel),
      description: modelDescription,
      scores: scores,
      enabled: index == -1 ? true : models[index].enabled,
    );

    if (index == -1) {
      models.add(updated);
    } else {
      models[index] = updated;
    }

    agents[agentName] = _rebuildOverride(
      current,
      models: models,
      defaultModel: current?.defaultModel == originalName
          ? modelName
          : current?.defaultModel,
    );
    await _configService.save(AppConfig(agents: agents));
  }

  /// Removes a custom model and clears it as the default when needed.
  Future<void> removeCustomModel({
    required String agentName,
    required String modelName,
  }) async {
    final config = await _configService.loadOrCreate();
    final agents = Map<String, AgentConfigOverride>.from(config.agents);
    final current = agents[agentName];
    final models = [...?current?.models]
      ..removeWhere((item) => item.name == modelName);

    agents[agentName] = _rebuildOverride(
      current,
      models: models,
      defaultModel: current?.defaultModel == modelName
          ? null
          : current?.defaultModel,
    );
    await _configService.save(AppConfig(agents: agents));
  }

  AgentModelSettings _agentSettings({
    required AgentDefinition definition,
    required AgentConfigOverride? override,
    required bool enabled,
    required String defaultModel,
  }) {
    final standardModels = definition.defaultConfig.availableModels.isEmpty
        ? AgentModelRegistry.modelsFor(definition.name)
        : definition.defaultConfig.availableModels;
    final overrides = {
      for (final model in override?.models ?? []) model.name: model,
    };
    final resolvedStandardModels = [
      for (final model in standardModels)
        if (overrides[model.name] case final overrideModel?)
          _mergeModel(model, overrideModel)
        else
          model,
    ];
    final overriddenModelNames = {
      for (final model in standardModels)
        if (overrides[model.name] case final overrideModel?)
          if (_isContentOverridden(model, _mergeModel(model, overrideModel)))
            model.name,
    };
    final standardNames = standardModels.map((model) => model.name).toSet();
    final customModels = [
      for (final model in override?.models ?? const <ModelConfig>[])
        if (!standardNames.contains(model.name)) model,
    ];

    return AgentModelSettings(
      name: definition.name,
      displayName: definition.displayName,
      enabled: enabled,
      defaultModel: defaultModel,
      standardModels: resolvedStandardModels,
      customModels: customModels,
      overriddenModelNames: overriddenModelNames,
    );
  }

  /// Whether [resolved] changes [base] in any field shown to the user other
  /// than its enabled state, which is toggled through the normal UI.
  bool _isContentOverridden(ModelConfig base, ModelConfig resolved) {
    return base.model != resolved.model ||
        base.description != resolved.description ||
        base.scores != resolved.scores ||
        !_sameStrings(base.aliases, resolved.aliases);
  }

  bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  AgentConfigOverride _mergeOverride({
    required AgentConfigOverride? current,
    bool? enabled,
    String? defaultModel,
    List<ModelConfig>? models,
  }) {
    return AgentConfigOverride(
      executable: current?.executable,
      enabled: enabled ?? current?.enabled,
      defaultModel: defaultModel ?? current?.defaultModel,
      additionalArgs: current?.additionalArgs,
      env: current?.env,
      hardTimeoutSeconds: current?.hardTimeoutSeconds,
      idleTimeoutSeconds: current?.idleTimeoutSeconds,
      shellExecutable: current?.shellExecutable,
      shellArgs: current?.shellArgs,
      shellCommandPrefix: current?.shellCommandPrefix,
      models: models ?? current?.models,
    );
  }

  AgentConfigOverride _rebuildOverride(
    AgentConfigOverride? current, {
    required List<ModelConfig> models,
    required String? defaultModel,
  }) {
    return AgentConfigOverride(
      executable: current?.executable,
      enabled: current?.enabled,
      defaultModel: defaultModel,
      additionalArgs: current?.additionalArgs,
      env: current?.env,
      hardTimeoutSeconds: current?.hardTimeoutSeconds,
      idleTimeoutSeconds: current?.idleTimeoutSeconds,
      shellExecutable: current?.shellExecutable,
      shellArgs: current?.shellArgs,
      shellCommandPrefix: current?.shellCommandPrefix,
      models: models,
    );
  }

  String _requireField(String value, String label) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('$label is required.');
    }
    return trimmed;
  }

  ModelConfig _mergeModel(ModelConfig base, ModelConfig override) {
    return ModelConfig(
      name: base.name,
      model: override.model ?? base.model,
      description: _blankToNull(override.description) ?? base.description,
      scores: override.scores ?? base.scores,
      isDefault: override.isDefault || base.isDefault,
      enabled: override.enabled,
      aliases: override.aliases.isEmpty ? base.aliases : override.aliases,
    );
  }

  ModelConfig _copyModel(ModelConfig model, {required bool enabled}) {
    return ModelConfig(
      name: model.name,
      model: model.model,
      description: model.description,
      scores: model.scores,
      isDefault: model.isDefault,
      enabled: enabled,
      aliases: model.aliases,
    );
  }

  ModelConfig? _findModel(List<ModelConfig> models, String name) {
    for (final model in models) {
      if (model.name == name) return model;
    }
    return null;
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }
}

import '../config/app_config.dart';

class DoctorReport {
  const DoctorReport({
    required this.config,
    required this.agents,
    required this.mcp,
    required this.summary,
  });

  final ConfigDiagnostic config;
  final List<AgentDiagnostic> agents;
  final McpDiagnostic mcp;
  final DoctorSummary summary;

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'agents': agents.map((agent) => agent.toJson()).toList(),
    'mcp': mcp.toJson(),
    'summary': summary.toJson(),
  };
}

class ConfigDiagnostic {
  const ConfigDiagnostic({
    required this.path,
    required this.exists,
    required this.valid,
    required this.status,
    required this.appConfig,
    this.error,
  });

  factory ConfigDiagnostic.invalid({
    required String path,
    required String error,
  }) {
    return ConfigDiagnostic(
      path: path,
      exists: true,
      valid: false,
      status: 'invalid',
      error: error,
      appConfig: AppConfig.defaults(),
    );
  }

  final String path;
  final bool exists;
  final bool valid;
  final String status;
  final String? error;
  final AppConfig appConfig;

  Map<String, dynamic> toJson() => {
    'path': path,
    'exists': exists,
    'valid': valid,
    if (error != null) 'error': error,
  };
}

class AgentDiagnostic {
  const AgentDiagnostic({
    required this.name,
    required this.enabled,
    required this.executable,
    required this.available,
    required this.defaultModel,
    required this.modelCount,
    required this.authStatus,
    required this.executionMode,
    required this.status,
    this.version,
    this.hint,
  });

  final String name;
  final bool enabled;
  final String executable;
  final bool available;
  final String defaultModel;
  final int modelCount;
  final String authStatus;
  final String executionMode;
  final String? version;
  final String status;
  final String? hint;

  Map<String, dynamic> toJson() => {
    'name': name,
    'enabled': enabled,
    'executable': executable,
    'available': available,
    'default_model': defaultModel,
    'model_count': modelCount,
    'auth_status': authStatus,
    'execution_mode': executionMode,
    if (version != null) 'version': version,
    'status': status,
    if (hint != null) 'hint': hint,
  };
}

class McpDiagnostic {
  const McpDiagnostic({
    required this.checked,
    this.url,
    this.reachable,
    this.statusCode,
    this.error,
  });

  final bool checked;
  final String? url;
  final bool? reachable;
  final int? statusCode;
  final String? error;

  Map<String, dynamic> toJson() => {
    'checked': checked,
    if (url != null) 'url': url,
    if (reachable != null) 'reachable': reachable,
    if (statusCode != null) 'statusCode': statusCode,
    if (error != null) 'error': error,
  };
}

class DoctorSummary {
  const DoctorSummary({
    required this.ok,
    required this.warn,
    required this.fail,
  });

  final int ok;
  final int warn;
  final int fail;

  Map<String, dynamic> toJson() => {'ok': ok, 'warn': warn, 'fail': fail};
}

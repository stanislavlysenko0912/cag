import 'dart:io';

import 'package:path/path.dart' as p;

class AppPaths {
  AppPaths._();

  static const appDirName = 'cag';

  static String dataHome() {
    if (Platform.isWindows) {
      return _firstNonEmpty([Platform.environment['APPDATA'], Platform.environment['LOCALAPPDATA'], Platform.environment['USERPROFILE']]) ??
          Directory.current.path;
    }

    if (Platform.isMacOS) {
      final home = _homeDir();
      if (home == null) return Directory.current.path;
      return home;
    }

    final xdgData = Platform.environment['XDG_DATA_HOME'];
    if (xdgData != null && xdgData.isNotEmpty) {
      return xdgData;
    }

    final home = _homeDir();
    if (home == null) return Directory.current.path;
    return p.join(home, '.local', 'share');
  }

  static String appDataDir() {
    return Platform.isMacOS ? p.join(dataHome(), '.$appDirName') : p.join(dataHome(), appDirName);
  }

  static String consensusPath() {
    return p.join(appDataDir(), 'consensus.jsonl');
  }

  static String configPath() {
    return p.join(appDataDir(), 'config.json');
  }

  static String schemaPath() {
    return p.join(appDataDir(), 'config.schema.json');
  }

  static String? _homeDir() {
    return _firstNonEmpty([Platform.environment['HOME'], Platform.environment['USERPROFILE'], Platform.environment['HOMEPATH']]);
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

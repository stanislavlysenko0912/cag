import 'dart:io';

bool isExecutableAvailable(String executable) {
  final trimmed = executable.trim();
  if (trimmed.isEmpty) return false;

  return Platform.isWindows
      ? _isWindowsExecutableAvailable(trimmed)
      : _isPosixExecutableAvailable(trimmed);
}

bool _isPosixExecutableAvailable(String executable) {
  if (_hasPathSeparator(executable)) {
    return File(executable).existsSync();
  }

  final path = Platform.environment['PATH'];
  if (path == null || path.isEmpty) return false;

  for (final dir in path.split(':')) {
    if (dir.isEmpty) continue;
    final candidate = File('$dir/$executable');
    if (candidate.existsSync()) return true;
  }

  return false;
}

bool _isWindowsExecutableAvailable(String executable) {
  final hasPath = _hasPathSeparator(executable);
  final hasExtension = _hasExtension(executable);
  final extensions = _windowsExtensions();

  if (hasPath) {
    if (File(executable).existsSync()) return true;
    if (!hasExtension) {
      for (final extension in extensions) {
        if (File('$executable$extension').existsSync()) return true;
      }
    }
    return false;
  }

  final path = Platform.environment['PATH'];
  if (path == null || path.isEmpty) return false;

  for (final dir in path.split(';')) {
    if (dir.isEmpty) continue;
    if (hasExtension) {
      if (File('$dir\\$executable').existsSync()) return true;
      continue;
    }
    for (final extension in extensions) {
      if (File('$dir\\$executable$extension').existsSync()) return true;
    }
  }

  return false;
}

bool _hasPathSeparator(String value) =>
    value.contains('/') || value.contains(r'\');

bool _hasExtension(String path) {
  final lastSlash = path.lastIndexOf('/');
  final lastBackslash = path.lastIndexOf(r'\');
  final lastSeparator = lastSlash > lastBackslash ? lastSlash : lastBackslash;
  final lastDot = path.lastIndexOf('.');
  return lastDot > lastSeparator;
}

List<String> _windowsExtensions() {
  final pathext = Platform.environment['PATHEXT'];
  if (pathext == null || pathext.trim().isEmpty) {
    return const ['.exe', '.cmd', '.bat'];
  }
  return pathext
      .split(';')
      .where((entry) => entry.trim().isNotEmpty)
      .map((entry) => entry.trim().toLowerCase())
      .toList();
}

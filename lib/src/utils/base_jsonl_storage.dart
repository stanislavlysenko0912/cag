import 'dart:convert';
import 'dart:io';

/// Generic JSONL-backed storage for simple ID-addressable records.
class BaseJsonlStorage<T> {
  /// Creates a storage backed by a JSONL file.
  BaseJsonlStorage({
    required String storagePath,
    required T Function(Map<String, dynamic> json) fromJson,
    required Map<String, dynamic> Function(T value) toJson,
    required String Function(T value) getId,
    StringSink? warningSink,
  }) : _storagePath = storagePath,
       _fromJson = fromJson,
       _toJson = toJson,
       _getId = getId,
       _warningSink = warningSink ?? stderr;

  final String _storagePath;
  final T Function(Map<String, dynamic> json) _fromJson;
  final Map<String, dynamic> Function(T value) _toJson;
  final String Function(T value) _getId;
  final StringSink _warningSink;

  File get _file => File(_storagePath);

  Future<void> _ensureDirectory() async {
    final dir = _file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Saves a new or existing record.
  Future<void> save(T value) async {
    await _ensureDirectory();

    final values = await loadAll();
    final index = values.indexWhere((item) => _getId(item) == _getId(value));
    if (index >= 0) {
      values[index] = value;
    } else {
      values.add(value);
    }

    final lines = values.map((item) => jsonEncode(_toJson(item))).join('\n');
    await _file.writeAsString(lines.isEmpty ? '' : '$lines\n');
  }

  /// Loads a record by identifier.
  Future<T?> load(String id) async {
    final values = await loadAll();
    try {
      return values.firstWhere((value) => _getId(value) == id);
    } catch (_) {
      return null;
    }
  }

  /// Loads all records from storage.
  Future<List<T>> loadAll() async {
    if (!await _file.exists()) {
      return [];
    }

    final content = await _file.readAsString();
    if (content.trim().isEmpty) {
      return [];
    }

    final values = <T>[];
    final lines = content.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (line.trim().isEmpty) {
        continue;
      }

      final value = _parseLine(line, index + 1);
      if (value != null) {
        values.add(value);
      }
    }
    return values;
  }

  /// Deletes a record by identifier.
  Future<void> delete(String id) async {
    final values = await loadAll();
    values.removeWhere((value) => _getId(value) == id);

    if (values.isEmpty) {
      if (await _file.exists()) {
        await _file.delete();
      }
      return;
    }

    final lines = values.map((item) => jsonEncode(_toJson(item))).join('\n');
    await _file.writeAsString('$lines\n');
  }

  T? _parseLine(String line, int lineNumber) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) {
        _warn(lineNumber, 'expected a JSON object');
        return null;
      }
      return _fromJson(decoded);
    } on FormatException catch (error) {
      _warn(lineNumber, error.message);
      return null;
    } catch (error) {
      _warn(lineNumber, error.toString());
      return null;
    }
  }

  void _warn(int lineNumber, String reason) {
    _warningSink.writeln(
      'Warning: skipped invalid record in $_storagePath:$lineNumber: $reason',
    );
  }
}

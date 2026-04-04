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
  }) : _storagePath = storagePath,
       _fromJson = fromJson,
       _toJson = toJson,
       _getId = getId;

  final String _storagePath;
  final T Function(Map<String, dynamic> json) _fromJson;
  final Map<String, dynamic> Function(T value) _toJson;
  final String Function(T value) _getId;

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

    return content
        .trim()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => _fromJson(jsonDecode(line) as Map<String, dynamic>))
        .toList();
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
}

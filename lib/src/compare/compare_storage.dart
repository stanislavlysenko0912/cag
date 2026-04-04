import 'dart:convert';
import 'dart:io';

import '../utils/app_paths.dart';
import 'compare_model.dart';

/// Storage for compare runs using JSONL format.
class CompareStorage {
  /// Creates compare storage.
  CompareStorage({String? storagePath})
    : _storagePath = storagePath ?? AppPaths.comparePath();

  final String _storagePath;

  File get _file => File(_storagePath);

  Future<void> _ensureDirectory() async {
    final dir = _file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Save a compare run.
  Future<void> save(CompareRun run) async {
    await _ensureDirectory();

    final runs = await loadAll();
    final index = runs.indexWhere((item) => item.compareId == run.compareId);
    if (index >= 0) {
      run.updatedAt = DateTime.now();
      runs[index] = run;
    } else {
      runs.add(run);
    }

    final lines = runs.map((item) => jsonEncode(item.toJson())).join('\n');
    await _file.writeAsString(lines.isEmpty ? '' : '$lines\n');
  }

  /// Load a compare run by ID.
  Future<CompareRun?> load(String compareId) async {
    final runs = await loadAll();
    try {
      return runs.firstWhere((run) => run.compareId == compareId);
    } catch (_) {
      return null;
    }
  }

  /// Load all compare runs.
  Future<List<CompareRun>> loadAll() async {
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
        .map(
          (line) =>
              CompareRun.fromJson(jsonDecode(line) as Map<String, dynamic>),
        )
        .toList();
  }
}

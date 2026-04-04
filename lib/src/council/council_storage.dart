import 'dart:convert';
import 'dart:io';

import '../utils/app_paths.dart';
import 'council_model.dart';

/// Storage for council runs using JSONL format.
class CouncilStorage {
  /// Creates council storage.
  CouncilStorage({String? storagePath})
    : _storagePath = storagePath ?? AppPaths.councilPath();

  final String _storagePath;

  File get _file => File(_storagePath);

  Future<void> _ensureDirectory() async {
    final dir = _file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Saves a council run.
  Future<void> save(CouncilRun run) async {
    await _ensureDirectory();

    final runs = await loadAll();
    final index = runs.indexWhere((item) => item.councilId == run.councilId);
    if (index >= 0) {
      run.updatedAt = DateTime.now();
      runs[index] = run;
    } else {
      runs.add(run);
    }

    final lines = runs.map((item) => jsonEncode(item.toJson())).join('\n');
    await _file.writeAsString(lines.isEmpty ? '' : '$lines\n');
  }

  /// Loads a council run by ID.
  Future<CouncilRun?> load(String councilId) async {
    final runs = await loadAll();
    try {
      return runs.firstWhere((run) => run.councilId == councilId);
    } catch (_) {
      return null;
    }
  }

  /// Loads all council runs.
  Future<List<CouncilRun>> loadAll() async {
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
              CouncilRun.fromJson(jsonDecode(line) as Map<String, dynamic>),
        )
        .toList();
  }
}

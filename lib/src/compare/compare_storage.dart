import '../utils/app_paths.dart';
import '../utils/base_jsonl_storage.dart';
import 'compare_model.dart';

/// Storage for compare runs using JSONL format.
class CompareStorage {
  /// Creates compare storage.
  CompareStorage({String? storagePath})
    : _storage = BaseJsonlStorage<CompareRun>(
        storagePath: storagePath ?? AppPaths.comparePath(),
        fromJson: CompareRun.fromJson,
        toJson: (run) => run.toJson(),
        getId: (run) => run.compareId,
      );

  final BaseJsonlStorage<CompareRun> _storage;

  /// Save a compare run.
  Future<void> save(CompareRun run) async {
    if (await load(run.compareId) != null) {
      run.updatedAt = DateTime.now();
    }
    await _storage.save(run);
  }

  /// Load a compare run by ID.
  Future<CompareRun?> load(String compareId) => _storage.load(compareId);

  /// Load all compare runs.
  Future<List<CompareRun>> loadAll() => _storage.loadAll();
}

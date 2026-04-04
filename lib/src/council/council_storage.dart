import '../utils/app_paths.dart';
import '../utils/base_jsonl_storage.dart';
import 'council_model.dart';

/// Storage for council runs using JSONL format.
class CouncilStorage {
  /// Creates council storage.
  CouncilStorage({String? storagePath})
    : _storage = BaseJsonlStorage<CouncilRun>(
        storagePath: storagePath ?? AppPaths.councilPath(),
        fromJson: CouncilRun.fromJson,
        toJson: (run) => run.toJson(),
        getId: (run) => run.councilId,
      );

  final BaseJsonlStorage<CouncilRun> _storage;

  /// Saves a council run.
  Future<void> save(CouncilRun run) async {
    if (await load(run.councilId) != null) {
      run.updatedAt = DateTime.now();
    }
    await _storage.save(run);
  }

  /// Loads a council run by ID.
  Future<CouncilRun?> load(String councilId) => _storage.load(councilId);

  /// Loads all council runs.
  Future<List<CouncilRun>> loadAll() => _storage.loadAll();
}

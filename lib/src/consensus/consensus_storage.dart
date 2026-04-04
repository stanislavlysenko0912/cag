import '../utils/app_paths.dart';
import '../utils/base_jsonl_storage.dart';
import 'consensus_model.dart';

/// Storage for consensus sessions using JSONL format.
class ConsensusStorage {
  ConsensusStorage({String? storagePath})
    : _storage = BaseJsonlStorage<ConsensusSession>(
        storagePath: storagePath ?? _defaultPath,
        fromJson: ConsensusSession.fromJson,
        toJson: (session) => session.toJson(),
        getId: (session) => session.consensusId,
      );

  static String get _defaultPath {
    return AppPaths.consensusPath();
  }

  final BaseJsonlStorage<ConsensusSession> _storage;

  /// Save a new or updated session.
  Future<void> save(ConsensusSession session) async {
    if (await load(session.consensusId) != null) {
      session.updatedAt = DateTime.now();
    }
    await _storage.save(session);
  }

  /// Load session by consensus ID.
  Future<ConsensusSession?> load(String consensusId) =>
      _storage.load(consensusId);

  /// Load all sessions.
  Future<List<ConsensusSession>> loadAll() => _storage.loadAll();

  /// Delete a session by ID.
  Future<void> delete(String consensusId) => _storage.delete(consensusId);
}

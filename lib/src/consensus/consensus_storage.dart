import 'dart:convert';
import 'dart:io';

import 'consensus_model.dart';
import '../utils/app_paths.dart';

/// Storage for consensus sessions using JSONL format.
class ConsensusStorage {
  ConsensusStorage({String? storagePath})
    : _storagePath = storagePath ?? _defaultPath;

  final String _storagePath;

  static String get _defaultPath {
    return AppPaths.consensusPath();
  }

  File get _file => File(_storagePath);

  /// Ensure storage directory exists.
  Future<void> _ensureDirectory() async {
    final dir = _file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Save a new or updated session.
  Future<void> save(ConsensusSession session) async {
    await _ensureDirectory();

    // Read all sessions, update or add
    final sessions = await loadAll();
    final index = sessions.indexWhere(
      (s) => s.consensusId == session.consensusId,
    );

    if (index >= 0) {
      session.updatedAt = DateTime.now();
      sessions[index] = session;
    } else {
      sessions.add(session);
    }

    // Write all sessions back
    final lines = sessions.map((s) => jsonEncode(s.toJson())).join('\n');
    await _file.writeAsString(lines.isEmpty ? '' : '$lines\n');
  }

  /// Load session by consensus ID.
  Future<ConsensusSession?> load(String consensusId) async {
    final sessions = await loadAll();
    try {
      return sessions.firstWhere((s) => s.consensusId == consensusId);
    } catch (_) {
      return null;
    }
  }

  /// Load all sessions.
  Future<List<ConsensusSession>> loadAll() async {
    if (!await _file.exists()) {
      return [];
    }

    final content = await _file.readAsString();
    if (content.trim().isEmpty) {
      return [];
    }

    final lines = content.trim().split('\n');
    return lines.where((line) => line.trim().isNotEmpty).map((line) {
      final json = jsonDecode(line) as Map<String, dynamic>;
      return ConsensusSession.fromJson(json);
    }).toList();
  }

  /// Delete a session by ID.
  Future<void> delete(String consensusId) async {
    final sessions = await loadAll();
    sessions.removeWhere((s) => s.consensusId == consensusId);

    if (sessions.isEmpty) {
      if (await _file.exists()) {
        await _file.delete();
      }
      return;
    }

    final lines = sessions.map((s) => jsonEncode(s.toJson())).join('\n');
    await _file.writeAsString('$lines\n');
  }
}

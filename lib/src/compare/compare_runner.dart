import 'dart:async';

import 'package:uuid/uuid.dart';

import '../agents/agents.dart';
import '../models/agent_execution.dart';
import '../models/models.dart';
import 'compare_model.dart';
import 'compare_storage.dart';

/// Runs compare by calling multiple agents in parallel.
class CompareRunner {
  /// Creates a compare runner with optional dependencies.
  CompareRunner({
    CompareStorage? storage,
    GeminiAgent? geminiAgent,
    CodexAgent? codexAgent,
    CursorAgent? cursorAgent,
    ClaudeAgent? claudeAgent,
  }) : _storage = storage ?? CompareStorage(),
       _geminiAgent = geminiAgent ?? GeminiAgent(),
       _codexAgent = codexAgent ?? CodexAgent(),
       _cursorAgent = cursorAgent ?? CursorAgent(),
       _claudeAgent = claudeAgent ?? ClaudeAgent();

  final CompareStorage _storage;
  final GeminiAgent _geminiAgent;
  final CodexAgent _codexAgent;
  final CursorAgent _cursorAgent;
  final ClaudeAgent _claudeAgent;

  static const _uuid = Uuid();

  /// Run a new compare request.
  Future<CompareRun> run({
    required String prompt,
    required String title,
    required List<CompareParticipant> participants,
  }) async {
    if (participants.length < 2) {
      throw ArgumentError('Compare requires at least 2 participants');
    }

    final results = await Future.wait(
      participants.map((participant) => _runParticipant(prompt, participant)),
    );
    final now = DateTime.now();
    final run = CompareRun(
      compareId: 'cmp_${_uuid.v4().substring(0, 8)}',
      title: title,
      prompt: prompt,
      participants: participants,
      results: results,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.save(run);
    return run;
  }

  BaseAgent _getAgent(String agentName) {
    return switch (agentName) {
      'gemini' => _geminiAgent,
      'codex' => _codexAgent,
      'cursor' => _cursorAgent,
      'claude' => _claudeAgent,
      _ => throw ArgumentError('Unknown agent: $agentName'),
    };
  }

  Future<CompareParticipantResult> _runParticipant(
    String prompt,
    CompareParticipant participant,
  ) async {
    try {
      final agent = _getAgent(participant.agent);
      final response = await agent.execute(
        prompt: prompt,
        model: participant.resolvedModel,
      );
      return CompareParticipantResult(
        participant: participant.copyWith(sessionId: response.sessionId),
        response: response,
      );
    } on AgentExecutionException catch (error) {
      return CompareParticipantResult(
        participant: participant,
        failure: error.failure,
      );
    } catch (error) {
      return CompareParticipantResult(
        participant: participant,
        failure: AgentFailure(
          reason: AgentExitReason.crash,
          message: error.toString(),
        ),
      );
    }
  }
}

import 'dart:async';

import 'package:uuid/uuid.dart';

import '../agents/agents.dart';
import '../models/models.dart';
import 'consensus_model.dart';
import 'consensus_storage.dart';
import 'prompt.dart';

/// Result from a single participant in consensus.
class ParticipantResult {
  ParticipantResult({
    required this.participant,
    required this.response,
    this.error,
  });

  final ConsensusParticipant participant;
  final ParsedResponse? response;
  final String? error;

  bool get success => error == null && response != null;
}

/// Result from consensus run.
class ConsensusResult {
  ConsensusResult({required this.session, required this.results});

  final ConsensusSession session;
  final List<ParticipantResult> results;

  bool get allSucceeded => results.every((r) => r.success);
  List<ParticipantResult> get successful =>
      results.where((r) => r.success).toList();
  List<ParticipantResult> get failed =>
      results.where((r) => !r.success).toList();
}

/// Runs consensus by calling multiple agents in parallel.
class ConsensusRunner {
  ConsensusRunner({
    ConsensusStorage? storage,
    GeminiAgent? geminiAgent,
    CodexAgent? codexAgent,
    CursorAgent? cursorAgent,
    ClaudeAgent? claudeAgent,
  }) : _storage = storage ?? ConsensusStorage(),
       _geminiAgent = geminiAgent ?? GeminiAgent(),
       _codexAgent = codexAgent ?? CodexAgent(),
       _cursorAgent = cursorAgent ?? CursorAgent(),
       _claudeAgent = claudeAgent ?? ClaudeAgent();

  final ConsensusStorage _storage;
  final GeminiAgent _geminiAgent;
  final CodexAgent _codexAgent;
  final CursorAgent _cursorAgent;
  final ClaudeAgent _claudeAgent;

  static const _uuid = Uuid();

  /// Stance-specific prompts mapping.
  static const stancePrompts = {
    ConsensusStance.forProposal: stancePromptFor,
    ConsensusStance.against: stancePromptAgainst,
    ConsensusStance.neutral: stancePromptNeutral,
  };

  /// Build system prompt for a participant.
  String buildSystemPrompt(ConsensusParticipant participant) {
    final stancePrompt =
        participant.stancePrompt ?? stancePrompts[participant.stance] ?? '';
    return consensusPrompt.replaceAll('{stance_prompt}', stancePrompt);
  }

  /// Get agent for participant.
  BaseAgent _getAgent(String agentName) {
    return switch (agentName) {
      'gemini' => _geminiAgent,
      'codex' => _codexAgent,
      'cursor' => _cursorAgent,
      'claude' => _claudeAgent,
      _ => throw ArgumentError('Unknown agent: $agentName'),
    };
  }

  /// Run a new consensus.
  Future<ConsensusResult> run({
    required String prompt,
    required List<ConsensusParticipant> participants,
    String? proposal,
  }) async {
    if (participants.length < 2) {
      throw ArgumentError('Consensus requires at least 2 participants');
    }

    // Create session
    final session = ConsensusSession(
      consensusId: 'cons-${_uuid.v4().substring(0, 8)}',
      prompt: prompt,
      proposal: proposal,
      participants: participants,
      createdAt: DateTime.now(),
    );

    // Build full prompt with proposal context if provided
    final fullPrompt = _buildFullPrompt(prompt, proposal);

    // Run all agents in parallel
    final results = await _runParticipants(
      prompt: fullPrompt,
      participants: participants,
    );

    // Update session with session IDs
    for (final result in results) {
      if (result.response?.sessionId != null) {
        result.participant.sessionId = result.response!.sessionId;
      }
    }

    // Save session
    await _storage.save(session);

    return ConsensusResult(session: session, results: results);
  }

  /// Resume an existing consensus session.
  Future<ConsensusResult> resume({
    required String consensusId,
    required String prompt,
  }) async {
    final session = await _storage.load(consensusId);
    if (session == null) {
      throw ArgumentError('Consensus session not found: $consensusId');
    }

    // Build full prompt with original proposal context if it exists
    final fullPrompt = _buildFullPrompt(prompt, session.proposal);

    // Run all agents with their saved session IDs
    final results = await _runParticipants(
      prompt: fullPrompt,
      participants: session.participants,
      useResume: true,
    );

    // Update session with new session IDs (if changed)
    for (final result in results) {
      if (result.response?.sessionId != null) {
        result.participant.sessionId = result.response!.sessionId;
      }
    }

    // Save updated session
    session.updatedAt = DateTime.now();
    await _storage.save(session);

    return ConsensusResult(session: session, results: results);
  }

  /// Run all participants in parallel.
  Future<List<ParticipantResult>> _runParticipants({
    required String prompt,
    required List<ConsensusParticipant> participants,
    bool useResume = false,
  }) async {
    final futures = participants.map((p) async {
      try {
        final agent = _getAgent(p.agent);
        final systemPrompt = buildSystemPrompt(p);

        final response = await agent.execute(
          prompt: prompt,
          model: p.resolvedModel,
          systemPrompt: systemPrompt,
          resume: useResume ? p.sessionId : null,
        );

        return ParticipantResult(participant: p, response: response);
      } catch (e) {
        return ParticipantResult(
          participant: p,
          response: null,
          error: e.toString(),
        );
      }
    });

    return Future.wait(futures);
  }

  /// Build full prompt combining agent's proposal with user context.
  String _buildFullPrompt(String prompt, String? proposal) {
    if (proposal == null || proposal.isEmpty) {
      return '<task>\n$prompt\n</task>';
    }

    return '''<context>
$prompt
</context>

<proposal>
$proposal
</proposal>

Evaluate this proposal given the context above.''';
  }
}

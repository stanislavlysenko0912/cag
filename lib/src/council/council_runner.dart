import 'dart:async';

import '../agents/agents.dart';
import '../models/models.dart';
import 'council_model.dart';
import 'council_prompt.dart';

/// Result from a single participant response.
///
/// Captures the answer stage output per participant.
class CouncilParticipantResult {
  /// Creates a participant result.
  ///
  /// Provide response or error.
  CouncilParticipantResult({
    required this.participant,
    required this.response,
    this.error,
  });

  /// Participant details.
  final CouncilMember participant;

  /// Parsed response.
  final ParsedResponse? response;

  /// Error message when execution failed.
  final String? error;

  /// Whether the participant succeeded.
  bool get success => error == null && response != null;
}

/// Result from a single participant review.
///
/// Captures the review stage output per participant.
class CouncilReviewResult {
  /// Creates a review result.
  ///
  /// Provide response or error.
  CouncilReviewResult({
    required this.participant,
    required this.response,
    this.error,
  });

  /// Participant details.
  final CouncilMember participant;

  /// Parsed response.
  final ParsedResponse? response;

  /// Error message when execution failed.
  final String? error;

  /// Whether the participant succeeded.
  bool get success => error == null && response != null;
}

/// Result from the chairman synthesis.
///
/// Captures the final stage output.
class CouncilChairmanResult {
  /// Creates a chairman result.
  ///
  /// Provide response or error.
  CouncilChairmanResult({
    required this.chairman,
    required this.response,
    this.error,
  });

  /// Chairman member.
  final CouncilMember chairman;

  /// Parsed response.
  final ParsedResponse? response;

  /// Error message when execution failed.
  final String? error;

  /// Whether the chairman succeeded.
  bool get success => error == null && response != null;
}

/// Aggregated result from a council run.
///
/// Groups stage outputs into a single result.
class CouncilResult {
  /// Creates a council result payload.
  ///
  /// Includes stage outputs and request context.
  CouncilResult({
    required this.prompt,
    required this.participants,
    required this.chairmanMember,
    required this.answers,
    required this.reviews,
    required this.chairman,
  });

  /// Original prompt for the council run.
  final String prompt;

  /// Participants for the run.
  final List<CouncilMember> participants;

  /// Chairman for the run.
  final CouncilMember chairmanMember;

  /// Stage 1 answers.
  final List<CouncilParticipantResult> answers;

  /// Stage 2 reviews.
  final List<CouncilReviewResult> reviews;

  /// Stage 3 chairman response.
  final CouncilChairmanResult chairman;
}

/// Runs council stages: answers, reviews, chairman synthesis.
///
/// Uses separate sessions for the chairman stage.
class CouncilRunner {
  /// Creates a council runner with optional dependencies.
  ///
  /// Provide agents to customize behavior.
  CouncilRunner({
    GeminiAgent? geminiAgent,
    CodexAgent? codexAgent,
    ClaudeAgent? claudeAgent,
  }) : _geminiAgent = geminiAgent ?? GeminiAgent(),
       _codexAgent = codexAgent ?? CodexAgent(),
       _claudeAgent = claudeAgent ?? ClaudeAgent();

  final GeminiAgent _geminiAgent;
  final CodexAgent _codexAgent;
  final ClaudeAgent _claudeAgent;

  /// Run a new council request.
  Future<CouncilResult> run({
    required String prompt,
    required List<CouncilMember> participants,
    required CouncilMember chairman,
  }) async {
    if (participants.length < 2) {
      throw ArgumentError('Council requires at least 2 participants');
    }

    final answers = await _runStage1(
      prompt: prompt,
      participants: participants,
    );
    final reviews = await _runStage2(
      prompt: prompt,
      participants: participants,
      stage1Results: answers,
    );
    final chairmanAnswers = _buildAnswersForChairman(answers);
    final chairmanResult = await _runStage3(
      prompt: prompt,
      chairman: chairman,
      answers: chairmanAnswers,
      reviews: _buildReviewsForChairman(reviews),
    );

    return CouncilResult(
      prompt: prompt,
      participants: participants,
      chairmanMember: chairman,
      answers: answers,
      reviews: reviews,
      chairman: chairmanResult,
    );
  }

  BaseAgent _getAgent(String agentName) {
    return switch (agentName) {
      'gemini' => _geminiAgent,
      'codex' => _codexAgent,
      'claude' => _claudeAgent,
      _ => throw ArgumentError('Unknown agent: $agentName'),
    };
  }

  Future<List<CouncilParticipantResult>> _runStage1({
    required String prompt,
    required List<CouncilMember> participants,
  }) async {
    final futures = participants.map((p) async {
      try {
        final agent = _getAgent(p.agent);
        final response = await agent.execute(
          prompt: prompt,
          model: p.resolvedModel,
          resume: null,
        );
        return CouncilParticipantResult(participant: p, response: response);
      } catch (e) {
        return CouncilParticipantResult(
          participant: p,
          response: null,
          error: e.toString(),
        );
      }
    });

    return Future.wait(futures);
  }

  Future<List<CouncilReviewResult>> _runStage2({
    required String prompt,
    required List<CouncilMember> participants,
    required List<CouncilParticipantResult> stage1Results,
  }) async {
    if (participants.length != stage1Results.length) {
      throw StateError('Stage 1 results mismatch participants length.');
    }
    final futures = <Future<CouncilReviewResult>>[];
    for (var i = 0; i < participants.length; i++) {
      final p = participants[i];
      final stage1 = stage1Results[i];
      if (!stage1.success) {
        futures.add(
          Future.value(
            CouncilReviewResult(
              participant: p,
              response: null,
              error: 'Stage 1 response missing for ${p.agent}',
            ),
          ),
        );
        continue;
      }

      futures.add(() async {
        try {
          final agent = _getAgent(p.agent);
          final reviewAnswers = _buildAnswersForReview(
            stage1Results,
            excludeIndex: i,
          );
          final reviewPrompt = buildCouncilReviewPrompt(
            question: prompt,
            answers: reviewAnswers,
          );
          final response = await agent.execute(
            prompt: reviewPrompt,
            model: p.resolvedModel,
            resume: null,
          );
          return CouncilReviewResult(participant: p, response: response);
        } catch (e) {
          return CouncilReviewResult(
            participant: p,
            response: null,
            error: e.toString(),
          );
        }
      }());
    }

    return Future.wait(futures);
  }

  Future<CouncilChairmanResult> _runStage3({
    required String prompt,
    required CouncilMember chairman,
    required List<CouncilAnswer> answers,
    required List<CouncilReview> reviews,
  }) async {
    try {
      final agent = _getAgent(chairman.agent);
      final chairmanPrompt = buildCouncilChairmanPrompt(
        question: prompt,
        answers: answers,
        reviews: reviews,
      );
      final response = await agent.execute(
        prompt: chairmanPrompt,
        model: chairman.resolvedModel,
      );
      return CouncilChairmanResult(chairman: chairman, response: response);
    } catch (e) {
      return CouncilChairmanResult(
        chairman: chairman,
        response: null,
        error: e.toString(),
      );
    }
  }

  List<CouncilAnswer> _buildAnswersForReview(
    List<CouncilParticipantResult> results, {
    int? excludeIndex,
  }) {
    final answers = <CouncilAnswer>[];
    var labelIndex = 0;
    for (var i = 0; i < results.length; i++) {
      if (excludeIndex != null && i == excludeIndex) {
        continue;
      }
      final answerId = 'ans_${labelIndex + 1}';
      final label = 'Answer ${labelIndex + 1}';
      labelIndex += 1;
      final result = results[i];
      final content = result.success
          ? result.response!.content
          : 'ERROR: ${result.error ?? 'Unknown error'}';
      answers.add(
        CouncilAnswer(answerId: answerId, label: label, content: content),
      );
    }
    return answers;
  }

  List<CouncilAnswer> _buildAnswersForChairman(
    List<CouncilParticipantResult> results,
  ) {
    final answers = <CouncilAnswer>[];
    for (var i = 0; i < results.length; i++) {
      final answerId = 'ans_${i + 1}';
      final participant = results[i].participant;
      final label = '${participant.agent.toUpperCase()} (${participant.model})';
      final result = results[i];
      final content = result.success
          ? result.response!.content
          : 'ERROR: ${result.error ?? 'Unknown error'}';
      answers.add(
        CouncilAnswer(answerId: answerId, label: label, content: content),
      );
    }
    return answers;
  }

  List<CouncilReview> _buildReviewsForChairman(
    List<CouncilReviewResult> results,
  ) {
    final reviews = <CouncilReview>[];
    for (final result in results) {
      final reviewerLabel =
          '${result.participant.agent.toUpperCase()} (${result.participant.model})';
      final content = result.success
          ? result.response!.content
          : 'ERROR: ${result.error ?? 'Unknown error'}';
      reviews.add(
        CouncilReview(reviewerLabel: reviewerLabel, content: content),
      );
    }
    return reviews;
  }
}

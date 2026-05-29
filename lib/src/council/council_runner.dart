import 'dart:async';

import 'package:uuid/uuid.dart';

import '../agents/agents.dart';
import '../models/models.dart';
import 'council_model.dart';
import 'council_prompt.dart';
import 'council_storage.dart';

/// Runs council stages: answers, reviews, chairman synthesis.
class CouncilRunner {
  /// Creates a council runner with optional dependencies.
  CouncilRunner({
    CouncilStorage? storage,
    GeminiAgent? geminiAgent,
    CodexAgent? codexAgent,
    CursorAgent? cursorAgent,
    ClaudeAgent? claudeAgent,
    Map<String, AgentConfig> agentConfigs = const {},
  }) : _storage = storage ?? CouncilStorage(),
       _agentRegistry = AgentRegistry(
         geminiAgent: geminiAgent,
         codexAgent: codexAgent,
         cursorAgent: cursorAgent,
         claudeAgent: claudeAgent,
         agentConfigs: agentConfigs,
       );

  final CouncilStorage _storage;
  final AgentRegistry _agentRegistry;

  static const _uuid = Uuid();

  /// Runs a new council request and persists the result.
  Future<CouncilRun> run({
    required String prompt,
    required String title,
    required List<CouncilMember> participants,
    required CouncilMember chairman,
  }) async {
    if (participants.length < 2) {
      throw ArgumentError('Council requires at least 2 participants');
    }

    final answers = await _runStage1(prompt, participants);
    final reviews = await _runStage2(prompt, participants, answers);
    final chairmanResult = await _runStage3(
      prompt: prompt,
      chairman: chairman,
      answers: _buildAnswersForChairman(answers),
      reviews: _buildReviewsForChairman(reviews),
    );

    final now = DateTime.now();
    final run = CouncilRun(
      councilId: 'council_${_uuid.v4().substring(0, 8)}',
      title: title,
      prompt: prompt,
      participants: participants,
      chairman: chairman,
      answers: answers,
      reviews: reviews,
      chairmanResult: chairmanResult,
      createdAt: now,
      updatedAt: now,
    );
    await _storage.save(run);
    return run;
  }

  Future<List<CouncilParticipantResult>> _runStage1(
    String prompt,
    List<CouncilMember> participants,
  ) {
    final futures = participants.map(
      (participant) => _runAnswer(prompt, participant),
    );
    return Future.wait(futures);
  }

  Future<CouncilParticipantResult> _runAnswer(
    String prompt,
    CouncilMember participant,
  ) async {
    try {
      final agent = _agentRegistry.get(participant.agent);
      final response = await agent.execute(
        prompt: prompt,
        model: participant.resolvedModel,
        resume: null,
      );
      return CouncilParticipantResult(
        participant: participant.copyWith(sessionId: response.sessionId),
        response: response,
      );
    } on AgentExecutionException catch (error) {
      return CouncilParticipantResult(
        participant: participant,
        response: null,
        failure: error.failure,
      );
    } catch (error) {
      return CouncilParticipantResult(
        participant: participant,
        response: null,
        failure: AgentFailure(
          reason: AgentExitReason.crash,
          message: error.toString(),
        ),
      );
    }
  }

  Future<List<CouncilReviewResult>> _runStage2(
    String prompt,
    List<CouncilMember> participants,
    List<CouncilParticipantResult> stage1Results,
  ) {
    if (participants.length != stage1Results.length) {
      throw StateError('Stage 1 results mismatch participants length.');
    }

    final futures = <Future<CouncilReviewResult>>[];
    for (var index = 0; index < participants.length; index++) {
      futures.add(
        _runReview(prompt, participants[index], stage1Results, index),
      );
    }
    return Future.wait(futures);
  }

  Future<CouncilReviewResult> _runReview(
    String prompt,
    CouncilMember participant,
    List<CouncilParticipantResult> stage1Results,
    int excludeIndex,
  ) async {
    final stage1 = stage1Results[excludeIndex];
    if (!stage1.success) {
      return CouncilReviewResult(
        participant: participant,
        response: null,
        failure: AgentFailure(
          reason: AgentExitReason.crash,
          message: 'Stage 1 response missing for ${participant.agent}',
        ),
      );
    }

    try {
      final agent = _agentRegistry.get(participant.agent);
      final reviewPrompt = buildCouncilReviewPrompt(
        question: prompt,
        answers: _buildAnswersForReview(
          stage1Results,
          excludeIndex: excludeIndex,
        ),
      );
      final response = await agent.execute(
        prompt: reviewPrompt,
        model: participant.resolvedModel,
        resume: null,
      );
      return CouncilReviewResult(participant: participant, response: response);
    } on AgentExecutionException catch (error) {
      return CouncilReviewResult(
        participant: participant,
        response: null,
        failure: error.failure,
      );
    } catch (error) {
      return CouncilReviewResult(
        participant: participant,
        response: null,
        failure: AgentFailure(
          reason: AgentExitReason.crash,
          message: error.toString(),
        ),
      );
    }
  }

  Future<CouncilChairmanResult> _runStage3({
    required String prompt,
    required CouncilMember chairman,
    required List<CouncilAnswer> answers,
    required List<CouncilReview> reviews,
  }) async {
    try {
      final agent = _agentRegistry.get(chairman.agent);
      final chairmanPrompt = buildCouncilChairmanPrompt(
        question: prompt,
        answers: answers,
        reviews: reviews,
      );
      final response = await agent.execute(
        prompt: chairmanPrompt,
        model: chairman.resolvedModel,
        resume: null,
      );
      return CouncilChairmanResult(chairman: chairman, response: response);
    } on AgentExecutionException catch (error) {
      return CouncilChairmanResult(
        chairman: chairman,
        response: null,
        failure: error.failure,
      );
    } catch (error) {
      return CouncilChairmanResult(
        chairman: chairman,
        response: null,
        failure: AgentFailure(
          reason: AgentExitReason.crash,
          message: error.toString(),
        ),
      );
    }
  }

  List<CouncilAnswer> _buildAnswersForReview(
    List<CouncilParticipantResult> stage1Results, {
    required int excludeIndex,
  }) {
    final answers = <CouncilAnswer>[];
    var answerNumber = 1;

    for (var index = 0; index < stage1Results.length; index++) {
      if (index == excludeIndex) {
        continue;
      }

      final result = stage1Results[index];
      if (!result.success || result.response == null) {
        continue;
      }
      answers.add(
        CouncilAnswer(
          answerId: 'ans_$answerNumber',
          label: 'Answer $answerNumber',
          content: result.response!.content.trim(),
        ),
      );
      answerNumber++;
    }

    return answers;
  }

  List<CouncilAnswer> _buildAnswersForChairman(
    List<CouncilParticipantResult> answers,
  ) {
    final chairmanAnswers = <CouncilAnswer>[];
    for (var index = 0; index < answers.length; index++) {
      final result = answers[index];
      final label = 'ans_${index + 1}';
      final content = result.success && result.response != null
          ? result.response!.content.trim()
          : 'ERROR: ${result.failure}';
      chairmanAnswers.add(
        CouncilAnswer(
          answerId: label,
          label:
              '${result.participant.agent.toUpperCase()} (${result.participant.model})',
          content: content,
        ),
      );
    }
    return chairmanAnswers;
  }

  List<CouncilReview> _buildReviewsForChairman(
    List<CouncilReviewResult> reviews,
  ) {
    final chairmanReviews = <CouncilReview>[];
    for (final review in reviews) {
      final content = review.success && review.response != null
          ? review.response!.content.trim()
          : 'ERROR: ${review.failure}';
      chairmanReviews.add(
        CouncilReview(
          reviewerLabel:
              '${review.participant.agent.toUpperCase()} (${review.participant.model})',
          content: content,
        ),
      );
    }
    return chairmanReviews;
  }
}
